# frozen_string_literal: true

module WhereIsMyFriends
  class DynamicFeed
    # Responsible for all read-side queries against the dynamic-topic corpus.
    # Every method returns a plain Ruby value (Hash or Hash-of-Hashes) so the
    # caller never needs to touch ActiveRecord directly.
    class Queries
      def initialize(viewer:, guardian:, category:, serializer:)
        @viewer = viewer
        @guardian = guardian
        @category = category
        @serializer = serializer
      end

      # Paginated member feed ordered by id desc.
      def feed(username:, before_id: nil)
        member = User.find_by(username_lower: username.to_s.downcase)
        raise Discourse::NotFound unless @guardian.can_see_profile?(member)

        topics = visible_topics.where(user_id: member.id)
        topics =
          topics.where("topics.id < ?", before_id.to_i) if before_id.to_i.positive?
        page = topics.order(id: :desc).limit(PAGE_SIZE + 1).to_a
        has_more = page.length > PAGE_SIZE
        page = page.first(PAGE_SIZE)

        {
          dynamics: @serializer.serialize_many(page),
          has_more: has_more,
          before_id: has_more ? page.last.id : nil
        }
      end

      # Latest dynamic per unique author within the recent window (home widget).
      def recent
        topics = latest_topics_by_author(visible_topics).limit(RECENT_LIMIT)
        { dynamics: @serializer.serialize_many(topics) }
      end

      # Author-diverse discover feed, excluding the viewer's own dynamics.
      def discover(before_id: nil, limit: nil)
        page_size = discovery_page_size(limit)
        scope =
          visible_topics
            .where("topics.created_at >= ?", RECENT_WINDOW.ago)
            .where.not(user_id: @viewer.id)
        scope = before_cursor(scope, before_id)

        page = latest_topics_by_author(scope).limit(page_size + 1).to_a
        has_more = page.length > page_size
        page = page.first(page_size)

        {
          dynamics: @serializer.serialize_many(page),
          has_more: has_more,
          before_id: has_more ? page.last.id : nil
        }
      end

      # Returns a single visible Topic by id, or nil if not found/accessible.
      # Used by Reactor to look up a reactionable topic via the shared scope.
      def visible_topic_by_id(topic_id)
        visible_topics.find_by(id: topic_id.to_i)
      end

      # Returns a Hash of { user_id => serialized_dynamic } for a batch of user
      # ids — used by the member-card hover previews.
      def latest_by_user_ids(user_ids)
        ids = Array(user_ids).map(&:to_i).uniq
        return {} if ids.empty?

        topics = latest_topics_by_author(visible_topics.where(user_id: ids)).to_a
        serialized = @serializer.serialize_many(topics)
        topics.each_with_index.to_h { |topic, index| [topic.user_id, serialized[index]] }
      end

      private

      def discovery_page_size(limit)
        requested = limit.to_i
        return DISCOVERY_PAGE_SIZE unless requested.positive?

        requested.clamp(1, DISCOVERY_PAGE_SIZE)
      end

      def visible_topics
        topics =
          Topic
            .joins(
              "INNER JOIN topic_custom_fields AS dynamic_fields " \
                "ON dynamic_fields.topic_id = topics.id " \
                "AND dynamic_fields.name = #{Topic.connection.quote(FIELD)}"
            )
            .joins(
              "INNER JOIN posts AS dynamic_first_posts " \
                "ON dynamic_first_posts.topic_id = topics.id " \
                "AND dynamic_first_posts.post_number = 1"
            )
            .where(
              archetype: Archetype.default,
              visible: true,
              deleted_at: nil,
              category_id: @category.id
            )
            .where(
              "dynamic_first_posts.deleted_at IS NULL " \
                "AND dynamic_first_posts.hidden = FALSE " \
                "AND dynamic_first_posts.post_type = ?",
              Post.types[:regular]
            )
            .secured(@guardian)
            .includes(:first_post, :user)

        ignored_ids = @viewer.ignored_user_ids
        topics = topics.where.not(user_id: ignored_ids) if ignored_ids.present?
        topics
      end

      def latest_topics_by_author(scope)
        latest_ids =
          scope
            .where("topics.created_at >= ?", RECENT_WINDOW.ago)
            .reorder(
              Arel.sql("topics.user_id, topics.created_at DESC, topics.id DESC")
            )
            .select(Arel.sql("DISTINCT ON (topics.user_id) topics.id"))

        scope.where(id: latest_ids).order(created_at: :desc, id: :desc)
      end

      def before_cursor(scope, before_id)
        cursor_id = before_id.to_i
        return scope unless cursor_id.positive?

        cursor = Topic.find_by(id: cursor_id)
        return scope.where("topics.id < ?", cursor_id) unless cursor

        scope.where(
          "topics.created_at < :created_at OR " \
            "(topics.created_at = :created_at AND topics.id < :id)",
          created_at: cursor.created_at,
          id: cursor.id
        )
      end
    end
  end
end

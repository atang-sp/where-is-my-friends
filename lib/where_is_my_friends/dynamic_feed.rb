# frozen_string_literal: true

module WhereIsMyFriends
  class DynamicFeed
    FIELD = "where_is_my_friends_dynamic"
    PAGE_SIZE = 20
    DISCOVERY_PAGE_SIZE = 10
    RECENT_LIMIT = 3
    RECENT_WINDOW = 30.days
    MIN_VISIBLE_CHARACTERS = 8
    MAX_VISIBLE_CHARACTERS = 500
    CREATION_CONTEXT_KEY = :where_is_my_friends_dynamic_creation
    INTERNAL_CREATION_PARAM = :where_is_my_friends_dynamic
    MEDIA_PATTERN =
      %r{
      upload://|
      /uploads/|
      !\[[^\]]*\]\s*(?:\(|\[)|
      \[img(?:=[^\]]+)?\]|
      <\s*(?:img|picture|video|audio|source|object|embed|iframe|svg)\b
    }ix
    COOKED_MEDIA_SELECTOR =
      "img:not(.emoji), picture, video, audio, source, object, embed, iframe, svg"

    class InvalidContent < StandardError
    end

    class InvalidReaction < StandardError
    end

    def initialize(viewer:, guardian: nil)
      @viewer = viewer
      @guardian = guardian || Guardian.new(viewer)
      ensure_available!
    end

    def feed(username:, before_id: nil)
      member = User.find_by(username_lower: username.to_s.downcase)
      raise Discourse::NotFound unless @guardian.can_see_profile?(member)

      topics = visible_topics.where(user_id: member.id)
      topics =
        topics.where(
          "topics.id < ?",
          before_id.to_i
        ) if before_id.to_i.positive?
      page = topics.order(id: :desc).limit(PAGE_SIZE + 1).to_a
      has_more = page.length > PAGE_SIZE
      page = page.first(PAGE_SIZE)

      {
        dynamics: serialize_many(page),
        has_more: has_more,
        before_id: has_more ? page.last.id : nil
      }
    end

    def recent
      topics = latest_topics_by_author(visible_topics).limit(RECENT_LIMIT)

      { dynamics: serialize_many(topics) }
    end

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
        dynamics: serialize_many(page),
        has_more: has_more,
        before_id: has_more ? page.last.id : nil
      }
    end

    def latest_by_user_ids(user_ids)
      ids = Array(user_ids).map(&:to_i).uniq
      return {} if ids.empty?

      topics = latest_topics_by_author(visible_topics.where(user_id: ids)).to_a
      serialized = serialize_many(topics)
      topics.each_with_index.to_h do |topic, index|
        [topic.user_id, serialized[index]]
      end
    end

    def create(raw:)
      validate_content!(raw)
      result =
        self.class.with_creation_context do
          NewPostManager.new(
            @viewer,
            :raw => raw.to_s,
            :title => self.class.title_for(raw),
            :category => @category.id,
            :archetype => Archetype.default,
            :guardian => @guardian,
            :cooking_options => self.class.plain_link_cooking_options,
            INTERNAL_CREATION_PARAM => true
          ).perform
        end

      unless result.success?
        raise InvalidContent, result.errors.full_messages.to_sentence
      end

      if result.post
        { queued: false, dynamic: serialize_many([result.post.topic]).first }
      else
        { queued: true }
      end
    end

    def react(topic_id:, kind:)
      topic = reactionable_topic(topic_id)
      reaction_kind = kind.to_s
      if WhereIsMyFriendsDynamicReaction::KINDS.exclude?(reaction_kind)
        raise InvalidReaction,
              I18n.t("where_is_my_friends.dynamics.invalid_reaction")
      end

      reaction =
        WhereIsMyFriendsDynamicReaction.find_or_initialize_by(
          topic: topic,
          user: @viewer
        )
      if reaction.persisted? && reaction.kind == reaction_kind
        return { reaction: reaction.kind }
      end

      begin
        RateLimiter.new(
          @viewer,
          "where-is-my-friends-dynamic-reaction",
          40,
          1.day
        ).performed!
      rescue RateLimiter::LimitExceeded
        raise InvalidReaction,
              I18n.t("where_is_my_friends.dynamics.reaction_rate_limit")
      end

      event_name =
        if reaction.persisted?
          "dynamic_reaction_changed"
        else
          "dynamic_reaction_added"
        end
      WhereIsMyFriendsDynamicReaction.transaction do
        reaction.update!(kind: reaction_kind)
        sync_reaction_notification!(reaction, topic)
      end
      record_reaction_event(event_name)

      { reaction: reaction.kind }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      raise InvalidReaction,
            I18n.t("where_is_my_friends.dynamics.invalid_reaction")
    end

    def unreact(topic_id:)
      topic = reactionable_topic(topic_id)
      reaction =
        WhereIsMyFriendsDynamicReaction.find_by(topic: topic, user: @viewer)
      return { reaction: nil } unless reaction

      WhereIsMyFriendsDynamicReaction.transaction do
        reaction.notification&.destroy!
        reaction.destroy!
      end
      record_reaction_event("dynamic_reaction_removed")

      { reaction: nil }
    end

    def self.dynamic?(topic)
      ActiveModel::Type::Boolean.new.cast(topic&.custom_fields&.[](FIELD))
    end

    def self.creating?
      ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY] == true
    end

    def self.with_creation_context
      previous = ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY]
      ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[CREATION_CONTEXT_KEY] = previous
    end

    def self.visible_text(raw, document: cooked_document(raw))
      document
        .css("img.emoji")
        .each do |emoji|
          replacement = emoji["title"].presence || emoji["alt"].presence || ""
          emoji.replace(Nokogiri::XML::Text.new(replacement, document))
        end
      document.text.gsub(/\s+/, " ").strip
    end

    def self.title_for(raw, at: Time.current)
      maximum = SiteSetting.max_topic_title_length
      suffix = "#{at.utc.strftime("%y%m%d%H%M%S")}-#{SecureRandom.hex(3)}"
      separator = " · "
      return suffix.last(maximum) if maximum <= suffix.length + separator.length

      summary_limit = [maximum - suffix.length - separator.length, 100].min
      summary = visible_text(raw).truncate(summary_limit, omission: "")
      "#{summary}#{separator}#{suffix}"
    end

    def self.disable_oneboxes!(document)
      document
        .css("a.onebox, a.inline-onebox-loading")
        .each do |link|
          link.remove_class("onebox")
          link.remove_class("inline-onebox-loading")
        end
    end

    def self.plain_link_cooking_options(options = nil)
      (options || {}).deep_symbolize_keys.deep_merge(
        features: {
          onebox: false
        }
      )
    end

    def self.validation_message(raw, enforce_length:)
      if raw.to_s.match?(MEDIA_PATTERN) ||
           Upload.extract_upload_ids(raw.to_s).present?
        return I18n.t("where_is_my_friends.dynamics.media_not_allowed")
      end

      document = cooked_document(raw)
      if document.css(COOKED_MEDIA_SELECTOR).present?
        return I18n.t("where_is_my_friends.dynamics.media_not_allowed")
      end

      if enforce_length
        length = visible_text(raw, document: document).grapheme_clusters.length
        unless length.between?(MIN_VISIBLE_CHARACTERS, MAX_VISIBLE_CHARACTERS)
          return I18n.t("where_is_my_friends.dynamics.invalid_length")
        end
      end

      nil
    end

    def self.cooked_document(raw)
      Nokogiri::HTML5.fragment(
        PrettyText.cook(raw.to_s, features: { onebox: false })
      )
    end

    private

    def discovery_page_size(limit)
      requested = limit.to_i
      return DISCOVERY_PAGE_SIZE unless requested.positive?

      requested.clamp(1, DISCOVERY_PAGE_SIZE)
    end

    def reactionable_topic(topic_id)
      topic = visible_topics.find_by(id: topic_id.to_i)
      raise Discourse::NotFound unless topic
      raise Discourse::NotFound if topic.user_id == @viewer.id
      raise Discourse::NotFound if @viewer.silenced?
      if UserTagVisibility.blocked_relationship?(@viewer, topic.user)
        raise Discourse::NotFound
      end

      topic
    end

    def sync_reaction_notification!(reaction, topic)
      data = {
        title: "where_is_my_friends.dynamics.reaction_notification_title",
        message:
          "where_is_my_friends.dynamics.reaction_notifications.#{reaction.kind}",
        display_username: @viewer.username,
        username: @viewer.username,
        user_id: @viewer.id,
        user_avatar_template: @viewer.avatar_template,
        topic_title: topic.title,
        action_url: "/t/#{topic.slug}/#{topic.id}",
        dynamic_reaction_id: reaction.id
      }.to_json

      notification = reaction.notification
      if notification
        notification.update!(data: data)
      else
        notification =
          Notification.new(
            user: topic.user,
            topic: topic,
            post_number: 1,
            notification_type: Notification.types[:custom],
            data: data
          )
        notification.skip_send_email = true
        notification.save!
        reaction.update_column(:notification_id, notification.id)
      end
    end

    def record_reaction_event(event_name)
      WhereIsMyFriendsEvent.create!(user: @viewer, event_name: event_name)
    end

    def ensure_available!
      raise Discourse::NotFound unless SiteSetting.where_is_my_friends_enabled
      unless SiteSetting.where_is_my_friends_dynamics_enabled
        raise Discourse::NotFound
      end

      @category =
        Category.find_by(
          id: SiteSetting.where_is_my_friends_dynamics_category_id.to_i
        )
      raise Discourse::NotFound unless valid_category?(@category)
      raise Discourse::NotFound unless @guardian.can_see?(@category)
    end

    def validate_content!(raw)
      message = self.class.validation_message(raw, enforce_length: true)
      raise InvalidContent, message if message
    end

    def valid_category?(category)
      return false unless category&.read_restricted?
      return false if category.minimum_required_tags.to_i.nonzero?

      members_group_id = Group::AUTO_GROUPS[:trust_level_0]
      full_permission = CategoryGroup.permission_types[:full]
      permissions = category.category_groups.pluck(:group_id, :permission_type)
      return false unless permissions == [[members_group_id, full_permission]]

      SiteSetting
        .default_categories_muted
        .split("|")
        .map(&:to_i)
        .include?(category.id)
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

    def serialize_many(topics)
      topics = topics.to_a
      return [] if topics.empty?

      topic_ids = topics.map(&:id)
      reactions =
        WhereIsMyFriendsDynamicReaction
          .where(topic_id: topic_ids, user_id: @viewer.id)
          .pluck(:topic_id, :kind)
          .to_h
      blocked_author_ids = blocked_author_ids_for(topics)

      topics.map do |topic|
        can_react =
          topic.user_id != @viewer.id && !@viewer.silenced? &&
            !blocked_author_ids.include?(topic.user_id)
        serialize(
          topic,
          can_react: can_react,
          reaction_kind: can_react ? reactions[topic.id] : nil
        )
      end
    end

    def blocked_author_ids_for(topics)
      author_ids = topics.map(&:user_id).uniq - [@viewer.id]
      return Set.new if author_ids.empty?

      muted =
        MutedUser.where(user_id: @viewer.id, muted_user_id: author_ids).pluck(
          :muted_user_id
        )
      muted.concat(
        MutedUser.where(user_id: author_ids, muted_user_id: @viewer.id).pluck(
          :user_id
        )
      )
      ignored =
        IgnoredUser
          .where(user_id: @viewer.id, ignored_user_id: author_ids)
          .where("expiring_at > ?", Time.current)
          .pluck(:ignored_user_id)
      ignored.concat(
        IgnoredUser
          .where(user_id: author_ids, ignored_user_id: @viewer.id)
          .where("expiring_at > ?", Time.current)
          .pluck(:user_id)
      )
      (muted + ignored).to_set
    end

    def serialize(topic, can_react:, reaction_kind:)
      post = topic.first_post
      author = {
        id: topic.user.id,
        username: topic.user.username,
        avatar_template: topic.user.avatar_template,
        profile_url: "/u/#{topic.user.username}",
        dynamics_url: "/u/#{CGI.escape(topic.user.username)}/activity/dynamics"
      }
      author[:name] = topic.user.name if SiteSetting.enable_names

      {
        id: topic.id,
        url: "/t/#{topic.slug}/#{topic.id}",
        author: author,
        cooked: post.cooked,
        excerpt: post.excerpt(160),
        created_at: topic.created_at,
        reply_count: topic.reply_count.to_i,
        can_react: can_react,
        reaction: reaction_kind
      }
    end
  end
end

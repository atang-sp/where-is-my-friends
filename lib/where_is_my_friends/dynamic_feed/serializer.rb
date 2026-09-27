# frozen_string_literal: true

module WhereIsMyFriends
  class DynamicFeed
    # Responsible for converting Topic/Post ActiveRecord objects into the plain
    # Hash payloads consumed by the API response layer.  All viewer-specific
    # reaction and block-list lookups live here so that Queries and Reactor
    # never need to know about response shape.
    class Serializer
      def initialize(viewer:)
        @viewer = viewer
      end

      # Accepts an Array (or AR relation) of Topics and returns an Array of
      # serialized hashes in the same order.
      def serialize_many(topics)
        topics = topics.to_a
        return [] if topics.empty?

        topic_ids = topics.map(&:id)
        reactions =
          WhereIsMyFriendsDynamicReaction
            .where(topic_id: topic_ids, user_id: @viewer.id)
            .pluck(:topic_id, :kind)
            .to_h
        blocked_ids = blocked_author_ids_for(topics)

        topics.map do |topic|
          can_react =
            topic.user_id != @viewer.id &&
              !@viewer.silenced? &&
              !blocked_ids.include?(topic.user_id)
          serialize(
            topic,
            can_react: can_react,
            reaction_kind: can_react ? reactions[topic.id] : nil
          )
        end
      end

      private

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

      # Returns a Set of user ids whose dynamics the viewer cannot react to
      # because of a mutual mute/ignore relationship.
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
    end
  end
end

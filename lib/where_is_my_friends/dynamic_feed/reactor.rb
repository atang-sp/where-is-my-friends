# frozen_string_literal: true

module WhereIsMyFriends
  class DynamicFeed
    # Responsible for the lightweight reaction system on dynamics: adding,
    # changing, and removing reactions, enforcing rate limits, and keeping the
    # in-product notification in sync with the current reaction kind.
    class Reactor
      RATE_LIMIT_KEY = "where-is-my-friends-dynamic-reaction"
      RATE_LIMIT_MAX = 40
      RATE_LIMIT_WINDOW = 1.day

      def initialize(viewer:, guardian:, queries:)
        @viewer = viewer
        @guardian = guardian
        @queries = queries
      end

      # Adds or changes a reaction of +kind+ on the topic identified by
      # +topic_id+. Returns { reaction: kind }.
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
        # Idempotent: same kind already set — return early without rate-limiting.
        return { reaction: reaction.kind } if reaction.persisted? && reaction.kind == reaction_kind

        enforce_rate_limit!

        event_name =
          reaction.persisted? ? "dynamic_reaction_changed" : "dynamic_reaction_added"

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

      # Removes the viewer's reaction from the topic. Returns { reaction: nil }.
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

      private

      def reactionable_topic(topic_id)
        topic = @queries.visible_topic_by_id(topic_id)
        raise Discourse::NotFound unless topic
        raise Discourse::NotFound if topic.user_id == @viewer.id
        raise Discourse::NotFound if @viewer.silenced?
        if UserTagVisibility.blocked_relationship?(@viewer, topic.user)
          raise Discourse::NotFound
        end

        topic
      end

      def enforce_rate_limit!
        RateLimiter.new(
          @viewer,
          RATE_LIMIT_KEY,
          RATE_LIMIT_MAX,
          RATE_LIMIT_WINDOW
        ).performed!
      rescue RateLimiter::LimitExceeded
        raise InvalidReaction,
              I18n.t("where_is_my_friends.dynamics.reaction_rate_limit")
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
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  class NextAction
    ALGORITHM_VERSION = "first_connection_v1"
    FOLLOW_UP_WINDOW = 7.days
    MAX_ACCEPTED_INVITATIONS = 10

    def initialize(user:, guardian:, as_of:)
      @user = user
      @guardian = guardian
      @as_of = as_of
    end

    def call
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_first_connection_enabled
        return empty_action
      end

      return incoming_invitation_action if incoming_invitation_pending?
      if (pm_topic_id = accepted_conversation_topic_id)
        return continue_conversation_action(pm_topic_id)
      end
      return onboarding_action if onboarding_pending?

      if recommendation_profile
        if recent_public_interaction?
          person = recommended_person
          return person_action(person) if person

          topic = recommended_topic
          return topic_action(topic) if topic
        else
          topic = recommended_topic
          return topic_action(topic) if topic

          person = recommended_person
          return person_action(person) if person
        end
      end

      dynamic = recent_dynamic
      return dynamic_action(dynamic) if dynamic

      return local_discovery_action if local_discovery_available?
      return recommendations_action if recommendation_panel_available?

      empty_action
    end

    private

    def incoming_invitation_pending?
      invitation_actions_enabled? &&
        WhereIsMyFriendsPracticeInvitation.exists?(
          recipient_id: @user.id,
          status: "pending"
        )
    end

    def invitation_actions_enabled?
      SiteSetting.where_is_my_friends_interest_onboarding_enabled &&
        SiteSetting.where_is_my_friends_practice_invitations_enabled
    end

    def incoming_invitation_action
      action(
        :incoming_invitation,
        primary_kind: :open_invitation,
        primary_url: "/where-is-my-friends/interests"
      )
    end

    def accepted_conversation_topic_id
      return unless invitation_actions_enabled?

      invitations =
        WhereIsMyFriendsPracticeInvitation
          .select(:id, :pm_topic_id, :responded_at)
          .where(
            sender_id: @user.id,
            status: "accepted",
            responded_at: (@as_of - FOLLOW_UP_WINDOW)..@as_of
          )
          .where.not(pm_topic_id: nil)
          .order(responded_at: :desc, id: :desc)
          .limit(MAX_ACCEPTED_INVITATIONS)
          .to_a
      return if invitations.empty?

      visible_topic_ids =
        Topic
          .where(
            id: invitations.map(&:pm_topic_id),
            archetype: Archetype.private_message,
            visible: true,
            deleted_at: nil
          )
          .private_messages_for_user(@user)
          .pluck(:id)
          .to_set
      replied_invitation_ids = sender_reply_invitation_ids(invitations)

      invitations
        .find do |invitation|
          visible_topic_ids.include?(invitation.pm_topic_id) &&
            replied_invitation_ids.exclude?(invitation.id)
        end
        &.pm_topic_id
    end

    def sender_reply_invitation_ids(invitations)
      invitation_table = WhereIsMyFriendsPracticeInvitation.table_name
      Post
        .joins(
          "INNER JOIN #{invitation_table} ON " \
            "#{invitation_table}.pm_topic_id = posts.topic_id"
        )
        .where(invitation_table => { id: invitations.map(&:id) })
        .where(
          user_id: @user.id,
          post_type: Post.types[:regular],
          deleted_at: nil,
          hidden: false,
          post_number: 2..
        )
        .where("posts.created_at > #{invitation_table}.responded_at")
        .where("posts.created_at <= ?", @as_of)
        .distinct
        .pluck(Arel.sql("#{invitation_table}.id"))
        .to_set
    end

    def continue_conversation_action(pm_topic_id)
      action(
        :continue_conversation,
        primary_kind: :open_conversation,
        primary_url: "/t/#{pm_topic_id}"
      )
    end

    def onboarding_pending?
      SiteSetting.where_is_my_friends_interest_onboarding_enabled &&
        InterestVisibility.onboarding_state(@user) == "pending"
    end

    def recommendation_profile
      return @recommendation_profile if defined?(@recommendation_profile)

      @recommendation_profile =
        if SiteSetting.where_is_my_friends_interest_onboarding_enabled
          WhereIsMyFriendsInterestProfile.find_by(
            user_id: @user.id,
            personalization_enabled: true,
            completed_at: ..@as_of
          )
        end
    end

    def recommended_topic
      profile = recommendation_profile
      return unless profile

      topics =
        RecommendationEngine
          .new(@user, guardian: @guardian)
          .call(profile: profile, group: "topics")
          .fetch(:recommended_topics)
          .reject { |topic| topic.fetch(:viewer_replied, false) }
      topics.min_by do |topic|
        [
          topic_participation_priority(topic[:participation_state]),
          topic[:rank]
        ]
      end
    end

    def recommended_person
      profile = recommendation_profile
      return unless profile

      RecommendationEngine
        .new(@user, guardian: @guardian)
        .call(profile: profile, group: "people")
        .fetch(:recommended_users)
        .first
    end

    def recent_public_interaction?
      public_topic_ids =
        Topic
          .where(archetype: Archetype.default, visible: true, deleted_at: nil)
          .where(
            "topics.category_id IS NULL OR topics.category_id IN (" \
              "SELECT categories.id FROM categories " \
              "WHERE categories.read_restricted = FALSE)"
          )
          .select(:id)

      Post
        .where(
          user_id: @user.id,
          topic_id: public_topic_ids,
          post_type: Post.types[:regular],
          created_at: (@as_of - 30.days)..@as_of,
          deleted_at: nil,
          hidden: false
        )
        .visible
        .exists?
    end

    def topic_participation_priority(state)
      { "awaiting_response" => 0, "unread" => 1, "active" => 2 }.fetch(state, 3)
    end

    def topic_action(topic)
      action(
        :topic,
        primary_kind: :open_topic,
        primary_url: topic.fetch(:url)
      ).merge(
        secondary_action: {
          kind: "open_recommendations",
          label_key: "where_is_my_friends.first_connection.more",
          url: "/where-is-my-friends/interests"
        },
        recommendation_group: "topics"
      )
    end

    def person_action(person)
      representative_topic = person.fetch(:representative_topics).first
      if representative_topic
        kind = :open_person_topic
        label_key = "where_is_my_friends.first_connection.person.topic_cta"
        url = representative_topic.fetch(:url)
      else
        kind = :open_person_profile
        label_key = "where_is_my_friends.first_connection.person.profile_cta"
        url = person.fetch(:profile_url)
      end

      action(
        :person,
        primary_kind: kind,
        primary_label_key: label_key,
        primary_url: url
      ).merge(
        secondary_action: {
          kind: "open_recommendations",
          label_key: "where_is_my_friends.first_connection.more_people",
          url: "/where-is-my-friends/interests"
        },
        recommendation_group: "people"
      )
    end

    def recent_dynamic
      unless SiteSetting.where_is_my_friends_dynamics_enabled &&
               SiteSetting.where_is_my_friends_dynamics_feed_enabled
        return
      end

      DynamicFeed
        .new(viewer: @user, guardian: @guardian)
        .recent
        .fetch(:dynamics)
        .first
    rescue Discourse::NotFound
      nil
    end

    def dynamic_action(dynamic)
      action(
        :dynamic,
        primary_kind: :open_dynamic,
        primary_url: dynamic.fetch(:url)
      ).merge(recommendation_group: "dynamics")
    end

    def local_discovery_action
      action(
        :local_discovery,
        primary_kind: :open_local_discovery,
        primary_url: "/where-is-my-friends"
      )
    end

    def local_discovery_available?
      # City mode is an always-available core path while the plugin is enabled.
      SiteSetting.where_is_my_friends_enabled
    end

    def recommendation_panel_available?
      SiteSetting.where_is_my_friends_interest_onboarding_enabled
    end

    def recommendations_action
      action(
        :recommendations,
        primary_kind: :open_recommendations,
        primary_url: "/where-is-my-friends/interests"
      )
    end

    def onboarding_action
      action(
        :onboarding,
        primary_kind: :open_onboarding,
        primary_url: "/where-is-my-friends/interests"
      )
    end

    def action(state, primary_kind:, primary_url:, primary_label_key: nil)
      prefix = "where_is_my_friends.first_connection.#{state}"
      {
        state: state.to_s,
        title_key: "#{prefix}.title",
        description_key: "#{prefix}.description",
        primary_action: {
          kind: primary_kind.to_s,
          label_key: primary_label_key || "#{prefix}.cta",
          url: primary_url
        },
        algorithm_version: ALGORITHM_VERSION
      }
    end

    def empty_action
      { state: "empty", algorithm_version: ALGORITHM_VERSION }
    end
  end
end

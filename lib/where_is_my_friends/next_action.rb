# frozen_string_literal: true

require_relative "next_action/evaluators/base"
require_relative "next_action/evaluators/incoming_invitation"
require_relative "next_action/evaluators/accepted_conversation"
require_relative "next_action/evaluators/onboarding"
require_relative "next_action/evaluators/recommendation"
require_relative "next_action/evaluators/dynamic"

module WhereIsMyFriends
  class NextAction
    ALGORITHM_VERSION = "first_connection_v1"
    FOLLOW_UP_WINDOW = Evaluators::AcceptedConversation::FOLLOW_UP_WINDOW
    MAX_ACCEPTED_INVITATIONS = Evaluators::AcceptedConversation::MAX_ACCEPTED_INVITATIONS

    def self.action(state, primary_kind:, primary_url:, primary_label_key: nil)
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

    def self.empty_action
      { state: "empty", algorithm_version: ALGORITHM_VERSION }
    end

    def initialize(user:, guardian:, as_of:)
      @user = user
      @guardian = guardian
      @as_of = as_of

      context = { user: @user, guardian: @guardian, as_of: @as_of }
      @incoming_invitation_evaluator = Evaluators::IncomingInvitation.new(**context)
      @accepted_conversation_evaluator = Evaluators::AcceptedConversation.new(**context)
      @onboarding_evaluator = Evaluators::Onboarding.new(**context)
      @recommendation_evaluator = Evaluators::Recommendation.new(**context)
      @dynamic_evaluator = Evaluators::Dynamic.new(**context)
    end

    def call
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_first_connection_enabled
        return empty_action
      end

      if (action = @incoming_invitation_evaluator.evaluate)
        return action
      end

      if (action = @accepted_conversation_evaluator.evaluate)
        return action
      end

      if (action = @onboarding_evaluator.evaluate)
        return action
      end

      if (action = @recommendation_evaluator.evaluate)
        return action
      end

      if (action = @dynamic_evaluator.evaluate)
        return action
      end

      return local_discovery_action if local_discovery_available?
      return recommendations_action if recommendation_panel_available?

      empty_action
    end

    # Preserved for spec stubbing and backwards compatibility
    def local_discovery_available?
      # City mode is an always-available core path while the plugin is enabled.
      SiteSetting.where_is_my_friends_enabled
    end

    private

    def incoming_invitation_pending?
      @incoming_invitation_evaluator.pending?
    end

    def accepted_conversation_topic_id
      @accepted_conversation_evaluator.accepted_conversation_topic_id
    end

    def onboarding_pending?
      @onboarding_evaluator.pending?
    end

    def recommendation_profile
      @recommendation_evaluator.recommendation_profile
    end

    def recommended_topic
      @recommendation_evaluator.recommended_topic
    end

    def recommended_person
      @recommendation_evaluator.recommended_person
    end

    def recent_public_interaction?
      @recommendation_evaluator.recent_public_interaction?
    end

    def recent_dynamic
      @dynamic_evaluator.recent_dynamic
    end

    def recommendation_panel_available?
      SiteSetting.where_is_my_friends_interest_onboarding_enabled
    end

    def local_discovery_action
      action(
        :local_discovery,
        primary_kind: :open_local_discovery,
        primary_url: "/where-is-my-friends"
      )
    end

    def recommendations_action
      action(
        :recommendations,
        primary_kind: :open_recommendations,
        primary_url: "/where-is-my-friends/interests"
      )
    end

    def action(state, primary_kind:, primary_url:, primary_label_key: nil)
      self.class.action(
        state,
        primary_kind: primary_kind,
        primary_url: primary_url,
        primary_label_key: primary_label_key
      )
    end

    def empty_action
      self.class.empty_action
    end
  end
end

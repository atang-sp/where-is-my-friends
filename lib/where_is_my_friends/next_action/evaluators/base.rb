# frozen_string_literal: true

module WhereIsMyFriends
  class NextAction
    module Evaluators
      class Base
        attr_reader :user, :guardian, :as_of

        def initialize(user:, guardian:, as_of:)
          @user = user
          @guardian = guardian
          @as_of = as_of
        end

        def evaluate
          raise NotImplementedError
        end

        protected

        def action(state, primary_kind:, primary_url:, primary_label_key: nil)
          NextAction.action(
            state,
            primary_kind: primary_kind,
            primary_url: primary_url,
            primary_label_key: primary_label_key
          )
        end

        def invitation_actions_enabled?
          SiteSetting.where_is_my_friends_interest_onboarding_enabled &&
            SiteSetting.where_is_my_friends_practice_invitations_enabled
        end
      end
    end
  end
end

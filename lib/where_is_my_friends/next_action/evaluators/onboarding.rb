# frozen_string_literal: true

require_relative "base"

module WhereIsMyFriends
  class NextAction
    module Evaluators
      class Onboarding < Base
        def evaluate
          return unless pending?

          action(
            :onboarding,
            primary_kind: :open_onboarding,
            primary_url: "/where-is-my-friends/interests"
          )
        end

        def pending?
          SiteSetting.where_is_my_friends_interest_onboarding_enabled &&
            InterestVisibility.onboarding_state(user) == "pending"
        end
      end
    end
  end
end

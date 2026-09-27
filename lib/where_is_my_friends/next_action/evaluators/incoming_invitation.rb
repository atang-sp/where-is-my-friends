# frozen_string_literal: true

require_relative "base"

module WhereIsMyFriends
  class NextAction
    module Evaluators
      class IncomingInvitation < Base
        def evaluate
          return unless pending?

          action(
            :incoming_invitation,
            primary_kind: :open_invitation,
            primary_url: "/where-is-my-friends/interests"
          )
        end

        def pending?
          invitation_actions_enabled? &&
            WhereIsMyFriendsPracticeInvitation.exists?(
              recipient_id: user.id,
              status: "pending"
            )
        end
      end
    end
  end
end

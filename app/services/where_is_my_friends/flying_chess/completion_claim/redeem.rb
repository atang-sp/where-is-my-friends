# frozen_string_literal: true

module WhereIsMyFriends
  module FlyingChess
    module CompletionClaim
      class Redeem
        include Service::Base

        params do
          attribute :claim_token, :string

          validates :claim_token,
                    presence: true,
                    length: {
                      maximum: ClaimToken::MAXIMUM_TOKEN_BYTES
                    }
        end

        model :user
        policy :claims_enabled

        try ClaimToken::InvalidClaim do
          step :verify_claim
        end

        try ActiveRecord::RecordNotUnique do
          lock(:user) do
            policy :claim_available

            transaction do
              step :record_completion
              model :profile, :synchronize_profile
            end
          end
        end

        step :synchronize_first_takeoff_badge

        private

        def fetch_user(guardian:)
          guardian.user
        end

        def claims_enabled
          FlyingChess.achievements_enabled? &&
            SiteSetting
              .where_is_my_friends_flying_chess_claim_secret
              .to_s
              .bytesize >= ClaimToken::MINIMUM_SECRET_BYTES
        end

        def verify_claim(params:)
          context[:claim] = ClaimToken.verify(
            params.claim_token,
            secret: SiteSetting.where_is_my_friends_flying_chess_claim_secret
          )
        end

        def claim_available(user:, claim:)
          WhereIsMyFriendsFlyingChessCompletion.claimable_by?(user:, claim:)
        end

        def record_completion(user:, claim:)
          WhereIsMyFriendsFlyingChessCompletion.record!(user:, claim:)
        end

        def synchronize_profile(user:)
          WhereIsMyFriendsFlyingChessProfile.synchronize_for(user)
        end

        def synchronize_first_takeoff_badge(profile:)
          profile.synchronize_first_takeoff_badge!
        end
      end
    end
  end
end

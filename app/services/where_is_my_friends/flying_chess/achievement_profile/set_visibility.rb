# frozen_string_literal: true

module WhereIsMyFriends
  module FlyingChess
    module AchievementProfile
      class SetVisibility
        include Service::Base

        params do
          attribute :profile_visible, :boolean

          validates :profile_visible, inclusion: { in: [true, false] }
        end

        model :user
        model :profile
        policy :can_manage_profile

        transaction do
          model :updated_profile, :change_profile_visibility
          step :synchronize_first_takeoff_badge
        end

        private

        def fetch_user(guardian:)
          guardian.user
        end

        def fetch_profile(user:)
          WhereIsMyFriendsFlyingChessProfile.find_by(user:)
        end

        def can_manage_profile(guardian:, profile:)
          profile.manageable_by?(guardian.user)
        end

        def change_profile_visibility(profile:, params:)
          profile.update(profile_visible: params.profile_visible)
          profile
        end

        def synchronize_first_takeoff_badge(updated_profile:)
          updated_profile.synchronize_first_takeoff_badge!
        end
      end
    end
  end
end

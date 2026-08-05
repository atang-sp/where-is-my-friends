# frozen_string_literal: true

class WhereIsMyFriendsFlyingChessProfileSerializer < ApplicationSerializer
  attributes :completed_games,
             :first_completed_at,
             :badge_name,
             :profile_visible,
             :can_manage

  def badge_name
    WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
  end

  def can_manage
    object.manageable_by?(scope.user)
  end
end

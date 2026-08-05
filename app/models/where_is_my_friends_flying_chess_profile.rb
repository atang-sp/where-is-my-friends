# frozen_string_literal: true

class WhereIsMyFriendsFlyingChessProfile < ActiveRecord::Base
  belongs_to :user

  validates :user_id, uniqueness: true
  validates :completed_games,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  def self.synchronize_for(user)
    completions = WhereIsMyFriendsFlyingChessCompletion.where(user:)
    attributes = {
      completed_games: completions.count,
      first_completed_at: completions.minimum(:completed_at)
    }
    profile = find_by(user:)

    if profile
      profile.update(attributes)
      profile
    else
      create(user:, **attributes)
    end
  end

  def visible_to?(viewer)
    profile_visible? || viewer&.id == user_id
  end

  def manageable_by?(viewer)
    viewer&.id == user_id
  end

  def synchronize_first_takeoff_badge!
    with_lock do
      badge =
        Badge.find_by(
          name: WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
        )
      user_badge = UserBadge.find_by(badge:, user:) if badge

      if profile_visible?
        BadgeGranter.grant(badge, user) if badge&.enabled? && !user_badge
      elsif user_badge
        BadgeGranter.revoke(user_badge)
      end
    end

    self
  end
end

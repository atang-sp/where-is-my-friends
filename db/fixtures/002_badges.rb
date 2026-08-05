# frozen_string_literal: true

Badge.seed(:name) do |badge|
  badge.name = "Local Explorer"
  badge.badge_type_id = BadgeType::Bronze
  badge.icon = "location-dot"
  badge.description =
    "Joined local discovery to connect with nearby community members"
  badge.badge_grouping_id = BadgeGrouping::Community
  badge.enabled = true
  badge.listable = true
  badge.target_posts = false
  badge.auto_revoke = false
  badge.system = false
end

Badge.seed(:name) do |badge|
  badge.name = WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
  badge.badge_type_id = BadgeType::Bronze
  badge.icon = "plane"
  badge.description = "完成第一局服务器确认的在线飞行棋"
  badge.badge_grouping_id = BadgeGrouping::Community
  badge.enabled = true
  badge.listable = true
  badge.target_posts = false
  badge.auto_revoke = false
  badge.system = false
end

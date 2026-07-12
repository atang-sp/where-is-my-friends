# frozen_string_literal: true

# name: where-is-my-friends
# about: City-first local member discovery with optional private distance bands
# version: 1.0.1
# authors: atang
# url: https://github.com/atang/where-is-my-friends
# required_version: 2026.7.0.beta1

enabled_site_setting :where_is_my_friends_enabled

register_asset "stylesheets/where-is-my-friends.scss"

require_relative "lib/where_is_my_friends/engine"

after_initialize do
  UserUpdater::OPTION_ATTR.push(:where_is_my_friends_notify_city)
  add_to_serializer(:user_option, :where_is_my_friends_notify_city) do
    object.where_is_my_friends_notify_city
  end

  add_to_serializer(:user_card, :where_is_my_friends_city) do
    UserLocation.active_for_discovery.find_by(user_id: object.id)&.city
  end

  add_to_serializer(:user, :where_is_my_friends_city) do
    UserLocation.active_for_discovery.find_by(user_id: object.id)&.city
  end

  Badge.seed(:name) do |badge|
    badge.name = "Local Explorer"
    badge.badge_type_id = BadgeType::Bronze
    badge.icon = "location-dot"
    badge.description = "Joined local discovery to connect with nearby community members"
    badge.badge_grouping_id = BadgeGrouping::Community
    badge.enabled = true
    badge.listable = true
    badge.target_posts = false
    badge.auto_revoke = false
    badge.system = false
  end

  on(:where_is_my_friends_location_saved) do |user|
    badge = Badge.find_by(name: "Local Explorer")
    if badge&.enabled
      BadgeGranter.grant(badge, user)
    end
  end

  # Render the Discourse application for the client route, then mount the JSON API.
  Discourse::Application.routes.append do
    get "/where-is-my-friends.json" => "where_is_my_friends/locations#index",
        :as => "where_is_my_friends_data"
    get "/where-is-my-friends" => "list#latest",
        :constraints => ->(request) { request.format.html? }
    mount ::WhereIsMyFriends::Engine,
          at: "/where-is-my-friends",
          as: "where_is_my_friends_engine"
  end
end

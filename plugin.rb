# frozen_string_literal: true

# name: where-is-my-friends
# about: City-first local member discovery with optional private distance bands
# version: 1.0.0
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

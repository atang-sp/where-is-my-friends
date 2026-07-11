# frozen_string_literal: true

# name: where-is-my-friends
# about: Find friends nearby with privacy protection
# version: 0.1
# authors: atang
# url: https://github.com/atang/where-is-my-friends

enabled_site_setting :where_is_my_friends_enabled

register_asset "stylesheets/where-is-my-friends.scss"

require_relative "lib/where_is_my_friends/engine"

# JavaScript files under assets/javascripts are automatically included in JS bundles
# No need to manually register them with register_asset

after_initialize do
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

  # Navigation menu items are now handled by the frontend initializer
end

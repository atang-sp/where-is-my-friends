# frozen_string_literal: true

WhereIsMyFriends::Engine.routes.draw do
  get "/" => "locations#index"
  post "/locations" => "locations#create"
  get "/locations/nearby" => "locations#nearby"
  delete "/locations" => "locations#destroy"
  get "/ip-location" => "locations#ip_location"
  get "/debug-stats" => "locations#debug_stats"  # 仅管理员可访问
end

Discourse::Application.routes.draw { mount ::WhereIsMyFriends::Engine, at: "where-is-my-friends" } 
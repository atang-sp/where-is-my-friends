# frozen_string_literal: true

WhereIsMyFriends::Engine.routes.draw do
  get "/" => "locations#index"
  post "/locations" => "locations#create"
  get "/locations/nearby" => "locations#nearby"
  delete "/locations" => "locations#destroy"
  post "/events" => "events#create"
  get "/debug-stats" => "locations#debug_stats" # 仅管理员可访问
end

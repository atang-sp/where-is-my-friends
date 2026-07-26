# frozen_string_literal: true

WhereIsMyFriends::Engine.routes.draw do
  get "/" => "locations#index"
  post "/locations" => "locations#create"
  get "/locations/nearby" => "locations#nearby"
  delete "/locations" => "locations#destroy"
  get "/recommendations" => "recommendations#index"
  put "/recommendations/profile" => "recommendations#update_profile"
  delete "/recommendations/profile" => "recommendations#destroy_profile"
  post "/recommendations/skip" => "recommendations#skip"
  post "/recommendations/dismiss" => "recommendations#dismiss"
  post "/events" => "events#create"
  get "/debug-stats" => "locations#debug_stats" # 仅管理员可访问
end

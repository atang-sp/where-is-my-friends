# frozen_string_literal: true

WhereIsMyFriends::Engine.routes.draw do
  get "/" => "locations#index"
  get "/cities/preview" => "locations#preview"
  post "/locations" => "locations#create"
  get "/locations/nearby" => "locations#nearby"
  delete "/locations" => "locations#destroy"
  get "/recommendations" => "recommendations#index"
  put "/recommendations/profile" => "recommendations#update_profile"
  delete "/recommendations/profile" => "recommendations#destroy_profile"
  post "/recommendations/skip" => "recommendations#skip"
  post "/recommendations/dismiss" => "recommendations#dismiss"
  get "/practice-invitations" => "practice_invitations#index"
  get "/practice-invitations/availability" =>
        "practice_invitations#availability"
  post "/practice-invitations" => "practice_invitations#create"
  put "/practice-invitations/:id/accept" => "practice_invitations#accept"
  put "/practice-invitations/:id/decline" => "practice_invitations#decline"
  put "/practice-invitations/:id/ignore" => "practice_invitations#ignore"
  get "/legacy-practice-bookmarks" => "legacy_practice_bookmarks#index"
  put "/legacy-practice-bookmarks/:id/reconfirm" =>
        "legacy_practice_bookmarks#reconfirm"
  put "/legacy-practice-bookmarks/:id/dismiss" =>
        "legacy_practice_bookmarks#dismiss"
  post "/events" => "events#create"
  get "/licensed-imports" => "licensed_imports#index"
  get "/debug-stats" => "locations#debug_stats" # 仅管理员可访问
end

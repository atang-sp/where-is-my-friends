# frozen_string_literal: true

WhereIsMyFriends::Engine.routes.draw do
  get "/" => "locations#index"
  get "/callout" => "locations#callout"
  get "/location-presence" => "locations#presence"
  get "/cities/preview" => "locations#preview"
  post "/locations" => "locations#create"
  get "/locations/nearby" => "locations#nearby"
  delete "/locations" => "locations#destroy"
  get "/recommendations" => "recommendations#index"
  get "/next-action" => "next_actions#show"
  get "/dynamics" => "dynamics#index"
  get "/dynamics/feed" => "dynamics#feed"
  get "/dynamics/recent" => "dynamics#recent"
  post "/dynamics" => "dynamics#create"
  post "/dynamics/:topic_id/reaction" => "dynamics#react"
  delete "/dynamics/:topic_id/reaction" => "dynamics#unreact"
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
  get "/user-tags" => "user_tags#index"
  get "/user-tags/mine" => "user_tags#mine"
  post "/user-tags" => "user_tags#create"
  put "/user-tags/:id/approve" => "user_tags#approve"
  put "/user-tags/:id/reject" => "user_tags#reject"
  put "/user-tags/:id/remove" => "user_tags#remove"
  post "/user-tags/:id/endorse" => "user_tags#endorse"
  delete "/user-tags/:id/endorse" => "user_tags#unendorse"
  post "/flying-chess/claims" => "flying_chess_claims#create"
  put "/flying-chess/profile" => "flying_chess_claims#update_profile"
  get "/licensed-imports" => "licensed_imports#index"
  scope "/admin" do
    resources :ai_provider_profiles,
              path: "ai-provider-profiles",
              only: %i[index create update destroy] do
      member do
        post :test
        post :activate
      end
    end
  end
  get "/debug-stats" => "locations#debug_stats" # 仅管理员可访问
end

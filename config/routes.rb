# frozen_string_literal: true

WhereIsMyFriends::Engine.routes.draw do
  get "/" => "locations#index"
  post "/locations" => "locations#create"
  get "/locations/nearby" => "locations#nearby"
  delete "/locations" => "locations#destroy"
end

Discourse::Application.routes.draw { mount ::WhereIsMyFriends::Engine, at: "where-is-my-friends" } 
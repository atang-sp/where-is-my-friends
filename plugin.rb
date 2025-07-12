# frozen_string_literal: true

# name: where-is-my-friends
# about: Find friends nearby with privacy protection
# version: 0.1
# authors: atang
# url: https://github.com/atang/where-is-my-friends

enabled_site_setting :where_is_my_friends_enabled

register_asset 'stylesheets/where-is-my-friends.scss'

# JavaScript files under assets/javascripts are automatically included in JS bundles
# No need to manually register them with register_asset

after_initialize do
  # Load the model
  load File.expand_path('../app/models/user_location.rb', __FILE__)
  
  # Load the serializer
  load File.expand_path('../app/serializers/user_location_serializer.rb', __FILE__)
  
  # Load the controller
  load File.expand_path('../app/controllers/where_is_my_friends/locations_controller.rb', __FILE__)
  
  # Add list controller extension for frontend route
  reloadable_patch do |plugin|
    ListController.class_eval do
      def where_is_my_friends
        # Render HTML for Ember app
        render html: '<div id="main-outlet" class="wrap"></div>'.html_safe, layout: 'application'
      end
    end
  end

  # Add routes
  Discourse::Application.routes.append do
    # Frontend route - renders Ember app
    get "/where-is-my-friends" => "list#where_is_my_friends"
    
    # API routes - return JSON data
    get "/api/where-is-my-friends" => "where_is_my_friends/locations#index"
    post "/api/where-is-my-friends/locations" => "where_is_my_friends/locations#create"
    get "/api/where-is-my-friends/locations/nearby" => "where_is_my_friends/locations#nearby"
    delete "/api/where-is-my-friends/locations" => "where_is_my_friends/locations#destroy"
  end

  # Navigation menu items are now handled by the frontend initializer

  # Add admin route
  add_admin_route 'where_is_my_friends.title', 'where-is-my-friends'
end 
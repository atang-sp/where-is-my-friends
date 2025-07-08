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
  
  # Add routes
  Discourse::Application.routes.append do
    get '/where-is-my-friends' => 'where_is_my_friends/locations#index'
    post '/where-is-my-friends/locations' => 'where_is_my_friends/locations#create'
    get '/where-is-my-friends/locations/nearby' => 'where_is_my_friends/locations#nearby'
    delete '/where-is-my-friends/locations' => 'where_is_my_friends/locations#destroy'
  end

  # Add navigation menu item
  add_to_serializer(:site, :menu_items) do
    [
      {
        name: 'where-is-my-friends',
        text: I18n.t('where_is_my_friends.title'),
        href: '/where-is-my-friends',
        title: I18n.t('where_is_my_friends.description'),
        icon: 'map-marker-alt'
      }
    ]
  end

  # Add user menu item
  add_to_serializer(:current_user, :user_menu_items) do
    [
      {
        name: 'where-is-my-friends',
        text: I18n.t('where_is_my_friends.title'),
        href: '/where-is-my-friends',
        title: I18n.t('where_is_my_friends.description'),
        icon: 'map-marker-alt'
      }
    ]
  end

  # Add admin route
  add_admin_route 'where_is_my_friends.title', 'where-is-my-friends'
end 
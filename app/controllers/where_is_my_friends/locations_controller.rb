# frozen_string_literal: true

module WhereIsMyFriends
  class LocationsController < ::ApplicationController
    requires_plugin 'where-is-my-friends'
    before_action :ensure_logged_in
    before_action :ensure_plugin_enabled

    def index
      # Return initial data for the frontend
      current_user_location = UserLocation.find_by(user_id: current_user.id, enabled: true)
      
      response_data = {
        currentUser: {
          id: current_user.id,
          username: current_user.username,
          location: current_user_location ? {
            latitude: current_user_location.latitude,
            longitude: current_user_location.longitude
          } : nil
        },
        users: [] # Will be populated when user shares location
      }
      
      render json: response_data
    end

    def create
      # Update user's location
      latitude = params[:latitude].to_f
      longitude = params[:longitude].to_f

      if latitude.abs > 90 || longitude.abs > 180
        return render_json_error(I18n.t('where_is_my_friends.invalid_coordinates'))
      end

      begin
        UserLocation.upsert_location(current_user.id, latitude, longitude)
        render json: success_json
      rescue => e
        render_json_error(e.message)
      end
    end

    def nearby
      # Get nearby users
      latitude = params[:latitude].to_f
      longitude = params[:longitude].to_f
      distance = [params[:distance].to_f, 50].min # Max 50km

      if latitude.abs > 90 || longitude.abs > 180
        return render_json_error(I18n.t('where_is_my_friends.invalid_coordinates'))
      end

      nearby_users = UserLocation.nearby(latitude, longitude, distance)
        .where.not(user_id: current_user.id)
        .limit(50)

      # Calculate distances
      users_with_distance = nearby_users.map do |location|
        distance_km = location.distance_to(latitude, longitude)
        {
          user: location.user,
          distance: distance_km.round(1),
          location: location
        }
      end.sort_by { |u| u[:distance] }

      render json: {
        users: users_with_distance.map { |u| UserLocationSerializer.new(u, root: false) },
        total: users_with_distance.count
      }
    end

    def destroy
      # Remove user's location
      location = UserLocation.find_by(user_id: current_user.id)
      location&.update(enabled: false)
      render json: success_json
    end

    private

    def ensure_plugin_enabled
      unless SiteSetting.where_is_my_friends_enabled
        raise Discourse::NotFound
      end
    end
  end
end 
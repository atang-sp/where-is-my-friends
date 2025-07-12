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

      Rails.logger.info "WhereIsMyFriends: Searching for users near (#{latitude}, #{longitude}) within #{distance}km"

      if latitude.abs > 90 || longitude.abs > 180
        Rails.logger.error "WhereIsMyFriends: Invalid coordinates (#{latitude}, #{longitude})"
        return render_json_error(I18n.t('where_is_my_friends.invalid_coordinates'))
      end

      begin
        # 查找所有启用的位置，包括当前用户
        nearby_users = UserLocation.nearby(latitude, longitude, distance)
          .where(enabled: true)
          .limit(50)

        Rails.logger.info "WhereIsMyFriends: Found #{nearby_users.count} users within #{distance}km"

        # Calculate distances and include current user
        users_with_distance = nearby_users.map do |location|
          distance_km = location.distance_to(latitude, longitude)
          {
            user: location.user,
            distance: distance_km.round(1),
            location: location,
            isCurrentUser: location.user_id == current_user.id
          }
        end.sort_by { |u| u[:distance] }

        # 确保当前用户也在结果中（如果他们有位置）
        current_user_location = UserLocation.find_by(user_id: current_user.id, enabled: true)
        if current_user_location && !users_with_distance.any? { |u| u[:isCurrentUser] }
          current_distance = current_user_location.distance_to(latitude, longitude)
          if current_distance <= distance
            users_with_distance.unshift({
              user: current_user,
              distance: current_distance.round(1),
              location: current_user_location,
              isCurrentUser: true
            })
          end
        end

        Rails.logger.info "WhereIsMyFriends: Returning #{users_with_distance.count} users (including current user)"

        render json: {
          users: users_with_distance.map { |u| UserLocationSerializer.new(u, root: false) },
          total: users_with_distance.count,
          searchLocation: { latitude: latitude, longitude: longitude },
          searchDistance: distance
        }
      rescue => e
        Rails.logger.error "WhereIsMyFriends: Error finding nearby users: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render_json_error("查找附近用户时发生错误: #{e.message}")
      end
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
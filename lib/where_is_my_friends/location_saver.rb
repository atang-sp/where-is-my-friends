# frozen_string_literal: true

module WhereIsMyFriends
  class LocationSaver
    def initialize(user:, params:)
      @user = user
      @params = params
    end
    def call
      if discovery_mode != "city" &&
           !SiteSetting.where_is_my_friends_enable_virtual_location
        raise ActiveRecord::RecordInvalid
      end

      previous_city_key = UserLocation.find_by(user_id: @user.id)&.city_key
      location = upsert_location!
      update_notification_preferences!
      enqueue_member_joined_notification(location, previous_city_key)
      DiscourseEvent.trigger(:where_is_my_friends_location_saved, @user)
      location
    end

    private

    def discovery_mode
      @params[:discovery_mode].presence || "city"
    end

    def upsert_location!
      existing = UserLocation.find_by(user_id: @user.id)
      if radius_only_update?(existing)
        radius =
          UserLocation.normalize_discovery_radius_km(
            @params[:discovery_radius_km]
          )
        raise ActiveRecord::RecordInvalid if radius.blank?

        existing.update!(discovery_radius_km: radius)
        return existing
      end

      if discovery_mode == "city"
        UserLocation.upsert_city_location(
          @user.id,
          city: @params[:city],
          region: @params[:region],
          discovery_radius_km: @params[:discovery_radius_km]
        )
      else
        UserLocation.upsert_precise_location(
          @user.id,
          city: @params[:city],
          region: @params[:region],
          discovery_mode: discovery_mode,
          latitude: @params[:latitude],
          longitude: @params[:longitude],
          location_accuracy: @params[:location_accuracy],
          discovery_radius_km: @params[:discovery_radius_km]
        )
      end
    end

    def radius_only_update?(existing)
      return false if existing.blank?
      return false if @params[:discovery_radius_km].blank?
      return false if @params[:city].blank?
      unless UserLocation.normalize_city(@params[:city]) == existing.city_key
        return false
      end
      return false unless discovery_mode == existing.discovery_mode
      return true if discovery_mode == "city"

      existing.precise? && @params[:latitude].blank? &&
        @params[:longitude].blank?
    end

    def update_notification_preferences!
      attributes = {}
      unless @params[:notify_city].nil?
        attributes[
          :where_is_my_friends_notify_city
        ] = ActiveModel::Type::Boolean.new.cast(@params[:notify_city])
      end
      unless @params[:notify_nearby].nil?
        attributes[
          :where_is_my_friends_notify_nearby
        ] = ActiveModel::Type::Boolean.new.cast(@params[:notify_nearby])
      end
      @user.user_option.update!(attributes) if attributes.present?
    end

    def enqueue_member_joined_notification(location, previous_city_key)
      return if location.city_key.blank?
      return if previous_city_key == location.city_key

      Jobs.enqueue(
        :where_is_my_friends_notify_city_members,
        joiner_id: @user.id,
        city: location.city,
        city_key: location.city_key
      )
    end
  end
end

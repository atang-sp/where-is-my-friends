# frozen_string_literal: true

module WhereIsMyFriends
  class LocationsController < ::ApplicationController
    REPORT_WINDOWS = [7, 30, 90].freeze

    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_plugin_enabled

    def index
      location = current_location

      render json: {
               state: state_for(location),
               current_user: {
                 id: current_user.id,
                 username: current_user.username
               },
               location: location_metadata(location),
               active_participants: active_participants,
               city_suggestions: city_suggestions,
               settings: client_settings
             }
    end

    def create
      if discovery_mode != "city" &&
           !SiteSetting.where_is_my_friends_enable_virtual_location
        return(
          render_json_error(
            I18n.t("where_is_my_friends.invalid_location"),
            status: 422
          )
        )
      end

      location =
        if discovery_mode == "city"
          UserLocation.upsert_city_location(
            current_user.id,
            city: params[:city],
            region: params[:region]
          )
        else
          UserLocation.upsert_precise_location(
            current_user.id,
            city: params[:city],
            region: params[:region],
            discovery_mode: discovery_mode,
            latitude: params[:latitude],
            longitude: params[:longitude],
            location_accuracy: params[:location_accuracy]
          )
        end

      render json: { state: "ready", location: location_metadata(location) }
    rescue ActiveRecord::RecordInvalid
      render_json_error(
        I18n.t("where_is_my_friends.invalid_location"),
        status: 422
      )
    end

    def nearby
      origin = current_location
      if origin.blank?
        return render json: { state: state_for(origin), users: [] }
      end

      locations =
        UserLocation
          .active_for_discovery
          .where(city_key: origin.city_key)
          .where.not(user_id: current_user.id)
          .includes(:user)
          .order(updated_at: :desc)
          .limit(
            UserLocation.discovery_limit(
              SiteSetting.where_is_my_friends_max_users_display
            )
          )

      users =
        locations.map do |location|
          UserLocationSerializer.new(
            { user: location.user, location: location, origin: origin },
            root: false
          )
        end

      render json: { state: users.empty? ? "empty" : "ready", users: users }
    end

    def destroy
      UserLocation.find_by(user_id: current_user.id)&.destroy!
      render json: success_json.merge(state: "setup")
    end

    def debug_stats
      raise Discourse::InvalidAccess unless current_user.admin?

      active_locations = UserLocation.active_for_discovery
      expired_locations = UserLocation.where("expires_at <= ?", Time.current)

      render json: {
               window_days: report_window_days,
               active: active_locations.count,
               expired: expired_locations.count,
               by_mode: active_locations.group(:discovery_mode).count,
               locations: {
                 active: location_totals(active_locations),
                 expired: location_totals(expired_locations)
               },
               funnel:
                 WhereIsMyFriendsEvent.aggregate(
                   since: report_window_days.days.ago
                 )
             }
    end

    private

    def current_location
      UserLocation.active_for_discovery.find_by(user_id: current_user.id)
    end

    def state_for(location)
      return "ready" if location.present?

      UserLocation.exists?(user_id: current_user.id) ? "expired" : "setup"
    end

    def discovery_mode
      params[:discovery_mode].presence || "city"
    end

    def location_metadata(location)
      return nil if location.blank?

      {
        city: location.city,
        region: location.region,
        discovery_mode: location.discovery_mode,
        expires_at: location.expires_at&.iso8601
      }
    end

    def city_suggestions
      UserLocation
        .active_for_discovery
        .select(:city, :city_key)
        .distinct
        .order(:city)
        .limit(20)
        .map { |location| { city: location.city, city_key: location.city_key } }
    end

    def client_settings
      settings = {
        virtual_location_enabled:
          SiteSetting.where_is_my_friends_enable_virtual_location,
        map_provider: SiteSetting.where_is_my_friends_map_provider,
        location_ttl_days: UserLocation.ttl_days
      }

      case settings[:map_provider]
      when "amap"
        settings[
          :amap_api_key
        ] = SiteSetting.where_is_my_friends_amap_api_key.presence
      when "baidu"
        settings[
          :baidu_api_key
        ] = SiteSetting.where_is_my_friends_baidu_api_key.presence
      end

      settings.compact
    end

    def active_participants
      count = UserLocation.active_for_discovery.count
      threshold =
        SiteSetting.where_is_my_friends_aggregate_privacy_threshold.to_i.clamp(
          2,
          20
        )
      return { suppressed: true } if count < threshold

      { suppressed: false, count: count }
    end

    def report_window_days
      requested = params[:days].to_i
      REPORT_WINDOWS.include?(requested) ? requested : 30
    end

    def location_totals(scope)
      { total: scope.count, by_mode: scope.group(:discovery_mode).count }
    end

    def ensure_plugin_enabled
      raise Discourse::NotFound unless SiteSetting.where_is_my_friends_enabled
    end
  end
end

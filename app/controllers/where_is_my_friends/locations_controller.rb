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
               settings: client_settings,
               profile_location: current_user.user_profile&.location.presence
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

      previous_city_key =
        UserLocation.find_by(user_id: current_user.id)&.city_key

      location = upsert_location!
      enqueue_member_joined_notification(location, previous_city_key)
      DiscourseEvent.trigger(:where_is_my_friends_location_saved, current_user)

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

      radius = origin.effective_discovery_radius_km
      users, expanded = discover_nearby(origin, radius)

      if users.empty? && radius < 200
        users, _ = discover_nearby(origin, 200)
        expanded = true if users.any?
      end

      if users.empty?
        nearby_city_count =
          UserLocation
            .active_for_discovery
            .where.not(city_key: origin.city_key)
            .where.not(user_id: current_user.id)
            .count

        render json: {
                 state: "empty",
                 users: [],
                 nearby_city_count: nearby_city_count
               }
      else
        result = { state: "ready", users: users }
        if expanded
          result[:expanded_radius] = true
          result[:original_radius_km] = radius
          result[:expanded_radius_km] = 200
        end
        render json: result
      end
    end

    def destroy
      UserLocation.find_by(user_id: current_user.id)&.destroy!
      render json: success_json.merge(state: "setup")
    end

    def debug_stats
      raise Discourse::InvalidAccess unless current_user.admin?

      active_locations = UserLocation.active_for_discovery

      render json: {
               window_days: report_window_days,
               active: active_locations.count,
               by_mode: active_locations.group(:discovery_mode).count,
               locations: {
                 active: location_totals(active_locations),
               },
               funnel:
                 WhereIsMyFriendsEvent.aggregate(
                   since: report_window_days.days.ago
                 )
             }
    end

    private

    def discover_nearby(origin, radius)
      nearby_keys =
        WhereIsMyFriends::CityCentroidLookup.instance.city_keys_within_radius(
          origin.city_key,
          radius
        )

      locations =
        UserLocation
          .active_for_discovery
          .where(city_key: nearby_keys)
          .where.not(user_id: current_user.id)
          .includes(user: :user_profile)
          .joins(:user)
          .order(
            Arel.sql(
              "CASE WHEN user_locations.updated_at > #{ActiveRecord::Base.connection.quote(7.days.ago)} THEN 0 ELSE 1 END, users.last_seen_at DESC NULLS LAST"
            )
          )
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

      [users, false]
    end

    def current_location
      UserLocation.active_for_discovery.find_by(user_id: current_user.id)
    end

    def state_for(location)
      return "ready" if location.present?

      "setup"
    end

    def discovery_mode
      params[:discovery_mode].presence || "city"
    end

    def upsert_location!
      existing = UserLocation.find_by(user_id: current_user.id)
      if radius_only_update?(existing)
        radius =
          UserLocation.normalize_discovery_radius_km(params[:discovery_radius_km])
        raise ActiveRecord::RecordInvalid if radius.blank?

        existing.update!(discovery_radius_km: radius)
        return existing
      end

      if discovery_mode == "city"
        UserLocation.upsert_city_location(
          current_user.id,
          city: params[:city],
          region: params[:region],
          discovery_radius_km: params[:discovery_radius_km]
        )
      else
        UserLocation.upsert_precise_location(
          current_user.id,
          city: params[:city],
          region: params[:region],
          discovery_mode: discovery_mode,
          latitude: params[:latitude],
          longitude: params[:longitude],
          location_accuracy: params[:location_accuracy],
          discovery_radius_km: params[:discovery_radius_km]
        )
      end
    end

    def radius_only_update?(existing)
      return false if existing.blank?
      return false if params[:discovery_radius_km].blank?
      return false if params[:city].blank?
      return false unless UserLocation.normalize_city(params[:city]) ==
                            existing.city_key
      return false unless discovery_mode == existing.discovery_mode
      return true if discovery_mode == "city"

      existing.precise? && params[:latitude].blank? && params[:longitude].blank?
    end

    def location_metadata(location)
      return nil if location.blank?

      {
        city: location.city,
        region: location.region,
        discovery_mode: location.discovery_mode,
        discovery_radius_km: location.effective_discovery_radius_km,
      }
    end

    def city_suggestions
      active =
        UserLocation
          .active_for_discovery
          .select("city_key, MIN(city) AS city, COUNT(*) AS member_count")
          .group(:city_key)
          .order("COUNT(*) DESC, MIN(city)")
          .limit(20)
          .map do |location|
            {
              city: location.city,
              city_key: location.city_key,
              count: location.member_count
            }
          end

      seen_keys = active.map { |suggestion| suggestion[:city_key] }.to_set

      seeds =
        SiteSetting
          .where_is_my_friends_seed_cities
          .to_s
          .split("|")
          .map(&:strip)
          .reject(&:blank?)
          .filter_map do |name|
            key = UserLocation.normalize_city(name)
            next if seen_keys.include?(key)

            seen_keys.add(key)
            { city: name, city_key: key, count: 0 }
          end

      (active + seeds).first(30)
    end

    def client_settings
      settings = {
        virtual_location_enabled:
          SiteSetting.where_is_my_friends_enable_virtual_location,
        map_provider: SiteSetting.where_is_my_friends_map_provider,
        aggregate_privacy_threshold:
          SiteSetting.where_is_my_friends_aggregate_privacy_threshold.to_i.clamp(
            2,
            20
          ),
        default_discovery_radius_km: UserLocation.default_discovery_radius_km,
        discovery_radius_options_km: UserLocation::DISCOVERY_RADIUS_OPTIONS_KM
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
      scope = UserLocation.active_for_discovery
      count = scope.count
      threshold =
        SiteSetting.where_is_my_friends_aggregate_privacy_threshold.to_i.clamp(
          2,
          20
        )
      return { suppressed: true } if count < threshold

      { suppressed: false, count: count, city_count: scope.distinct.count(:city_key) }
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

    def enqueue_member_joined_notification(location, previous_city_key)
      return if location.city_key.blank?
      return if previous_city_key == location.city_key

      Jobs.enqueue(
        :where_is_my_friends_notify_city_members,
        joiner_id: current_user.id,
        city: location.city,
        city_key: location.city_key
      )
    end
  end
end

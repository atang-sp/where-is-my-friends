# frozen_string_literal: true

module WhereIsMyFriends
  class LocationsController < ::ApplicationController
    REPORT_WINDOWS = [7, 30, 90].freeze

    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_plugin_enabled

    def index
      render json: LocationOverview.new(user: current_user).call
    end

    def create
      location =
        LocationSaver.new(user: current_user, params: params).call

      render json: { state: "ready", location: location_metadata(location) }
    rescue ActiveRecord::RecordInvalid
      render_json_error(
        I18n.t("where_is_my_friends.invalid_location"),
        status: 422
      )
    end

    def preview
      render json:
               CityPreview.new(user: current_user, city: params[:city]).call
    end

    def nearby
      render json:
               LocationDiscovery.new(
                 user: current_user,
                 origin: current_location,
                 raw_filters: params[:filters],
                 filterable_fields: FilterableFields.resolve
               ).call
    end

    def destroy
      UserLocation.find_by(user_id: current_user.id)&.destroy!
      render json: success_json.merge(state: "setup")
    end

    def debug_stats
      raise Discourse::InvalidAccess unless current_user.admin?

      active_locations = UserLocation.active_for_discovery
      window_days = report_window_days
      as_of = Time.current
      report =
        GrowthReport.new(
          since: as_of - window_days.days,
          as_of: as_of
        ).call

      render json: {
               window_days: window_days,
               active: active_locations.count,
               by_mode: active_locations.group(:discovery_mode).count,
               locations: {
                 active: location_totals(active_locations)
               }
             }.merge(report)
    end

    private

    def current_location
      UserLocation.active_for_discovery.find_by(user_id: current_user.id)
    end

    def location_metadata(location)
      return nil if location.blank?

      {
        city: location.city,
        region: location.region,
        discovery_mode: location.discovery_mode,
        discovery_radius_km: location.effective_discovery_radius_km
      }
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

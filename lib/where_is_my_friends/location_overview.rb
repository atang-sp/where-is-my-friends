# frozen_string_literal: true

module WhereIsMyFriends
  class LocationOverview
    def initialize(user:)
      @user = user
    end

    def call
      location = current_location
      protected_new_nearby_count =
        AggregatePrivacy.protect_counts(
          { new_nearby_count: new_nearby_count(location) },
          :new_nearby_count
        )

      {
        state: state_for(location),
        current_user: {
          id: @user.id,
          username: @user.username
        },
        location: location_metadata(location),
        active_participants: active_participants,
        city_suggestions: city_suggestions,
        city_directory: CityNetwork.new.directory,
        city_catalogue: CityCentroidLookup.instance.catalogue,
        settings: client_settings,
        profile_location: @user.user_profile&.location.presence,
        filterable_fields:
          resolved_filterable_fields.map do |field|
            field.slice(:name, :key, :options)
          end
      }.merge(protected_new_nearby_count)
    end

    private

    def current_location
      UserLocation.active_for_discovery.find_by(user_id: @user.id)
    end

    def state_for(location)
      location.present? ? "ready" : "setup"
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

    def city_suggestions
      active =
        UserLocation
          .discoverable
          .select("city_key, MIN(city) AS city, COUNT(*) AS member_count")
          .group(:city_key)
          .order("COUNT(*) DESC, MIN(city)")
          .limit(20)
          .map do |location|
            AggregatePrivacy.protect_counts(
              {
                city: location.city,
                city_key: location.city_key,
                count: location.member_count
              },
              :count
            )
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
          AggregatePrivacy.threshold,
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
      scope = UserLocation.discoverable
      count = scope.count
      protected = AggregatePrivacy.protect_counts({ count: count }, :count)
      return { suppressed: true } if protected[:count_suppressed]

      {
        suppressed: false,
        count: protected[:count],
        city_count: scope.distinct.count(:city_key)
      }
    end

    def new_nearby_count(location)
      return 0 if location.blank?

      radius = location.effective_discovery_radius_km
      nearby_keys =
        CityCentroidLookup.instance.city_keys_within_radius(
          location.city_key,
          radius
        )

      UserLocation
        .discoverable
        .where(city_key: nearby_keys)
        .where.not(user_id: @user.id)
        .where("user_locations.updated_at > ?", 7.days.ago)
        .count
    end

    def resolved_filterable_fields
      @resolved_filterable_fields ||= FilterableFields.resolve
    end
  end
end

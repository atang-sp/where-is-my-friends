# frozen_string_literal: true

require "digest"

module WhereIsMyFriends
  class CityNetwork
    ACTIVE_WINDOW = 90.days
    GROWTH_WINDOW = 30.days
    RECOMMENDED_ACTIVE_MEMBERS = 3
    DISTANCE_ROUNDING_KM = 10
    DIRECTORY_SECTION_LIMIT = 6

    def initialize(
      scope: UserLocation.discoverable,
      city_lookup: CityCentroidLookup.instance,
      now: Time.zone.now
    )
      @scope = scope
      @city_lookup = city_lookup
      @now = now
      @active_since = now - ACTIVE_WINDOW
      @growing_since = now - GROWTH_WINDOW
    end

    def directory(limit: DIRECTORY_SECTION_LIMIT)
      cities =
        stats_for_keys(nil, exclude_user_id: nil).values.map do |entry|
          decorate_city(entry)
        end

      {
        active:
          cities
            .sort_by do |entry|
              [-entry[:recent_active_count], rotation_key(entry[:city_key])]
            end
            .first(limit)
            .map { |entry| protect_city_counts(entry) },
        growing:
          cities
            .select { |entry| entry[:new_member_count].positive? }
            .sort_by do |entry|
              [
                -entry[:new_member_count],
                -entry[:recent_active_count],
                rotation_key(entry[:city_key])
              ]
            end
            .first(limit)
            .map { |entry| protect_city_counts(entry) },
        cities:
          cities
            .sort_by do |entry|
              [
                -entry[:recent_active_count],
                -entry[:joined_count],
                entry[:city]
              ]
            end
            .map { |entry| protect_city_counts(entry) },
        activity_window_days: (ACTIVE_WINDOW / 1.day).to_i,
        growth_window_days: (GROWTH_WINDOW / 1.day).to_i
      }
    end

    def preview(city:, exclude_user_id: nil)
      requested_city = city.to_s.strip
      city_key = UserLocation.normalize_city(requested_city)
      canonical = @city_lookup.centroid_for(city_key).present?
      city_stats = stats_for_keys([city_key], exclude_user_id: exclude_user_id)
      city_entry =
        city_stats.fetch(city_key, empty_stats(city_key, requested_city))

      radius_options =
        if canonical
          UserLocation::DISCOVERY_RADIUS_OPTIONS_KM.map do |radius_km|
            keys = @city_lookup.city_keys_within_radius(city_key, radius_km)
            stats =
              stats_for_keys(keys, exclude_user_id: exclude_user_id).values
            {
              radius_km: radius_km,
              recent_active_count:
                stats.sum { |entry| entry[:recent_active_count] },
              joined_count: stats.sum { |entry| entry[:joined_count] },
              city_count: stats.count { |entry| entry[:joined_count].positive? }
            }
          end
        else
          []
        end

      {
        city:
          protect_city_counts(
            city_entry.merge(
              canonical: canonical,
              region: @city_lookup.centroid_for(city_key)&.fetch(:region, nil)
            ),
            keys: %i[recent_active_count joined_count]
          ),
        radius_options:
          radius_options.map do |option|
            protect_city_counts(
              option,
              keys: %i[recent_active_count joined_count]
            )
          end,
        recommended_radius_km: recommended_radius(radius_options),
        recommended_active_members: RECOMMENDED_ACTIVE_MEMBERS,
        nearby_cities:
          nearby_cities(city_key, canonical, exclude_user_id: exclude_user_id)
      }
    end

    def group_members(origin_city_key:, locations:, serialized_users:)
      locations
        .zip(serialized_users)
        .group_by { |location, _serializer| location.city_key }
        .map do |city_key, entries|
          sorted_entries =
            entries.sort_by do |location, _serializer|
              last_seen = location.user.last_seen_at
              [
                last_seen.present? && last_seen >= @active_since ? 0 : 1,
                last_seen ? -last_seen.to_f : 0
              ]
            end
          distance = @city_lookup.distance_km_between(origin_city_key, city_key)
          recent_active_count =
            sorted_entries.count do |location, _serializer|
              location.user.last_seen_at.present? &&
                location.user.last_seen_at >= @active_since
            end

          {
            city: sorted_entries.first.first.city,
            city_key: city_key,
            distance_band:
              city_distance_band(origin_city_key, city_key, distance),
            approximate_distance_km:
              (
                if city_key == origin_city_key
                  nil
                else
                  approximate_distance(distance)
                end
              ),
            recent_active_count: recent_active_count,
            joined_count: sorted_entries.length,
            users: sorted_entries.map(&:last)
          }
        end
        .sort_by do |group|
          [
            group[:city_key] == origin_city_key ? 0 : 1,
            group[:approximate_distance_km] || 0,
            -group[:recent_active_count],
            group[:city]
          ]
        end
    end

    private

    def protect_city_counts(
      entry,
      keys: %i[recent_active_count joined_count new_member_count]
    )
      protected = AggregatePrivacy.protect_counts(entry, *keys)
      displayed_keys = keys & %i[recent_active_count joined_count]
      protected[:counts_suppressed] = displayed_keys.any? do |key|
        protected[:"#{key}_suppressed"]
      end
      protected
    end

    def stats_for_keys(city_keys, exclude_user_id:)
      return {} if city_keys&.empty?

      scope = @scope.joins(:user)
      scope = scope.where(city_key: city_keys) if city_keys
      scope = scope.where.not(user_id: exclude_user_id) if exclude_user_id
      quoted_active_since = ActiveRecord::Base.connection.quote(@active_since)
      quoted_growing_since = ActiveRecord::Base.connection.quote(@growing_since)

      scope
        .select(
          "user_locations.city_key",
          "MIN(user_locations.city) AS city_name",
          "COUNT(*) AS joined_count",
          "SUM(CASE WHEN users.last_seen_at >= #{quoted_active_since} THEN 1 ELSE 0 END) AS recent_active_count",
          "SUM(CASE WHEN user_locations.city_joined_at >= #{quoted_growing_since} THEN 1 ELSE 0 END) AS new_member_count"
        )
        .group("user_locations.city_key")
        .each_with_object({}) do |row, result|
          result[row.city_key] = {
            city: row.city_name,
            city_key: row.city_key,
            recent_active_count: row.recent_active_count.to_i,
            joined_count: row.joined_count.to_i,
            new_member_count: row.new_member_count.to_i
          }
        end
    end

    def empty_stats(city_key, requested_city)
      {
        city: requested_city.presence || city_key,
        city_key: city_key,
        recent_active_count: 0,
        joined_count: 0,
        new_member_count: 0
      }
    end

    def decorate_city(entry)
      centroid = @city_lookup.centroid_for(entry[:city_key])
      entry.merge(
        canonical: centroid.present?,
        region: centroid&.fetch(:region, nil)
      )
    end

    def rotation_key(city_key)
      Digest::SHA256.hexdigest("#{@now.to_date.iso8601}:#{city_key}")
    end

    def recommended_radius(options)
      return nil if options.empty?

      useful =
        options.find do |option|
          option[:recent_active_count] >= RECOMMENDED_ACTIVE_MEMBERS
        end
      return useful[:radius_km] if useful

      options.max_by do |option|
        [option[:recent_active_count], -option[:radius_km]]
      end[
        :radius_km
      ]
    end

    def nearby_cities(origin_key, canonical, exclude_user_id:)
      return [] unless canonical

      keys =
        @city_lookup.city_keys_within_radius(
          origin_key,
          UserLocation::DISCOVERY_RADIUS_OPTIONS_KM.max
        ) - [origin_key]

      stats_for_keys(keys, exclude_user_id: exclude_user_id)
        .values
        .filter_map do |entry|
          distance =
            @city_lookup.distance_km_between(origin_key, entry[:city_key])
          next if distance.nil?

          entry.merge(
            region:
              @city_lookup.centroid_for(entry[:city_key])&.fetch(:region, nil),
            approximate_distance_km: approximate_distance(distance)
          )
        end
        .sort_by do |entry|
          [
            entry[:approximate_distance_km],
            -entry[:recent_active_count],
            entry[:city]
          ]
        end
        .map do |entry|
          protect_city_counts(
            entry,
            keys: %i[recent_active_count joined_count new_member_count]
          )
        end
    end

    def approximate_distance(distance)
      return nil if distance.nil?

      [
        (distance / DISTANCE_ROUNDING_KM).round * DISTANCE_ROUNDING_KM,
        DISTANCE_ROUNDING_KM
      ].max
    end

    def city_distance_band(origin_key, city_key, distance)
      return "same_city" if city_key == origin_key
      return nil if distance.nil?
      return "nearby" if distance < UserLocation::CENTROID_NEARBY_KM
      return "moderate" if distance < UserLocation::CENTROID_MODERATE_KM

      "far"
    end
  end
end

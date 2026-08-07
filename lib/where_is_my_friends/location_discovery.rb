# frozen_string_literal: true

module WhereIsMyFriends
  class LocationDiscovery
    def initialize(user:, guardian:, origin:, raw_filters:, filterable_fields:)
      @user = user
      @guardian = guardian
      @member_selection =
        ViewerAwareMemberSelection.new(viewer: user, guardian: guardian)
      @origin = origin
      @raw_filters = raw_filters
      @filterable_fields = filterable_fields
    end

    def call
      return { state: "setup", users: [] } if @origin.blank?

      radius = @origin.effective_discovery_radius_km
      filters = validated_filters
      users, city_groups, results_limited = discover_nearby(radius, filters)
      expanded = false

      if users.empty? && radius < 200
        users, city_groups, expanded_results_limited =
          discover_nearby(200, filters)
        results_limited ||= expanded_results_limited
        expanded = true if users.any?
      end

      return limited_result(radius) if users.empty? && results_limited
      return empty_result(radius) if users.empty?

      result = { state: "ready", users: users, city_groups: city_groups }.merge(
        local_topic_snapshot(radius)
      )
      result[:results_limited] = true if results_limited
      if expanded
        result[:expanded_radius] = true
        result[:original_radius_km] = radius
        result[:expanded_radius_km] = 200
      end
      result
    end

    private

    def discover_nearby(radius, filters)
      nearby_keys =
        CityCentroidLookup.instance.city_keys_within_radius(
          @origin.city_key,
          radius
        )

      locations =
        UserLocation
          .discoverable
          .where(city_key: nearby_keys)
          .where.not(user_id: @user.id)
          .includes(user: %i[user_option user_profile user_stat])
          .joins(:user)

      filters.each_with_index do |(key, value), index|
        table_alias = "ucf_filter_#{index}"
        locations =
          locations.joins(
            ActiveRecord::Base.sanitize_sql_array(
              [
                "INNER JOIN user_custom_fields #{table_alias} " +
                  "ON #{table_alias}.user_id = user_locations.user_id " +
                  "AND #{table_alias}.name = ? AND #{table_alias}.value = ?",
                key,
                value
              ]
            )
          )
      end

      limit =
        UserLocation.discovery_limit(
          SiteSetting.where_is_my_friends_max_users_display
        )
      selection =
        @member_selection.select(
          scope:
            locations.order(
              Arel.sql(
                "CASE WHEN users.last_seen_at >= #{ActiveRecord::Base.connection.quote(90.days.ago)} THEN 0 ELSE 1 END, users.last_seen_at DESC NULLS LAST, users.id ASC"
              )
            ),
          limit: limit,
          scan_limit:
            limit * ViewerAwareMemberSelection::DEFAULT_SCAN_MULTIPLIER,
          &:user
        )
      locations = selection.items
      results_limited = selection.limited

      fields = @filterable_fields
      cf_map = load_custom_field_values(locations.map(&:user_id), fields)

      users =
        locations.map do |location|
          UserLocationSerializer.new(
            {
              user: location.user,
              location: location,
              origin: @origin,
              custom_field_values: cf_map[location.user_id] || {}
            },
            root: false
          )
        end

      groups =
        CityNetwork.new.group_members(
          origin_city_key: @origin.city_key,
          locations: locations,
          serialized_users: users
        )

      [users, groups, results_limited]
    end

    def empty_result(radius)
      nearby_keys =
        CityCentroidLookup.instance.city_keys_within_radius(
          @origin.city_key,
          radius
        ) - [@origin.city_key]
      nearby_city_count =
        UserLocation
          .discoverable
          .where(city_key: nearby_keys)
          .where.not(user_id: @user.id)
          .count
      protected_count =
        if nearby_city_count.zero?
          { nearby_city_count: 0, nearby_city_count_suppressed: false }
        else
          AggregatePrivacy.protect_counts(
            { nearby_city_count: nearby_city_count },
            :nearby_city_count
          )
        end

      { state: "empty", users: [] }.merge(protected_count).merge(
        local_topic_snapshot(radius)
      )
    end

    def limited_result(radius)
      { state: "limited", users: [], results_limited: true }.merge(
        local_topic_snapshot(radius)
      )
    end

    def local_topic_snapshot(radius)
      city_keys =
        CityCentroidLookup.instance.city_keys_within_radius(
          @origin.city_key,
          radius
        )
      {
        local_topics: LocalTopics.new(user: @user, city_keys: city_keys).call,
        local_topic_compose_url: LocalTopics.compose_url(@origin.city_key)
      }
    end

    def validated_filters
      raw = @raw_filters
      return {} if raw.blank? || !raw.respond_to?(:to_unsafe_h)

      allowed =
        @filterable_fields.each_with_object({}) do |field, values|
          values[field[:key]] = field[:options].to_set
        end

      raw
        .to_unsafe_h
        .each_with_object({}) do |(key, value), result|
          val = value.to_s.strip
          next if val.blank?

          result[key] = val if allowed[key]&.include?(val)
        end
    end

    def load_custom_field_values(user_ids, fields)
      return {} if fields.empty? || user_ids.empty?

      keys = fields.map { |field| field[:key] }
      name_map =
        fields.each_with_object({}) do |field, values|
          values[field[:key]] = field[:name]
        end

      UserCustomField
        .where(user_id: user_ids, name: keys)
        .pluck(:user_id, :name, :value)
        .group_by(&:first)
        .transform_values do |rows|
          rows.each_with_object({}) do |(_user_id, key, value), values|
            values[name_map[key]] = value if value.present?
          end
        end
    end
  end
end

# frozen_string_literal: true

class BackfillCityKeysFromCentroids < ActiveRecord::Migration[7.0]
  MAX_MATCH_KM = 80
  BATCH_SIZE = 200

  def up
    require File.expand_path(
              "../../../lib/where_is_my_friends/city_centroid_lookup",
              __dir__
            )
    lookup = WhereIsMyFriends::CityCentroidLookup.instance
    ttl_days =
      begin
        SiteSetting.where_is_my_friends_location_ttl_days.to_i.clamp(1, 365)
      rescue StandardError
        30
      end

    # Keep existing city records discoverable by ensuring expires_at is set.
    execute <<~SQL
      UPDATE user_locations
      SET expires_at = NOW() + INTERVAL '#{ttl_days} days'
      WHERE expires_at IS NULL
        AND city_key IS NOT NULL
        AND city_key <> ''
    SQL

    UserLocation
      .where(city_key: [nil, ""])
      .where.not(latitude: nil)
      .where.not(longitude: nil)
      .find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch.each do |location|
          match =
            lookup.nearest_city_for(
              location.latitude,
              location.longitude,
              max_km: MAX_MATCH_KM
            )
          next if match.blank?

          attrs = {
            city: match[:city_key],
            city_key: match[:city_key],
            region: location.region.presence || match[:region],
            expires_at: location.expires_at || ttl_days.days.from_now
          }
          location.update_columns(attrs)
        end
      end
  end

  def down
    # Irreversible data backfill.
  end
end

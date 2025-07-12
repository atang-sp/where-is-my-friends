# frozen_string_literal: true

class UserLocation < ActiveRecord::Base
  belongs_to :user

  validates :latitude, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  scope :enabled, -> { where(enabled: true) }

  def self.upsert_location(user_id, lat, lng)
    # Add some noise to protect privacy (roughly ±500m)
    noise_lat = lat + rand(-0.005..0.005)
    noise_lng = lng + rand(-0.005..0.005)

    location = find_or_initialize_by(user_id: user_id)
    location.latitude = noise_lat
    location.longitude = noise_lng
    location.enabled = true
    location.save!
    location
  end

  def self.nearby(lat, lng, distance_km = SiteSetting.where_is_my_friends_default_distance_km)
    # Simple distance calculation using Haversine formula
    # This is a simplified version - for production, consider using PostGIS
    enabled.joins(:user).where("
      (
        6371 * acos(
          GREATEST(LEAST(
            cos(radians(?)) * cos(radians(latitude)) *
            cos(radians(longitude) - radians(?)) +
            sin(radians(?)) * sin(radians(latitude))
          , 1), -1)
        )
      ) <= ?
    ", lat, lng, lat, distance_km)
  end

  def distance_to(lat, lng)
    # Calculate distance in kilometers
    rad_per_deg = Math::PI / 180
    earth_radius = 6371 # kilometers

    lat_rad = lat * rad_per_deg
    lng_rad = lng * rad_per_deg
    lat_rad_other = latitude * rad_per_deg
    lng_rad_other = longitude * rad_per_deg

    a_raw = Math.sin(lat_rad) * Math.sin(lat_rad_other) +
            Math.cos(lat_rad) * Math.cos(lat_rad_other) * Math.cos(lng_rad - lng_rad_other)
    # Clamp to [-1, 1] to avoid domain errors due to floating point overflows
    a = [[a_raw, 1.0].min, -1.0].max
    c = Math.acos(a)
    earth_radius * c
  end
end 
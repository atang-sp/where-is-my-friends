# frozen_string_literal: true

class UserLocation < ActiveRecord::Base
  belongs_to :user

  validates :latitude, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :location_type, inclusion: { in: %w[real virtual] }

  scope :enabled, -> { where(enabled: true) }
  scope :real_locations, -> { where(location_type: 'real') }
  scope :virtual_locations, -> { where(location_type: 'virtual') }

  def self.upsert_location(user_id, lat, lng, options = {})
    is_virtual = options[:is_virtual] || false
    virtual_address = options[:virtual_address]
    location_type = is_virtual ? 'virtual' : 'real'

    location = find_or_initialize_by(user_id: user_id)
    
    if is_virtual
      # 虚拟位置不需要添加噪声，直接使用用户选择的坐标
      location.latitude = lat
      location.longitude = lng
      location.is_virtual = true
      location.virtual_address = virtual_address
      location.location_type = 'virtual'
    else
      # 真实位置添加噪声以保护隐私（roughly ±500m）
    noise_lat = lat + rand(-0.005..0.005)
    noise_lng = lng + rand(-0.005..0.005)

    location.latitude = noise_lat
    location.longitude = noise_lng
      location.is_virtual = false
      location.virtual_address = nil
      location.location_type = 'real'
    end
    
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

  def virtual?
    is_virtual || location_type == 'virtual'
  end

  def real?
    !virtual?
  end
end 
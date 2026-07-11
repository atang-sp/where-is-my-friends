# frozen_string_literal: true

class UserLocation < ActiveRecord::Base
  CITY_SUFFIXES = %w[特别行政区 自治州 地区 盟 市].freeze

  belongs_to :user

  validates :latitude,
            numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 },
            allow_nil: true
  validates :longitude,
            numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 },
            allow_nil: true
  validates :location_type, inclusion: { in: %w[real virtual] }
  validates :location_source, inclusion: { in: %w[gps ip unknown virtual] }, allow_nil: true
  validates :city, :city_key, presence: true
  validates :discovery_mode, inclusion: { in: %w[city gps map] }
  validates :latitude, :longitude, presence: true, unless: :city_mode?

  scope :enabled, -> { where(enabled: true) }
  scope :real_locations, -> { where(location_type: 'real') }
  scope :virtual_locations, -> { where(location_type: 'virtual') }
  scope :gps_locations, -> { where(location_source: 'gps') }
  scope :ip_locations, -> { where(location_source: 'ip') }
  scope :active_for_discovery,
        -> { where(enabled: true).where.not(city_key: [nil, ""]).where("expires_at > ?", Time.current) }

  # 精度阈值（米）：低于此值认为是高精度定位
  HIGH_ACCURACY_THRESHOLD = 100  # 100米内认为是高精度

  def self.normalize_city(value)
    normalized = value.to_s.strip.gsub(/\s+/, " ").downcase
    suffix = CITY_SUFFIXES.find { |candidate| normalized.end_with?(candidate) }
    suffix ? normalized.delete_suffix(suffix) : normalized
  end

  def self.upsert_city_location(user_id, city:, region: nil)
    location = find_or_initialize_by(user_id: user_id)
    location.assign_attributes(
      city: city.to_s.strip,
      city_key: normalize_city(city),
      region: region.to_s.strip.presence,
      discovery_mode: "city",
      latitude: nil,
      longitude: nil,
      is_virtual: false,
      virtual_address: nil,
      location_type: "real",
      location_source: "unknown",
      location_accuracy: nil,
      enabled: true,
      expires_at: ttl_days.days.from_now,
    )
    location.save!
    location
  end

  def self.upsert_precise_location(
    user_id,
    city:,
    discovery_mode:,
    latitude:,
    longitude:,
    region: nil,
    location_accuracy: nil
  )
    location = find_or_initialize_by(user_id: user_id)
    map_mode = discovery_mode == "map"
    stored_latitude = latitude
    stored_longitude = longitude

    if discovery_mode == "gps" && latitude.present? && longitude.present?
      stored_latitude = latitude.to_f + rand(-0.005..0.005)
      stored_longitude = longitude.to_f + rand(-0.005..0.005)
    end

    location.assign_attributes(
      city: city.to_s.strip,
      city_key: normalize_city(city),
      region: region.to_s.strip.presence,
      discovery_mode: discovery_mode,
      latitude: stored_latitude,
      longitude: stored_longitude,
      is_virtual: map_mode,
      virtual_address: nil,
      location_type: map_mode ? "virtual" : "real",
      location_source: map_mode ? "virtual" : "gps",
      location_accuracy: map_mode ? nil : location_accuracy,
      enabled: true,
      expires_at: ttl_days.days.from_now,
    )
    location.save!
    location
  end

  def self.ttl_days
    SiteSetting.where_is_my_friends_location_ttl_days.to_i.clamp(1, 365)
  end

  def self.discovery_limit(requested)
    requested.to_i.clamp(10, 200)
  end
  
  def self.upsert_location(user_id, lat, lng, options = {})
    is_virtual = options[:is_virtual] || false
    virtual_address = options[:virtual_address]
    location_source = options[:location_source] || 'unknown'
    location_accuracy = options[:location_accuracy]

    location = find_or_initialize_by(user_id: user_id)
    
    if is_virtual
      # 虚拟位置不需要添加噪声，直接使用用户选择的坐标
      location.latitude = lat
      location.longitude = lng
      location.is_virtual = true
      location.virtual_address = virtual_address
      location.location_type = 'virtual'
      location.location_source = 'virtual'
      location.location_accuracy = nil
    else
      # 真实位置添加噪声以保护隐私（roughly ±500m）
      noise_lat = lat + rand(-0.005..0.005)
      noise_lng = lng + rand(-0.005..0.005)

      location.latitude = noise_lat
      location.longitude = noise_lng
      location.is_virtual = false
      location.virtual_address = nil
      location.location_type = 'real'
      location.location_source = location_source
      location.location_accuracy = location_accuracy
      
      Rails.logger.info "WhereIsMyFriends: [UPSERT] user_id=#{user_id} " \
                        "original=(#{lat}, #{lng}) noised=(#{noise_lat}, #{noise_lng}) " \
                        "source=#{location_source} accuracy=#{location_accuracy || 'N/A'}m"
    end
    
    location.enabled = true
    location.save!
    location
  end
  
  # 判断是否是高精度定位
  def high_accuracy?
    return true if virtual?  # 虚拟位置总是"精确"的
    return false if location_source == 'ip'
    return true if location_source == 'gps'
    
    # 如果有精度数据，检查是否在阈值内
    location_accuracy.present? && location_accuracy <= HIGH_ACCURACY_THRESHOLD
  end
  
  # 判断是否是低精度/IP定位
  def low_accuracy?
    !high_accuracy?
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

  def distance_band_to(other)
    return nil unless precise? && other.precise?

    distance = distance_to(other.latitude, other.longitude)
    return "under_5" if distance < 5
    return "5_to_20" if distance < 20

    "over_20"
  end

  def virtual?
    is_virtual || location_type == 'virtual'
  end

  def city_mode?
    discovery_mode == "city"
  end

  def precise?
    !city_mode? && latitude.present? && longitude.present?
  end

  def real?
    !virtual?
  end
end

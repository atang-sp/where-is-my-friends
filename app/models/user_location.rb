# frozen_string_literal: true

class UserLocation < ActiveRecord::Base
  CITY_SUFFIXES = %w[特别行政区 自治州 地区 盟 市].freeze
  DISCOVERY_MODES = %w[city gps map].freeze
  DISCOVERY_RADIUS_OPTIONS_KM = [50, 100, 200].freeze
  CENTROID_NEARBY_KM = 50.0
  CENTROID_MODERATE_KM = 150.0

  belongs_to :user

  validates :latitude,
            numericality: {
              greater_than_or_equal_to: -90,
              less_than_or_equal_to: 90
            },
            allow_nil: true
  validates :longitude,
            numericality: {
              greater_than_or_equal_to: -180,
              less_than_or_equal_to: 180
            },
            allow_nil: true
  validates :location_type, inclusion: { in: %w[real virtual] }
  validates :location_source,
            inclusion: {
              in: %w[gps unknown virtual]
            },
            allow_nil: true
  validates :city, :city_key, presence: true
  validates :discovery_mode, inclusion: { in: DISCOVERY_MODES }
  validates :latitude, :longitude, presence: true, unless: :city_mode?
  validates :discovery_radius_km,
            inclusion: {
              in: DISCOVERY_RADIUS_OPTIONS_KM
            },
            allow_nil: true

  scope :active_for_discovery,
        -> do
          where(enabled: true)
            .where.not(city_key: [nil, ""])
            .where("expires_at > ?", Time.current)
        end

  def self.normalize_city(value)
    normalized = value.to_s.strip.gsub(/\s+/, " ").downcase
    suffix = CITY_SUFFIXES.find { |candidate| normalized.end_with?(candidate) }
    suffix ? normalized.delete_suffix(suffix) : normalized
  end

  def self.default_discovery_radius_km
    SiteSetting
      .where_is_my_friends_default_discovery_radius_km
      .to_i
      .clamp(20, 500)
  end

  def self.normalize_discovery_radius_km(value)
    return nil if value.blank?

    radius = value.to_i
    DISCOVERY_RADIUS_OPTIONS_KM.include?(radius) ? radius : nil
  end

  def self.upsert_city_location(user_id, city:, region: nil, discovery_radius_km: nil)
    location = find_or_initialize_by(user_id: user_id)
    attrs = {
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
      expires_at: ttl_days.days.from_now
    }
    radius = normalize_discovery_radius_km(discovery_radius_km)
    attrs[:discovery_radius_km] = radius if radius
    location.assign_attributes(attrs)
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
    location_accuracy: nil,
    discovery_radius_km: nil
  )
    location = find_or_initialize_by(user_id: user_id)
    map_mode = discovery_mode == "map"
    stored_latitude = latitude
    stored_longitude = longitude

    if discovery_mode == "gps" && latitude.present? && longitude.present?
      stored_latitude = latitude.to_f + rand(-0.005..0.005)
      stored_longitude = longitude.to_f + rand(-0.005..0.005)
    end

    attrs = {
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
      expires_at: ttl_days.days.from_now
    }
    radius = normalize_discovery_radius_km(discovery_radius_km)
    attrs[:discovery_radius_km] = radius if radius
    location.assign_attributes(attrs)
    location.save!
    location
  end

  def self.ttl_days
    SiteSetting.where_is_my_friends_location_ttl_days.to_i.clamp(1, 365)
  end

  def self.discovery_limit(requested)
    requested.to_i.clamp(10, 200)
  end

  def effective_discovery_radius_km
    discovery_radius_km.presence || self.class.default_discovery_radius_km
  end

  def distance_band_to(other)
    if precise? && other.precise?
      distance = distance_to(other.latitude, other.longitude)
      return "under_5" if distance < 5
      return "5_to_20" if distance < 20

      return "over_20"
    end

    return "same_city" if city_key.present? && city_key == other.city_key

    centroid_distance =
      WhereIsMyFriends::CityCentroidLookup.instance.distance_km_between(
        city_key,
        other.city_key
      )
    return nil if centroid_distance.nil?
    return "nearby" if centroid_distance < CENTROID_NEARBY_KM
    return "moderate" if centroid_distance < CENTROID_MODERATE_KM

    "far"
  end

  def city_mode?
    discovery_mode == "city"
  end

  def precise?
    !city_mode? && latitude.present? && longitude.present?
  end

  private

  def distance_to(other_latitude, other_longitude)
    radians = Math::PI / 180
    latitude_radians = other_latitude * radians
    longitude_radians = other_longitude * radians
    stored_latitude_radians = latitude * radians
    stored_longitude_radians = longitude * radians

    cosine =
      Math.sin(latitude_radians) * Math.sin(stored_latitude_radians) +
        Math.cos(latitude_radians) * Math.cos(stored_latitude_radians) *
          Math.cos(longitude_radians - stored_longitude_radians)

    6371 * Math.acos(cosine.clamp(-1.0, 1.0))
  end
end

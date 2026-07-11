# frozen_string_literal: true

require "json"

module WhereIsMyFriends
  class CityCentroidLookup
    DATA_PATH =
      File.expand_path("../../../data/city_centroids.json", __dir__).freeze
    EARTH_RADIUS_KM = 6371.0

    def self.instance
      @instance ||= new
    end

    def self.reset!
      @instance = nil
    end

    def initialize(path: DATA_PATH)
      @centroids = load_centroids(path)
    end

    def centroid_for(city_key)
      @centroids[city_key.to_s]
    end

    def city_keys_within_radius(origin_key, radius_km)
      key = origin_key.to_s
      origin = centroid_for(key)
      return [key] if origin.blank?

      radius = radius_km.to_f
      nearby =
        @centroids.filter_map do |candidate_key, centroid|
          next if candidate_key == key
          next if haversine_km(origin, centroid) > radius

          candidate_key
        end

      nearby.unshift(key)
    end

    def distance_km_between(city_key_a, city_key_b)
      a = centroid_for(city_key_a)
      b = centroid_for(city_key_b)
      return nil if a.blank? || b.blank?

      haversine_km(a, b)
    end

    # Returns { city_key:, lat:, lng:, region:, distance_km: } or nil.
    def nearest_city_for(latitude, longitude, max_km: 80)
      return nil if latitude.blank? || longitude.blank?

      origin = { lat: latitude.to_f, lng: longitude.to_f }
      best_key = nil
      best_centroid = nil
      best_distance = nil

      @centroids.each do |city_key, centroid|
        distance = haversine_km(origin, centroid)
        next if distance > max_km
        next if best_distance && distance >= best_distance

        best_key = city_key
        best_centroid = centroid
        best_distance = distance
      end

      return nil if best_key.blank?

      {
        city_key: best_key,
        lat: best_centroid[:lat],
        lng: best_centroid[:lng],
        region: best_centroid[:region],
        distance_km: best_distance
      }
    end

    private

    def load_centroids(path)
      raw = JSON.parse(File.read(path))
      raw.transform_values do |entry|
        { lat: entry.fetch("lat").to_f, lng: entry.fetch("lng").to_f, region: entry["region"] }
      end
    end

    def haversine_km(a, b)
      radians = Math::PI / 180
      lat1 = a[:lat] * radians
      lng1 = a[:lng] * radians
      lat2 = b[:lat] * radians
      lng2 = b[:lng] * radians

      cosine =
        Math.sin(lat1) * Math.sin(lat2) +
          Math.cos(lat1) * Math.cos(lat2) * Math.cos(lng2 - lng1)

      EARTH_RADIUS_KM * Math.acos(cosine.clamp(-1.0, 1.0))
    end
  end
end

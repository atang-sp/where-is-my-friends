# frozen_string_literal: true

require "cgi"

class UserLocationSerializer < ApplicationSerializer
  attributes :id,
             :username,
             :name,
             :avatar_template,
             :city,
             :distance_band,
             :message_url,
             :is_recent,
             :online,
             :activity_status,
             :last_seen_at,
             :last_posted_at,
             :bio_excerpt,
             :custom_fields,
             :user_tags,
             :community_level,
             :role_key

  def id
    user.id
  end

  def username
    user.username
  end

  def name
    user.name
  end

  def avatar_template
    user.avatar_template
  end

  def city
    location.city
  end

  def distance_band
    object[:origin].distance_band_to(location)
  end

  def message_url
    "/new-message?username=#{CGI.escape(username)}"
  end

  def is_recent
    location.updated_at > 7.days.ago
  end

  def activity_status
    return "online" if online

    last_seen = user.last_seen_at
    last_seen.present? && last_seen >= 90.days.ago ? "recent" : "inactive"
  end

  def online
    return false if user.user_option&.hide_presence

    user.last_seen_at.present? && user.last_seen_at >= 5.minutes.ago
  end

  def last_seen_at
    return nil if user.user_option&.hide_presence

    user.last_seen_at&.iso8601
  end

  def last_posted_at
    user.last_posted_at&.iso8601
  end

  def bio_excerpt
    raw = user.user_profile&.bio_raw
    return nil if raw.blank?

    raw.to_s.gsub(/\s+/, " ").strip.truncate(80)
  end

  def custom_fields
    object[:custom_field_values] || {}
  end

  def user_tags
    return [] unless WhereIsMyFriends::UserTagVisibility.feature_enabled?

    WhereIsMyFriends::UserTagVisibility.public_tags_for(
      user,
      viewer: scope.user
    )
  end

  def community_level
    if object.key?(:community_level)
      object[:community_level]
    elsif defined?(::DiscourseCommunityLevels::SerializerHelpers) &&
          defined?(::DiscourseCommunityLevels::GamificationScoreProvider) &&
          DiscourseCommunityLevels::SerializerHelpers.enabled?
      DiscourseCommunityLevels::SerializerHelpers.public_level_payload(
        DiscourseCommunityLevels::GamificationScoreProvider.score_for(user)
      )
    end
  rescue StandardError
    nil
  end

  def role_key
    if object.key?(:role_key)
      object[:role_key]
    else
      resolve_role_key
    end
  end

  private

  def resolve_role_key
    cf = custom_fields
    if cf.is_a?(Hash)
      role_val = cf.values.find do |v|
        self.class.map_role_value(v).present?
      end
      return self.class.map_role_value(role_val) if role_val.present?
    end

    if defined?(WhereIsMyFriendsUserInterest)
      WhereIsMyFriendsUserInterest
        .where(user_id: user.id)
        .joins(:tag)
        .pluck("tags.name")
        .each do |tname|
          mapped = self.class.map_role_value(tname)
          return mapped if mapped.present?
        end
    end

    nil
  rescue StandardError
    nil
  end

  def self.map_role_value(val)
    case val.to_s.strip.downcase
    when "active_role", "active", "主动", "主"
      "active_role"
    when "passive_role", "passive", "被动", "被"
      "passive_role"
    when "switch_role", "switch", "双向", "双"
      "switch_role"
    end
  end

  def user
    object[:user]
  end

  def location
    object[:location]
  end
end

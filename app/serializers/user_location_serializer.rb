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
             :custom_fields

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

  private

  def user
    object[:user]
  end

  def location
    object[:location]
  end
end

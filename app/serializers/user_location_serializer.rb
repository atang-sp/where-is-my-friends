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
             :last_seen_at,
             :bio_excerpt

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

  def last_seen_at
    user.last_seen_at&.iso8601
  end

  def bio_excerpt
    raw = user.user_profile&.bio_raw
    return nil if raw.blank?

    raw.to_s.gsub(/\s+/, " ").strip.truncate(80)
  end

  private

  def user
    object[:user]
  end

  def location
    object[:location]
  end
end

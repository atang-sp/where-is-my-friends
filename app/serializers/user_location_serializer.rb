# frozen_string_literal: true

require "cgi"

class UserLocationSerializer < ApplicationSerializer
  attributes :id,
             :username,
             :name,
             :avatar_template,
             :city,
             :region,
             :discovery_mode,
             :distance_band,
             :last_seen_at,
             :is_online,
             :bio,
             :profile_url,
             :message_url,
             :local_topics_url

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

  def region
    location.region
  end

  def discovery_mode
    location.discovery_mode
  end

  def distance_band
    object[:origin].distance_band_to(location)
  end

  def last_seen_at
    user.last_seen_at
  end

  def is_online
    user.last_seen_at.present? && user.last_seen_at > 5.minutes.ago
  end

  def bio
    user.user_profile&.bio_raw
  end

  def profile_url
    "/u/#{CGI.escape(username)}"
  end

  def message_url
    "/new-message?username=#{CGI.escape(username)}"
  end

  def local_topics_url
    "/search?q=#{CGI.escape(location.city)}"
  end

  private

  def user
    object[:user]
  end

  def location
    object[:location]
  end
end

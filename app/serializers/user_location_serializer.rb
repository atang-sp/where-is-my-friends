# frozen_string_literal: true

require "cgi"

class UserLocationSerializer < ApplicationSerializer
  attributes :id,
             :username,
             :name,
             :avatar_template,
             :city,
             :distance_band,
             :message_url

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

  private

  def user
    object[:user]
  end

  def location
    object[:location]
  end
end

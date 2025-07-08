# frozen_string_literal: true

class UserLocationSerializer < ApplicationSerializer
  attributes :username, :name, :avatar_template, :distance, :last_seen_at

  def username
    object[:user].username
  end

  def name
    object[:user].name
  end

  def avatar_template
    object[:user].avatar_template
  end

  def distance
    object[:distance]
  end

  def last_seen_at
    object[:user].last_seen_at
  end
end 
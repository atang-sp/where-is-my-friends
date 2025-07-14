# frozen_string_literal: true

class UserLocationSerializer < ApplicationSerializer
  attributes :username, :name, :avatar_template, :distance, :last_seen_at, 
             :is_virtual, :virtual_address, :location_type

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

  def is_virtual
    object[:location].is_virtual || false
  end

  def virtual_address
    object[:location].virtual_address
  end

  def location_type
    object[:location].location_type || 'real'
  end
end 
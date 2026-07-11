# frozen_string_literal: true

class AddDiscoveryRadiusToUserLocations < ActiveRecord::Migration[7.0]
  def change
    add_column :user_locations, :discovery_radius_km, :integer
  end
end

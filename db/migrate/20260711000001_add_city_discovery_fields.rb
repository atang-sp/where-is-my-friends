# frozen_string_literal: true

class AddCityDiscoveryFields < ActiveRecord::Migration[7.0]
  def up
    change_column_null :user_locations, :latitude, true
    change_column_null :user_locations, :longitude, true

    add_column :user_locations, :city, :string
    add_column :user_locations, :city_key, :string
    add_column :user_locations, :region, :string
    add_column :user_locations,
               :discovery_mode,
               :string,
               null: false,
               default: "city"
    add_column :user_locations, :expires_at, :datetime

    execute <<~SQL
      UPDATE user_locations
      SET discovery_mode = CASE WHEN is_virtual THEN 'map' ELSE 'gps' END
    SQL

    add_index :user_locations,
              %i[city_key enabled expires_at],
              name: "idx_user_locations_discovery"
  end

  def down
    remove_index :user_locations, name: "idx_user_locations_discovery"
    remove_columns :user_locations,
                   :city,
                   :city_key,
                   :region,
                   :discovery_mode,
                   :expires_at
    change_column_null :user_locations, :latitude, false
    change_column_null :user_locations, :longitude, false
  end
end

# frozen_string_literal: true

class AddCityJoinedAtToUserLocations < ActiveRecord::Migration[7.0]
  def up
    add_column :user_locations, :city_joined_at, :datetime
    execute <<~SQL
      UPDATE user_locations
      SET city_joined_at = created_at
      WHERE city_joined_at IS NULL
    SQL
    change_column_null :user_locations, :city_joined_at, false
  end

  def down
    remove_column :user_locations, :city_joined_at
  end
end

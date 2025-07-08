# frozen_string_literal: true

class CreateUserLocations < ActiveRecord::Migration[7.0]
  def change
    create_table :user_locations do |t|
      t.integer :user_id, null: false
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end

    add_index :user_locations, :user_id, unique: true
    add_index :user_locations, [:latitude, :longitude]
    add_index :user_locations, :enabled

    add_foreign_key :user_locations, :users, on_delete: :cascade
  end
end 
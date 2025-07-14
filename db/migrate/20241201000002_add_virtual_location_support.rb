# frozen_string_literal: true

class AddVirtualLocationSupport < ActiveRecord::Migration[7.0]
  def change
    add_column :user_locations, :is_virtual, :boolean, default: false, null: false
    add_column :user_locations, :virtual_address, :text
    add_column :user_locations, :location_type, :string, default: 'real', null: false
    
    add_index :user_locations, :is_virtual
    add_index :user_locations, :location_type
  end
end 
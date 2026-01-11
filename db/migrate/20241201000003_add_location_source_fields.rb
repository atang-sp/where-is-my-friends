# frozen_string_literal: true

class AddLocationSourceFields < ActiveRecord::Migration[7.0]
  def change
    add_column :user_locations, :location_source, :string, default: 'unknown'
    add_column :user_locations, :location_accuracy, :float  # 精度（米）
    
    add_index :user_locations, :location_source
  end
end


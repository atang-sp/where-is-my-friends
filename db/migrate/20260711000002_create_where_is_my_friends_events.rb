# frozen_string_literal: true

class CreateWhereIsMyFriendsEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :where_is_my_friends_events do |t|
      t.integer :user_id, null: false
      t.string :event_name, null: false
      t.string :location_mode
      t.string :result_bucket
      t.timestamps
    end

    add_index :where_is_my_friends_events, %i[event_name created_at]
    add_index :where_is_my_friends_events, %i[user_id created_at]
    add_foreign_key :where_is_my_friends_events, :users, on_delete: :cascade
  end
end

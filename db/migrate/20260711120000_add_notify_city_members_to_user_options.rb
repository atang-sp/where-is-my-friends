# frozen_string_literal: true

class AddNotifyCityMembersToUserOptions < ActiveRecord::Migration[7.0]
  def change
    add_column :user_options,
               :where_is_my_friends_notify_city,
               :boolean,
               default: true,
               null: false
  end
end

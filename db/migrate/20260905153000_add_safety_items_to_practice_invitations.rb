# frozen_string_literal: true

class AddSafetyItemsToPracticeInvitations < ActiveRecord::Migration[7.0]
  def change
    add_column :where_is_my_friends_practice_invitations,
               :safety_items,
               :jsonb,
               default: [],
               null: false
  end
end

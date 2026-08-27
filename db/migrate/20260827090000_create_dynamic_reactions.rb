# frozen_string_literal: true

class CreateDynamicReactions < ActiveRecord::Migration[7.0]
  def change
    create_table :where_is_my_friends_dynamic_reactions do |t|
      t.bigint :topic_id, null: false
      t.bigint :user_id, null: false
      t.bigint :notification_id
      t.string :kind, null: false
      t.timestamps
    end

    add_index :where_is_my_friends_dynamic_reactions,
              %i[topic_id user_id],
              unique: true,
              name: "idx_wimf_dynamic_reactions_topic_user"
    add_index :where_is_my_friends_dynamic_reactions,
              :user_id,
              name: "idx_wimf_dynamic_reactions_user"
    add_index :where_is_my_friends_dynamic_reactions,
              :notification_id,
              unique: true,
              name: "idx_wimf_dynamic_reactions_notification"

    add_foreign_key :where_is_my_friends_dynamic_reactions,
                    :topics,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_dynamic_reactions,
                    :users,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_dynamic_reactions,
                    :notifications,
                    on_delete: :nullify
  end
end

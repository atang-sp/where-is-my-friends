# frozen_string_literal: true

class CreateLegacyPracticeImportData < ActiveRecord::Migration[7.0]
  def change
    create_table :where_is_my_friends_legacy_practice_bookmarks do |t|
      t.integer :user_id, null: false
      t.integer :target_user_id, null: false
      t.bigint :source_practice_interest_id
      t.datetime :source_created_at
      t.string :state, null: false, default: "needs_reconfirmation"
      t.boolean :mutual_history, null: false, default: false
      t.datetime :confirmed_at
      t.datetime :dismissed_at
      t.timestamps
    end

    add_index :where_is_my_friends_legacy_practice_bookmarks,
              %i[user_id target_user_id],
              unique: true,
              name: "idx_wimf_legacy_bookmarks_unique"
    add_index :where_is_my_friends_legacy_practice_bookmarks,
              %i[user_id state],
              name: "idx_wimf_legacy_bookmarks_user_state"
    add_foreign_key :where_is_my_friends_legacy_practice_bookmarks,
                    :users,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_legacy_practice_bookmarks,
                    :users,
                    column: :target_user_id,
                    on_delete: :cascade

    create_table :where_is_my_friends_legacy_practice_pairs do |t|
      t.integer :user_a_id, null: false
      t.integer :user_b_id, null: false
      t.datetime :matched_at, null: false
      t.boolean :notification_suppressed, null: false, default: true
      t.timestamps
    end

    add_index :where_is_my_friends_legacy_practice_pairs,
              %i[user_a_id user_b_id],
              unique: true,
              name: "idx_wimf_legacy_pairs_unique"
    add_foreign_key :where_is_my_friends_legacy_practice_pairs,
                    :users,
                    column: :user_a_id,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_legacy_practice_pairs,
                    :users,
                    column: :user_b_id,
                    on_delete: :cascade
    add_check_constraint :where_is_my_friends_legacy_practice_pairs,
                         "user_a_id < user_b_id",
                         name: "wimf_legacy_pairs_ordered"
  end
end

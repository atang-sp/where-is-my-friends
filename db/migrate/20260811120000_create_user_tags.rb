# frozen_string_literal: true

class CreateUserTags < ActiveRecord::Migration[7.0]
  def change
    add_column :user_options,
               :where_is_my_friends_accept_user_tags,
               :boolean,
               default: true,
               null: false

    create_table :where_is_my_friends_user_tags do |t|
      t.integer :proposer_id, null: false
      t.integer :target_user_id, null: false
      t.string :label, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :responded_at
      t.timestamps
    end

    add_index :where_is_my_friends_user_tags,
              %i[proposer_id target_user_id label],
              unique: true,
              name: "idx_wimf_user_tags_proposer_target_label"
    add_index :where_is_my_friends_user_tags,
              %i[target_user_id status],
              name: "idx_wimf_user_tags_target_status"

    add_foreign_key :where_is_my_friends_user_tags,
                    :users,
                    column: :proposer_id,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_user_tags,
                    :users,
                    column: :target_user_id,
                    on_delete: :cascade

    create_table :where_is_my_friends_tag_endorsements do |t|
      t.integer :tag_id, null: false
      t.integer :user_id, null: false
      t.timestamps
    end

    add_index :where_is_my_friends_tag_endorsements,
              %i[tag_id user_id],
              unique: true,
              name: "idx_wimf_tag_endorsements_tag_user"
    add_index :where_is_my_friends_tag_endorsements,
              :user_id,
              name: "idx_wimf_tag_endorsements_user"

    add_foreign_key :where_is_my_friends_tag_endorsements,
                    :where_is_my_friends_user_tags,
                    column: :tag_id,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_tag_endorsements,
                    :users,
                    column: :user_id,
                    on_delete: :cascade
  end
end

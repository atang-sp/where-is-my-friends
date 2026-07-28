# frozen_string_literal: true

class CreatePracticeInvitations < ActiveRecord::Migration[7.0]
  def change
    add_column :user_options,
               :where_is_my_friends_accept_practice_invitations,
               :boolean,
               default: true,
               null: false

    create_table :where_is_my_friends_practice_invitations do |t|
      t.integer :sender_id, null: false
      t.integer :recipient_id, null: false
      t.integer :tag_id, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :proposed_at
      t.text :note
      t.datetime :responded_at
      t.integer :pm_topic_id
      t.string :source, null: false, default: "native"
      t.timestamps
    end

    add_index :where_is_my_friends_practice_invitations,
              %i[sender_id created_at],
              name: "idx_wimf_practice_invites_sender_created"
    add_index :where_is_my_friends_practice_invitations,
              %i[recipient_id status created_at],
              name: "idx_wimf_practice_invites_recipient_status"
    add_index :where_is_my_friends_practice_invitations,
              :tag_id,
              name: "idx_wimf_practice_invites_tag"
    add_index :where_is_my_friends_practice_invitations,
              :pm_topic_id,
              name: "idx_wimf_practice_invites_pm_topic"
    add_index :where_is_my_friends_practice_invitations,
              "LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id)",
              unique: true,
              where: "status = 'pending'",
              name: "idx_wimf_practice_invites_pending_pair"

    add_foreign_key :where_is_my_friends_practice_invitations,
                    :users,
                    column: :sender_id,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_practice_invitations,
                    :users,
                    column: :recipient_id,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_practice_invitations,
                    :tags,
                    on_delete: :restrict
    add_foreign_key :where_is_my_friends_practice_invitations,
                    :topics,
                    column: :pm_topic_id,
                    on_delete: :nullify
  end
end

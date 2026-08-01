# frozen_string_literal: true

class CreateWhereIsMyFriendsAiProviderProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :where_is_my_friends_ai_provider_profiles do |t|
      t.string :name, null: false
      t.string :purpose, null: false
      t.string :protocol, null: false
      t.string :structured_output_mode, null: false, default: "json_schema"
      t.string :base_url, null: false
      t.string :model, null: false
      t.string :api_key, limit: 10_000, null: false
      t.boolean :active, null: false, default: false
      t.datetime :verified_at
      t.string :verified_config_digest
      t.datetime :last_tested_at
      t.string :last_test_status
      t.string :last_test_error_code
      t.bigint :created_by_id, null: false
      t.bigint :updated_by_id, null: false
      t.timestamps
    end

    add_index(
      :where_is_my_friends_ai_provider_profiles,
      :purpose,
      unique: true,
      where: "active = TRUE",
      name: "idx_wimf_ai_profiles_one_active_per_purpose"
    )
    add_index :where_is_my_friends_ai_provider_profiles, :created_by_id
    add_index :where_is_my_friends_ai_provider_profiles, :updated_by_id
  end
end

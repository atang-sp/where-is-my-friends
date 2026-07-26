# frozen_string_literal: true

class CreateInterestRecommendationData < ActiveRecord::Migration[7.0]
  def change
    create_table :where_is_my_friends_interest_profiles do |t|
      t.integer :user_id, null: false
      t.string :purpose
      t.boolean :personalization_enabled, default: true, null: false
      t.boolean :recommendable, default: true, null: false
      t.boolean :show_interests_publicly, default: false, null: false
      t.datetime :completed_at
      t.datetime :dismissed_at
      t.timestamps
    end

    add_index :where_is_my_friends_interest_profiles,
              :user_id,
              unique: true,
              name: "idx_wimf_interest_profiles_user"
    add_foreign_key :where_is_my_friends_interest_profiles,
                    :users,
                    on_delete: :cascade

    create_table :where_is_my_friends_user_interests do |t|
      t.integer :user_id, null: false
      t.integer :tag_id, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :where_is_my_friends_user_interests,
              %i[user_id tag_id],
              unique: true,
              name: "idx_wimf_user_interests_unique"
    add_index :where_is_my_friends_user_interests,
              :tag_id,
              name: "idx_wimf_user_interests_tag"
    add_foreign_key :where_is_my_friends_user_interests,
                    :users,
                    on_delete: :cascade
    add_foreign_key :where_is_my_friends_user_interests,
                    :tags,
                    on_delete: :cascade

    create_table :where_is_my_friends_recommendation_dismissals do |t|
      t.integer :user_id, null: false
      t.string :target_type, null: false
      t.integer :target_id, null: false
      t.timestamps
    end

    add_index :where_is_my_friends_recommendation_dismissals,
              %i[user_id target_type target_id],
              unique: true,
              name: "idx_wimf_recommendation_dismissals_unique"
    add_index :where_is_my_friends_recommendation_dismissals,
              %i[target_type target_id],
              name: "idx_wimf_recommendation_dismissals_target"
    add_foreign_key :where_is_my_friends_recommendation_dismissals,
                    :users,
                    on_delete: :cascade
  end
end

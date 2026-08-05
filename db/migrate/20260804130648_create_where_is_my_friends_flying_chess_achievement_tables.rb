# frozen_string_literal: true

class CreateWhereIsMyFriendsFlyingChessAchievementTables < ActiveRecord::Migration[
  8.0
]
  def change
    create_table :where_is_my_friends_flying_chess_completions do |t|
      t.bigint :user_id, null: false
      t.string :claim_id, limit: 128, null: false
      t.string :game_id, limit: 128, null: false
      t.string :player_id, limit: 128, null: false
      t.string :mode, limit: 64, null: false
      t.string :ruleset_version, limit: 128, null: false
      t.datetime :completed_at, null: false
      t.integer :place, null: false
      t.boolean :winner, default: false, null: false
      t.timestamps
    end

    add_index :where_is_my_friends_flying_chess_completions,
              :claim_id,
              unique: true,
              name: "idx_wimf_fc_completions_claim"
    add_index :where_is_my_friends_flying_chess_completions,
              %i[game_id player_id],
              unique: true,
              name: "idx_wimf_fc_completions_seat"
    add_index :where_is_my_friends_flying_chess_completions,
              %i[user_id game_id],
              unique: true,
              name: "idx_wimf_fc_completions_user_game"

    create_table :where_is_my_friends_flying_chess_profiles do |t|
      t.bigint :user_id, null: false
      t.integer :completed_games, default: 0, null: false
      t.datetime :first_completed_at
      t.boolean :profile_visible, default: true, null: false
      t.timestamps
    end

    add_index :where_is_my_friends_flying_chess_profiles,
              :user_id,
              unique: true,
              name: "idx_wimf_fc_profiles_user"
  end
end

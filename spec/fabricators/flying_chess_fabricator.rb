# frozen_string_literal: true

Fabricator(:where_is_my_friends_flying_chess_completion) do
  user
  claim_id { sequence(:flying_chess_claim_id) { |i| "claim-#{i}" } }
  game_id { sequence(:flying_chess_game_id) { |i| "game-#{i}" } }
  player_id { sequence(:flying_chess_player_id) { |i| "player-#{i}" } }
  mode { WhereIsMyFriends::FlyingChess::ClaimToken::MODE }
  ruleset_version { "party-v1" }
  completed_at { 1.hour.ago }
  place { 1 }
  winner { true }
end

Fabricator(:where_is_my_friends_flying_chess_profile) do
  user
  completed_games { 0 }
  first_completed_at { nil }
  profile_visible { true }
end

# frozen_string_literal: true

class WhereIsMyFriendsFlyingChessCompletion < ActiveRecord::Base
  belongs_to :user

  validates :claim_id,
            :game_id,
            :player_id,
            :mode,
            :ruleset_version,
            presence: true
  validates :claim_id,
            :game_id,
            :player_id,
            :ruleset_version,
            length: {
              maximum: 128
            }
  validates :mode, length: { maximum: 64 }
  validates :claim_id, uniqueness: true
  validates :player_id, uniqueness: { scope: :game_id }
  validates :game_id, uniqueness: { scope: :user_id }
  validates :place, numericality: { only_integer: true, greater_than: 0 }
  validates :completed_at, presence: true

  def self.claimable_by?(user:, claim:)
    existing_claim = find_by(claim_id: claim.claim_id)
    return existing_claim.matches?(user:, claim:) if existing_claim

    existing_seat = find_by(game_id: claim.game_id, player_id: claim.player_id)
    return existing_seat.matches?(user:, claim:) if existing_seat

    !exists?(user:, game_id: claim.game_id)
  end

  def self.record!(user:, claim:)
    existing = find_by(claim_id: claim.claim_id)
    existing ||= find_by(game_id: claim.game_id, player_id: claim.player_id)
    return existing if existing&.matches?(user:, claim:)

    create!(user:, **claim.completion_attributes)
  end

  def matches?(user:, claim:)
    user_id == user.id && claim_id == claim.claim_id &&
      game_id == claim.game_id && player_id == claim.player_id &&
      mode == claim.mode && ruleset_version == claim.ruleset_version &&
      completed_at.to_i == claim.completed_at && place == claim.place &&
      winner? == claim.winner
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsFlyingChessCompletion do
  describe ".claimable_by?" do
    subject(:claimable) { described_class.claimable_by?(user:, claim:) }

    fab!(:user)
    let(:completed_at) { Time.zone.parse("2026-08-05 11:00:00").to_i }
    let(:claim) do
      WhereIsMyFriends::FlyingChess::ClaimToken::Claim.new(
        claim_id: "claim-1",
        game_id: "game-1",
        player_id: "player-1",
        mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
        ruleset_version: "party-v1",
        completed_at:,
        place: 1,
        winner: true,
        issued_at: completed_at,
        expires_at: completed_at + 1.day.to_i
      )
    end

    context "without an existing completion" do
      it { is_expected.to eq(true) }
    end

    context "with an exact existing completion" do
      fab!(:existing_completion) do
        Fabricate(
          :where_is_my_friends_flying_chess_completion,
          user:,
          claim_id: "claim-1",
          game_id: "game-1",
          player_id: "player-1",
          mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
          ruleset_version: "party-v1",
          completed_at: Time.zone.parse("2026-08-05 11:00:00"),
          place: 1,
          winner: true
        )
      end

      it { is_expected.to eq(true) }
    end

    context "when another user already owns the claim id" do
      fab!(:existing_owner, :user)
      fab!(:existing_completion) do
        Fabricate(
          :where_is_my_friends_flying_chess_completion,
          user: existing_owner,
          claim_id: "claim-1",
          game_id: "game-1",
          player_id: "player-1",
          mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
          ruleset_version: "party-v1",
          completed_at: Time.zone.parse("2026-08-05 11:00:00"),
          place: 1,
          winner: true
        )
      end

      it { is_expected.to eq(false) }
    end

    context "when the seat has a different claim id" do
      fab!(:existing_completion) do
        Fabricate(
          :where_is_my_friends_flying_chess_completion,
          user:,
          claim_id: "different-claim",
          game_id: "game-1",
          player_id: "player-1",
          mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
          ruleset_version: "party-v1",
          completed_at: Time.zone.parse("2026-08-05 11:00:00"),
          place: 1,
          winner: true
        )
      end

      it { is_expected.to eq(false) }
    end

    context "when the user already claimed another seat in the game" do
      fab!(:existing_completion) do
        Fabricate(
          :where_is_my_friends_flying_chess_completion,
          user:,
          claim_id: "different-claim",
          game_id: "game-1",
          player_id: "different-player",
          mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
          ruleset_version: "party-v1",
          completed_at: Time.zone.parse("2026-08-05 11:00:00"),
          place: 1,
          winner: true
        )
      end

      it { is_expected.to eq(false) }
    end
  end

  describe ".record!" do
    subject(:recorded_completion) { described_class.record!(user:, claim:) }

    fab!(:user)
    let(:completed_at) { Time.zone.parse("2026-08-05 11:00:00").to_i }
    let(:claim) do
      WhereIsMyFriends::FlyingChess::ClaimToken::Claim.new(
        claim_id: "claim-1",
        game_id: "game-1",
        player_id: "player-1",
        mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
        ruleset_version: "party-v1",
        completed_at:,
        place: 1,
        winner: true,
        issued_at: completed_at,
        expires_at: completed_at + 1.day.to_i
      )
    end

    context "without an existing completion" do
      it "creates the completion" do
        expect { recorded_completion }.to change(described_class, :count).by(1)
      end

      it { is_expected.to be_persisted }
    end

    context "with an exact existing completion" do
      fab!(:existing_completion) do
        Fabricate(
          :where_is_my_friends_flying_chess_completion,
          user:,
          claim_id: "claim-1",
          game_id: "game-1",
          player_id: "player-1",
          mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
          ruleset_version: "party-v1",
          completed_at: Time.zone.parse("2026-08-05 11:00:00"),
          place: 1,
          winner: true
        )
      end

      it "does not create a duplicate" do
        expect { recorded_completion }.not_to change(described_class, :count)
      end

      it "returns the existing completion" do
        expect(recorded_completion.id).to eq(existing_completion.id)
      end
    end

    context "with a conflicting existing claim" do
      fab!(:existing_completion) do
        Fabricate(
          :where_is_my_friends_flying_chess_completion,
          user:,
          claim_id: "claim-1",
          game_id: "game-1",
          player_id: "player-1",
          mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
          ruleset_version: "party-v1",
          completed_at: Time.zone.parse("2026-08-05 11:00:00"),
          place: 2,
          winner: false
        )
      end

      it "raises without persisting a completion", :aggregate_failures do
        expect { recorded_completion }.to raise_error(
          ActiveRecord::RecordInvalid
        ) do |error|
          expect(error.record).not_to be_persisted
          expect(error.record.errors[:claim_id]).to include(
            I18n.t("errors.messages.taken")
          )
        end
        expect(described_class.count).to eq(1)
      end
    end
  end

  describe "#matches?" do
    subject(:matches) { completion.matches?(user:, claim:) }

    fab!(:owner, :user)
    fab!(:completion) do
      Fabricate(
        :where_is_my_friends_flying_chess_completion,
        user: owner,
        claim_id: "claim-1",
        game_id: "game-1",
        player_id: "player-1",
        mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
        ruleset_version: "party-v1",
        completed_at: Time.zone.parse("2026-08-05 11:00:00"),
        place: 1,
        winner: true
      )
    end
    let(:user) { owner }
    let(:completed_at) { Time.zone.parse("2026-08-05 11:00:00").to_i }
    let(:base_claim) do
      WhereIsMyFriends::FlyingChess::ClaimToken::Claim.new(
        claim_id: "claim-1",
        game_id: "game-1",
        player_id: "player-1",
        mode: WhereIsMyFriends::FlyingChess::ClaimToken::MODE,
        ruleset_version: "party-v1",
        completed_at:,
        place: 1,
        winner: true,
        issued_at: completed_at,
        expires_at: completed_at + 1.day.to_i
      )
    end
    let(:claim) { base_claim }

    context "with the same user and every signed completion field" do
      it { is_expected.to eq(true) }
    end

    context "with another user" do
      fab!(:user, :user)

      it { is_expected.to eq(false) }
    end

    context "when any signed completion field differs" do
      it "rejects every mismatch", :aggregate_failures do
        mismatched_claims = [
          base_claim.with(claim_id: "different-claim"),
          base_claim.with(game_id: "different-game"),
          base_claim.with(player_id: "different-player"),
          base_claim.with(mode: "different-mode"),
          base_claim.with(ruleset_version: "different-ruleset"),
          base_claim.with(completed_at: completed_at - 1),
          base_claim.with(place: 2),
          base_claim.with(winner: false)
        ]

        mismatched_claims.each do |mismatched_claim|
          expect(completion.matches?(user:, claim: mismatched_claim)).to eq(
            false
          )
        end
      end
    end
  end
end

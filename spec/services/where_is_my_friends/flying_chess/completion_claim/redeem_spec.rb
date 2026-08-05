# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::FlyingChess::CompletionClaim::Redeem do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:claim_token) }

    it do
      is_expected.to validate_length_of(:claim_token).is_at_most(
        WhereIsMyFriends::FlyingChess::ClaimToken::MAXIMUM_TOKEN_BYTES
      )
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:acting_user, :user)
    fab!(:profile) do
      Fabricate(
        :where_is_my_friends_flying_chess_profile,
        user: acting_user,
        profile_visible: true
      )
    end
    let(:params) { { claim_token: } }
    let(:dependencies) { { guardian: Guardian.new(current_user) } }
    let(:current_user) { acting_user }
    let(:claim_token) { "signed-claim-token" }
    let(:secret) { "s" * 32 }
    let(:completed_at) { 1.hour.ago.change(usec: 0).to_i }
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

    before do
      SiteSetting.where_is_my_friends_enabled = true
      SiteSetting.where_is_my_friends_flying_chess_achievements_enabled = true
      SiteSetting.where_is_my_friends_flying_chess_claim_secret = secret
      allow(WhereIsMyFriends::FlyingChess::ClaimToken).to receive(:verify).with(
        claim_token,
        secret:
      ).and_return(claim)
      allow(WhereIsMyFriendsFlyingChessProfile).to receive(
        :synchronize_for
      ).with(acting_user).and_return(profile)
      allow(profile).to receive(:synchronize_first_takeoff_badge!).and_return(
        profile
      )
    end

    shared_examples "a rejected claim token" do
      it do
        expect(result).to fail_with_exception(
          WhereIsMyFriends::FlyingChess::ClaimToken::InvalidClaim
        )
      end
    end

    context "when the contract is invalid" do
      let(:claim_token) { "" }

      it { is_expected.to fail_a_contract }
    end

    context "without an authenticated user" do
      let(:current_user) { nil }

      it { is_expected.to fail_to_find_a_model(:user) }
    end

    context "when the main feature is disabled" do
      before { SiteSetting.where_is_my_friends_enabled = false }

      it { is_expected.to fail_a_policy(:claims_enabled) }
    end

    context "when achievements are disabled" do
      before do
        SiteSetting.where_is_my_friends_flying_chess_achievements_enabled =
          false
      end

      it { is_expected.to fail_a_policy(:claims_enabled) }
    end

    context "with a weak claim secret" do
      let(:secret) { "too-short" }

      it { is_expected.to fail_a_policy(:claims_enabled) }
    end

    context "with a malformed claim token" do
      let(:claim_token) { "malformed" }

      before do
        allow(WhereIsMyFriends::FlyingChess::ClaimToken).to receive(
          :verify
        ).with(claim_token, secret:).and_raise(
          WhereIsMyFriends::FlyingChess::ClaimToken::InvalidClaim
        )
      end

      include_examples "a rejected claim token"
    end

    context "with an expired claim token" do
      let(:claim_token) { "expired" }

      before do
        allow(WhereIsMyFriends::FlyingChess::ClaimToken).to receive(
          :verify
        ).with(claim_token, secret:).and_raise(
          WhereIsMyFriends::FlyingChess::ClaimToken::InvalidClaim
        )
      end

      include_examples "a rejected claim token"
    end

    context "with a tampered claim token" do
      let(:claim_token) { "tampered" }

      before do
        allow(WhereIsMyFriends::FlyingChess::ClaimToken).to receive(
          :verify
        ).with(claim_token, secret:).and_raise(
          WhereIsMyFriends::FlyingChess::ClaimToken::InvalidClaim
        )
      end

      include_examples "a rejected claim token"
    end

    context "when the claim conflicts with an existing claim" do
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

      it { is_expected.to fail_a_policy(:claim_available) }
    end

    context "when a unique constraint changes concurrently" do
      before do
        allow(WhereIsMyFriendsFlyingChessCompletion).to receive(
          :record!
        ).and_raise(ActiveRecord::RecordNotUnique)
      end

      it do
        expect(result).to fail_with_exception(ActiveRecord::RecordNotUnique)
      end
    end

    context "when the claim is valid" do
      it { is_expected.to run_successfully }

      it "records the completion" do
        expect { result }.to change {
          WhereIsMyFriendsFlyingChessCompletion.where(user: acting_user).count
        }.by(1)
      end

      it "records every signed completion attribute", :aggregate_failures do
        result
        completion =
          WhereIsMyFriendsFlyingChessCompletion.find_by!(user: acting_user)

        expect(completion.claim_id).to eq(claim.claim_id)
        expect(completion.game_id).to eq(claim.game_id)
        expect(completion.player_id).to eq(claim.player_id)
        expect(completion.mode).to eq(claim.mode)
        expect(completion.ruleset_version).to eq(claim.ruleset_version)
        expect(completion.completed_at.to_i).to eq(claim.completed_at)
        expect(completion.place).to eq(claim.place)
        expect(completion.winner?).to eq(claim.winner)
      end

      it "verifies the claim token" do
        result

        expect(WhereIsMyFriends::FlyingChess::ClaimToken).to have_received(
          :verify
        ).with(claim_token, secret:)
      end

      it "synchronizes the aggregate profile" do
        result

        expect(WhereIsMyFriendsFlyingChessProfile).to have_received(
          :synchronize_for
        ).with(acting_user)
      end

      it "synchronizes the public badge projection" do
        result

        expect(profile).to have_received(:synchronize_first_takeoff_badge!)
      end

      it "keeps an exact retry idempotent", :aggregate_failures do
        repeat_result = nil

        expect do
          result
          repeat_result = described_class.call(params:, **dependencies)
        end.to change {
          WhereIsMyFriendsFlyingChessCompletion.where(user: acting_user).count
        }.by(1)

        expect(result).to run_successfully
        expect(repeat_result).to run_successfully
      end

      context "with a hidden achievement profile" do
        before { profile.update!(profile_visible: false) }

        it "delegates the hidden badge condition to the profile" do
          result

          expect(profile).to have_received(:synchronize_first_takeoff_badge!)
        end
      end
    end
  end
end

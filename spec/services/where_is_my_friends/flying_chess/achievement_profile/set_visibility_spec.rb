# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::FlyingChess::AchievementProfile::SetVisibility do
  describe described_class::Contract, type: :model do
    it { is_expected.to allow_values(true, false).for(:profile_visible) }
    it { is_expected.not_to allow_value(nil).for(:profile_visible) }
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
    let(:params) { { profile_visible: requested_visibility } }
    let(:dependencies) { { guardian: Guardian.new(current_user) } }
    let(:current_user) { acting_user }
    let(:requested_visibility) { false }

    before do
      SiteSetting.where_is_my_friends_enabled = true
      SiteSetting.where_is_my_friends_flying_chess_achievements_enabled = true
      allow(WhereIsMyFriendsFlyingChessProfile).to receive(:find_by).with(
        user: acting_user
      ).and_return(profile)
      allow(profile).to receive(:synchronize_first_takeoff_badge!).and_return(
        profile
      )
    end

    context "when the contract is invalid" do
      let(:requested_visibility) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "without an authenticated user" do
      let(:current_user) { nil }

      it { is_expected.to fail_to_find_a_model(:user) }
    end

    context "when achievements are disabled" do
      before do
        SiteSetting.where_is_my_friends_flying_chess_achievements_enabled =
          false
      end

      it { is_expected.to fail_a_policy(:achievements_enabled) }
    end

    context "without an achievement profile" do
      before do
        allow(WhereIsMyFriendsFlyingChessProfile).to receive(:find_by).with(
          user: acting_user
        ).and_return(nil)
      end

      it { is_expected.to fail_to_find_a_model(:profile) }
    end

    context "when the profile belongs to another user" do
      fab!(:other_user, :user)
      fab!(:other_profile) do
        Fabricate(:where_is_my_friends_flying_chess_profile, user: other_user)
      end

      before do
        allow(WhereIsMyFriendsFlyingChessProfile).to receive(:find_by).with(
          user: acting_user
        ).and_return(other_profile)
      end

      it { is_expected.to fail_a_policy(:can_manage_profile) }
    end

    context "when hiding the achievement profile" do
      it { is_expected.to run_successfully }

      it "persists the hidden visibility" do
        expect { result }.to change { profile.reload.profile_visible? }.from(
          true
        ).to(false)
      end

      it "synchronizes the badge projection" do
        result

        expect(profile).to have_received(:synchronize_first_takeoff_badge!)
      end
    end

    context "when publishing the achievement profile" do
      let(:requested_visibility) { true }

      before { profile.update!(profile_visible: false) }

      it { is_expected.to run_successfully }

      it "persists the public visibility" do
        expect { result }.to change { profile.reload.profile_visible? }.from(
          false
        ).to(true)
      end

      it "synchronizes the badge projection" do
        result

        expect(profile).to have_received(:synchronize_first_takeoff_badge!)
      end
    end

    context "when badge synchronization raises" do
      before do
        allow(profile).to receive(:synchronize_first_takeoff_badge!).and_raise(
          "badge synchronization failed"
        )
      end

      it "rolls back the visibility update", :aggregate_failures do
        expect { result }.to raise_error(
          RuntimeError,
          "badge synchronization failed"
        )
        expect(profile.reload.profile_visible?).to eq(true)
      end
    end
  end
end

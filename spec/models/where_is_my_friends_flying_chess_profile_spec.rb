# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsFlyingChessProfile do
  describe ".synchronize_for" do
    subject(:synchronized_profile) { described_class.synchronize_for(user) }

    fab!(:user)
    fab!(:first_completion) do
      Fabricate(
        :where_is_my_friends_flying_chess_completion,
        user:,
        completed_at: Time.zone.parse("2026-08-03 12:00:00")
      )
    end
    fab!(:second_completion) do
      Fabricate(
        :where_is_my_friends_flying_chess_completion,
        user:,
        completed_at: Time.zone.parse("2026-08-04 12:00:00")
      )
    end
    let(:first_completed_at) { Time.zone.parse("2026-08-03 12:00:00") }

    context "without an existing profile" do
      it "creates the aggregate profile", :aggregate_failures do
        expect { synchronized_profile }.to change(described_class, :count).by(1)
        expect(synchronized_profile.completed_games).to eq(2)
        expect(synchronized_profile.first_completed_at).to eq_time(
          first_completed_at
        )
        expect(synchronized_profile).to be_profile_visible
      end
    end

    context "with an existing hidden profile" do
      fab!(:profile) do
        Fabricate(
          :where_is_my_friends_flying_chess_profile,
          user:,
          completed_games: 0,
          first_completed_at: nil,
          profile_visible: false
        )
      end

      it "updates the aggregate and preserves privacy", :aggregate_failures do
        expect { synchronized_profile }.not_to change(described_class, :count)
        expect(synchronized_profile.id).to eq(profile.id)
        expect(synchronized_profile.completed_games).to eq(2)
        expect(synchronized_profile.first_completed_at).to eq_time(
          first_completed_at
        )
        expect(synchronized_profile).not_to be_profile_visible
      end
    end
  end

  describe "#visible_to?" do
    subject(:visible) { profile.visible_to?(viewer) }

    fab!(:owner, :user)
    fab!(:viewer, :user)
    fab!(:profile) do
      Fabricate(
        :where_is_my_friends_flying_chess_profile,
        user: owner,
        profile_visible: true
      )
    end

    context "with a public profile" do
      it { is_expected.to eq(true) }
    end

    context "with a hidden profile viewed by its owner" do
      let(:viewer) { owner }

      before { profile.update!(profile_visible: false) }

      it { is_expected.to eq(true) }
    end

    context "with a hidden profile viewed by another user" do
      before { profile.update!(profile_visible: false) }

      it { is_expected.to eq(false) }
    end

    context "with a hidden profile viewed anonymously" do
      let(:viewer) { nil }

      before { profile.update!(profile_visible: false) }

      it { is_expected.to eq(false) }
    end
  end

  describe "#manageable_by?" do
    subject(:manageable) { profile.manageable_by?(viewer) }

    fab!(:owner, :user)
    fab!(:viewer, :user)
    fab!(:profile) do
      Fabricate(:where_is_my_friends_flying_chess_profile, user: owner)
    end

    context "when viewed by its owner" do
      let(:viewer) { owner }

      it { is_expected.to eq(true) }
    end

    context "when viewed by another user" do
      it { is_expected.to eq(false) }
    end

    context "when viewed anonymously" do
      let(:viewer) { nil }

      it { is_expected.to eq(false) }
    end
  end

  describe "#synchronize_first_takeoff_badge!" do
    subject(:synchronize_badge) { profile.synchronize_first_takeoff_badge! }

    fab!(:user)
    fab!(:profile) do
      Fabricate(
        :where_is_my_friends_flying_chess_profile,
        user:,
        profile_visible: true
      )
    end
    let(:badge) do
      Badge.find_by!(
        name: WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
      )
    end

    before do
      SiteSetting.enable_badges = true
      SiteSetting.where_is_my_friends_enabled = true
      SiteSetting.where_is_my_friends_flying_chess_achievements_enabled = true
    end

    context "with a public profile and no badge" do
      it "grants the badge" do
        expect { synchronize_badge }.to change {
          UserBadge.where(user:, badge:).count
        }.by(1)
      end

      it "returns the profile" do
        expect(synchronize_badge).to eq(profile)
      end

      it "is idempotent" do
        expect do
          synchronize_badge
          profile.synchronize_first_takeoff_badge!
        end.to change { UserBadge.where(user:, badge:).count }.by(1)
      end
    end

    context "with a public profile and an existing badge" do
      fab!(:user_badge) do
        Fabricate(
          :user_badge,
          user:,
          badge:
            Badge.find_by!(
              name: WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
            )
        )
      end

      it "does not grant another badge" do
        expect { synchronize_badge }.not_to change {
          UserBadge.where(user:, badge:).count
        }
      end
    end

    context "with a hidden profile and an existing badge" do
      fab!(:user_badge) do
        Fabricate(
          :user_badge,
          user:,
          badge:
            Badge.find_by!(
              name: WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
            )
        )
      end

      before { profile.update!(profile_visible: false) }

      it "revokes the badge" do
        expect { synchronize_badge }.to change {
          UserBadge.where(user:, badge:).count
        }.by(-1)
      end

      it "is idempotent" do
        expect do
          synchronize_badge
          profile.synchronize_first_takeoff_badge!
        end.to change { UserBadge.where(user:, badge:).count }.by(-1)
      end
    end

    context "with a hidden profile and no badge" do
      before { profile.update!(profile_visible: false) }

      it "does not change badge ownership" do
        expect { synchronize_badge }.not_to change {
          UserBadge.where(user:, badge:).count
        }
      end
    end

    context "with a disabled badge" do
      before { badge.update!(enabled: false) }

      it "does not grant the badge" do
        expect { synchronize_badge }.not_to change {
          UserBadge.where(user:, badge:).count
        }
      end
    end

    context "with disabled Flying Chess achievements and an existing badge" do
      fab!(:user_badge) do
        Fabricate(
          :user_badge,
          user:,
          badge:
            Badge.find_by!(
              name: WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
            )
        )
      end

      before do
        SiteSetting.where_is_my_friends_flying_chess_achievements_enabled = false
      end

      it "revokes the badge" do
        expect { synchronize_badge }.to change {
          UserBadge.where(user:, badge:).count
        }.by(-1)
      end
    end

    context "without a configured badge" do
      before do
        allow(Badge).to receive(:find_by).with(
          name: WhereIsMyFriends::FlyingChess::FIRST_TAKEOFF_BADGE_NAME
        ).and_return(nil)
      end

      it "does not grant a badge" do
        expect { synchronize_badge }.not_to change {
          UserBadge.where(user:).count
        }
      end
    end

    context "when a stale public instance was hidden concurrently" do
      before do
        described_class.where(id: profile.id).update_all(profile_visible: false)
      end

      it "uses the locked current visibility", :aggregate_failures do
        expect(profile).to be_profile_visible
        expect { synchronize_badge }.not_to change {
          UserBadge.where(user:, badge:).count
        }
        expect(profile.reload).not_to be_profile_visible
      end
    end
  end
end

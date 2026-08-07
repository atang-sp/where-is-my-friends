# frozen_string_literal: true

RSpec.describe Jobs::WhereIsMyFriendsSynchronizeFlyingChessBadges do
  subject(:job) { described_class.new }

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
    SiteSetting.enable_badges = true
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_flying_chess_achievements_enabled = false
  end

  it "revokes public badges when achievements are disabled" do
    expect { job.execute({}) }.to change {
      UserBadge.where(user:, badge:).count
    }.by(-1)
  end

  it "is enqueued when achievement availability changes" do
    allow(Jobs).to receive(:enqueue)

    DiscourseEvent.trigger(
      :site_setting_changed,
      :where_is_my_friends_flying_chess_achievements_enabled,
      true,
      false
    )

    expect(Jobs).to have_received(:enqueue).with(described_class)
  end

  it "is enqueued when the main plugin is disabled" do
    allow(Jobs).to receive(:enqueue)

    SiteSetting.where_is_my_friends_enabled = false

    expect(Jobs).to have_received(:enqueue).with(described_class)
  end
end

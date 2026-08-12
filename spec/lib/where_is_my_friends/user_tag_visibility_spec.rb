# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::UserTagVisibility do
  fab!(:viewer) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:proposer) { Fabricate(:user, trust_level: TrustLevel[1]) }

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_user_tags_enabled = true
  end

  def approved_tag(label: "热心肠", proposer:, target_user: target)
    WhereIsMyFriendsUserTag.create!(
      proposer: proposer,
      target_user: target_user,
      label: label
    ).tap(&:approve!)
  end

  it "returns approved tags ordered by endorsement count" do
    low = approved_tag(label: "低赞", proposer: proposer)
    high = approved_tag(label: "高赞", proposer: proposer)
    WhereIsMyFriendsTagEndorsement.create!(user: viewer, tag: high)
    WhereIsMyFriendsTagEndorsement.create!(user: Fabricate(:user), tag: high)

    tags = described_class.public_tags_for(target, viewer: viewer)

    expect(tags.map { |t| t[:label] }).to eq(%w[高赞 低赞])
    high_payload = tags.find { |t| t[:label] == "高赞" }
    expect(high_payload[:endorser_count]).to eq(2)
    expect(high_payload[:endorsed_by_me]).to be(true)
  end

  it "limits the displayed tags to the configured maximum" do
    SiteSetting.where_is_my_friends_user_tag_max_displayed = 2
    3.times { |i| approved_tag(label: "标签#{i}", proposer: proposer) }

    tags = described_class.public_tags_for(target, viewer: viewer)

    expect(tags.length).to eq(2)
  end

  it "never returns pending tags" do
    WhereIsMyFriendsUserTag.create!(
      proposer: proposer,
      target_user: target,
      label: "待批准"
    )

    expect(described_class.public_tags_for(target, viewer: viewer)).to eq([])
  end

  it "returns empty when the feature is disabled" do
    SiteSetting.where_is_my_friends_user_tags_enabled = false
    approved_tag(proposer: proposer)

    expect(described_class.public_tags_for(target, viewer: viewer)).to eq([])
  end

  it "returns empty when the target is not profile-visible to the viewer" do
    approved_tag(proposer: proposer)
    target.update!(suspended_till: 1.week.from_now)

    expect(described_class.public_tags_for(target, viewer: viewer)).to eq([])
  end

  it "returns empty for a muted relationship" do
    approved_tag(proposer: proposer)
    MutedUser.create!(user: viewer, muted_user: target)

    expect(described_class.public_tags_for(target, viewer: viewer)).to eq([])
  end

  it "returns empty for an ignored relationship" do
    approved_tag(proposer: proposer)
    IgnoredUser.create!(
      user: viewer,
      ignored_user: target,
      expiring_at: 2.weeks.from_now
    )

    expect(described_class.public_tags_for(target, viewer: viewer)).to eq([])
  end
end

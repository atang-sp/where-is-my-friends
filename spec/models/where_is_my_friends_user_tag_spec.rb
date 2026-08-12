# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsUserTag do
  fab!(:proposer) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:third) { Fabricate(:user, trust_level: TrustLevel[1]) }

  before do
    SiteSetting.where_is_my_friends_user_tags_enabled = true
    SiteSetting.where_is_my_friends_user_tag_max_length = 20
  end

  def build_tag(overrides = {})
    described_class.new(
      { proposer: proposer, target_user: target, label: "热心肠" }.merge(overrides)
    )
  end

  it "is valid with a clean label" do
    expect(build_tag).to be_valid
  end

  it "normalizes whitespace and strips the label" do
    tag = build_tag(label: "  热心  肠  ")
    expect(tag).to be_valid
    expect(tag.label).to eq("热心 肠")
  end

  it "rejects a blank label" do
    expect(build_tag(label: "   ")).not_to be_valid
  end

  it "rejects labels longer than the configured maximum" do
    expect(
      build_tag(label: "热" * (WhereIsMyFriendsUserTag.max_label_length + 1))
    ).not_to be_valid
  end

  it "rejects a tag on yourself" do
    expect(build_tag(target_user: proposer)).not_to be_valid
  end

  it "rejects an unknown status" do
    expect(build_tag(status: "weird")).not_to be_valid
  end

  it "is pending by default" do
    tag =
      described_class.create!(
        proposer: proposer,
        target_user: target,
        label: "靠谱"
      )
    expect(tag).to be_pending
    expect(tag.status).to eq("pending")
  end

  describe "state transitions" do
    fab!(:tag) { build_tag.tap(&:save!) }

    it "approves a pending tag and stamps the response time" do
      expect(tag.approve!).to be_truthy
      expect(tag).to be_approved
      expect(tag.responded_at).not_to be_nil
    end

    it "rejects a pending tag" do
      expect(tag.reject!).to be_truthy
      expect(tag.status).to eq("rejected")
      expect(tag.responded_at).not_to be_nil
    end

    it "refuses to approve an already approved tag" do
      tag.approve!
      expect(tag.approve!).to be_falsey
    end

    it "refuses to remove a non-approved tag" do
      expect(tag.remove!).to be_falsey
      expect(tag.status).to eq("pending")
    end

    it "removes an approved tag" do
      tag.approve!
      expect(tag.remove!).to be_truthy
      expect(tag.status).to eq("removed")
    end
  end

  describe "scopes" do
    fab!(:approved_tag) do
      described_class.create!(
        proposer: proposer,
        target_user: target,
        label: "热心肠"
      ).tap(&:approve!)
    end

    it "exposes only approved tags through approved scope" do
      described_class.create!(
        proposer: third,
        target_user: target,
        label: "还没批准"
      )
      expect(described_class.approved.pluck(:id)).to contain_exactly(
        approved_tag.id
      )
    end

    it "hides the viewer's own proposals from approved_for_visibility" do
      described_class.create!(
        proposer: proposer,
        target_user: target,
        label: "我提议的"
      ).tap(&:approve!)
      ids = described_class.approved_for_visibility(proposer.id).pluck(:id)
      expect(ids).not_to include(approved_tag.id)
    end
  end
end

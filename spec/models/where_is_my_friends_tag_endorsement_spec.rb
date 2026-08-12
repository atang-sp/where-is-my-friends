# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsTagEndorsement do
  fab!(:proposer, :user)
  fab!(:target, :user)
  fab!(:endorser, :user)

  fab!(:approved_tag) do
    WhereIsMyFriendsUserTag.create!(
      proposer: proposer,
      target_user: target,
      label: "热心肠"
    ).tap(&:approve!)
  end

  it "is valid for an approved tag by a third party" do
    endorsement = described_class.new(user: endorser, tag: approved_tag)
    expect(endorsement).to be_valid
  end

  it "rejects endorsing a non-approved tag" do
    pending_tag =
      WhereIsMyFriendsUserTag.create!(
        proposer: proposer,
        target_user: target,
        label: "还没批准"
      )
    endorsement = described_class.new(user: endorser, tag: pending_tag)
    expect(endorsement).not_to be_valid
  end

  it "rejects endorsing your own proposal" do
    endorsement = described_class.new(user: proposer, tag: approved_tag)
    expect(endorsement).not_to be_valid
  end

  it "rejects endorsing a tag about yourself" do
    endorsement = described_class.new(user: target, tag: approved_tag)
    expect(endorsement).not_to be_valid
  end
end

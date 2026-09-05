# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsPracticeInvitation do
  fab!(:sender, :user)
  fab!(:recipient, :user)
  fab!(:tag) { Fabricate(:tag) }

  def build_invitation(overrides = {})
    described_class.new(
      {
        sender: sender,
        recipient: recipient,
        tag: tag,
        interest_name: tag.name,
        safety_items: %w[ssc_consensus pure_practice safeword_mechanism]
      }.merge(overrides)
    )
  end

  it "is valid with recognized safety items" do
    invitation = build_invitation
    expect(invitation).to be_valid
    expect(invitation.safety_items).to contain_exactly(
      "ssc_consensus",
      "pure_practice",
      "safeword_mechanism"
    )
  end

  it "allows empty safety items for backward compatibility" do
    invitation = build_invitation(safety_items: [])
    expect(invitation).to be_valid
  end

  it "rejects unrecognized safety items" do
    invitation = build_invitation(safety_items: %w[unknown_item ssc_consensus])
    expect(invitation).not_to be_valid
    expect(invitation.errors[:safety_items]).to be_present
  end

  it "formats response_message with safety agreement section" do
    invitation =
      build_invitation(
        proposed_at: Time.zone.parse("2026-09-10 14:00:00"),
        note: "线上详细沟通。"
      )

    message = invitation.response_message(locale: :zh_CN)
    expect(message).to include(tag.name)
    expect(message).to include("线上详细沟通")
    expect(message).to include("双方安全与实践共识")
    expect(message).to include("SSC")
    expect(message).to include("纯粹 SP 交流")
    expect(message).to include("安全词")
  end
end

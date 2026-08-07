# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::ViewerAwareMemberSelection do
  fab!(:viewer, :user)
  fab!(:first_member, :user)
  fab!(:hidden_member, :user)
  fab!(:second_member, :user)
  fab!(:overflow_member, :user)

  let(:guardian) { instance_double(Guardian) }
  let(:selection) { described_class.new(viewer: viewer, guardian: guardian) }
  let(:scope) do
    User.where(
      id: [
        first_member.id,
        hidden_member.id,
        second_member.id,
        overflow_member.id
      ]
    ).order(:id)
  end

  before do
    allow(guardian).to receive(:can_see_profile?) do |member|
      member.id != hidden_member.id
    end
  end

  it "fills a result page with account-eligible members visible to the viewer" do
    result = selection.select(scope: scope, limit: 2, scan_limit: 4)

    expect(result.items.map(&:id)).to eq([first_member.id, second_member.id])
    expect(result.limited).to eq(false)
  end

  it "reports when its visibility scan budget ends before the scope" do
    allow(guardian).to receive(:can_see_profile?).and_return(false)

    result = selection.select(scope: scope, limit: 3, scan_limit: 3)

    expect(result.items).to be_empty
    expect(result.limited).to eq(true)
  end
end

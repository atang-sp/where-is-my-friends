# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::FunnelMetrics do
  fab!(:user)

  it "reports the event funnel through its explicit metrics interface" do
    as_of = Time.zone.parse("2026-08-03 12:00:00")
    WhereIsMyFriendsEvent.create!(
      user: user,
      event_name: "page_view",
      created_at: as_of - 1.hour
    )

    report = described_class.new(since: as_of - 30.days, as_of: as_of).call

    expect(report.fetch(:unique_page_visitors)).to eq(1)
  end
end

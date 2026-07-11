# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsEvent do
  fab!(:user)

  it "accepts only the approved privacy-safe funnel events" do
    approved = described_class.new(user: user, event_name: "page_view")
    unknown =
      described_class.new(user: user, event_name: "raw_location_captured")

    expect(approved).to be_valid
    expect(unknown).not_to be_valid
  end

  it "maps result counts into coarse buckets" do
    expect(described_class.result_bucket(0)).to eq("zero")
    expect(described_class.result_bucket(1)).to eq("one_to_four")
    expect(described_class.result_bucket(19)).to eq("five_to_nineteen")
    expect(described_class.result_bucket(20)).to eq("twenty_plus")
  end

  it "has no schema columns for location or browser details" do
    forbidden = %w[latitude longitude city region address ip user_agent query]

    expect(described_class.column_names & forbidden).to be_empty
  end

  it "aggregates conversion and seven-day return rates by unique user" do
    freeze_time(Time.zone.parse("2026-07-01 12:00:00"))
    returning_user = Fabricate(:user)
    visitor = Fabricate(:user)

    described_class.create!(user: returning_user, event_name: "page_view")
    described_class.create!(user: returning_user, event_name: "setup_started")
    described_class.create!(
      user: returning_user,
      event_name: "location_saved",
      location_mode: "city"
    )
    described_class.create!(
      user: returning_user,
      event_name: "results_viewed",
      result_bucket: "one_to_four"
    )
    described_class.create!(user: returning_user, event_name: "message_started")
    described_class.create!(user: visitor, event_name: "page_view")

    freeze_time(3.days.from_now)
    described_class.create!(user: returning_user, event_name: "page_view")

    stats = described_class.aggregate(since: 30.days.ago)

    expect(stats).to include(
      unique_page_visitors: 2,
      setup_completion_rate: 1.0,
      results_with_people_rate: 1.0,
      message_conversion_rate: 1.0,
      seven_day_return_rate: 0.5,
      result_bucket_distribution: {
        "one_to_four" => 1
      }
    )
  end
end

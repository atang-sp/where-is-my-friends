# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsEvent do
  fab!(:user)

  it "accepts only the approved privacy-safe funnel events" do
    approved_names = %w[
      page_view
      interest_prompt_viewed
      interest_onboarding_viewed
      interest_onboarding_completed
      interest_onboarding_skipped
      recommended_topic_opened
      recommended_user_opened
      recommendation_dismissed
      personalization_disabled
    ]
    unknown =
      described_class.new(user: user, event_name: "raw_location_captured")

    expect(
      approved_names.map do |event_name|
        described_class.new(user: user, event_name: event_name)
      end
    ).to all(be_valid)
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
    described_class.create!(
      user: returning_user,
      event_name: "interest_onboarding_viewed"
    )
    described_class.create!(
      user: returning_user,
      event_name: "interest_onboarding_completed"
    )
    described_class.create!(
      user: returning_user,
      event_name: "recommended_topic_opened"
    )

    freeze_time(3.days.from_now)
    described_class.create!(user: returning_user, event_name: "page_view")

    stats = described_class.aggregate(since: 30.days.ago)

    expect(stats).to include(
      unique_page_visitors: 2,
      setup_completion_rate: 1.0,
      results_with_people_rate: 1.0,
      message_conversion_rate: 1.0,
      interest_onboarding_completion_rate: 1.0,
      recommended_topic_open_rate: 1.0,
      recommended_user_open_rate: 0.0,
      seven_day_public_interaction_rate: 0.0,
      seven_day_first_reply_rate: 0.0,
      seven_day_return_rate: 0.5,
      result_bucket_distribution: {
        "one_to_four" => 1
      }
    )
  end

  it "counts only public interactions within seven days of onboarding" do
    freeze_time(Time.zone.parse("2026-07-01 12:00:00"))
    engaged = Fabricate(:user)
    private_only = Fabricate(:user)
    too_late = Fabricate(:user)
    [engaged, private_only, too_late].each do |member|
      described_class.create!(
        user: member,
        event_name: "interest_onboarding_completed"
      )
    end

    freeze_time(2.days.from_now)
    public_topic = Fabricate(:topic, user: engaged)
    Fabricate(:post, topic: public_topic, user: engaged, post_number: 1)
    Fabricate(:post, topic: public_topic, user: engaged, post_number: 2)

    private_topic =
      Fabricate(
        :private_message_topic,
        user: private_only,
        recipient: Fabricate(:user)
      )
    Fabricate(:post, topic: private_topic, user: private_only)
    restricted_category = Fabricate(:private_category, group: Fabricate(:group))
    restricted_topic =
      Fabricate(:topic, user: private_only, category: restricted_category)
    Fabricate(:post, topic: restricted_topic, user: private_only)

    freeze_time(8.days.from_now)
    late_topic = Fabricate(:topic, user: too_late)
    Fabricate(:post, topic: late_topic, user: too_late)

    stats = described_class.aggregate(since: 30.days.ago)

    expect(stats).to include(
      seven_day_public_interaction_rate: 0.3333,
      seven_day_first_reply_rate: 0.3333
    )
  end
end

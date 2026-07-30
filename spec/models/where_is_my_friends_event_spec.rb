# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsEvent do
  fab!(:user)

  it "accepts only the approved privacy-safe funnel events" do
    approved_names = %w[
      page_view
      directory_viewed
      city_previewed
      radius_confirmed
      local_topic_opened
      local_topic_interacted
      notification_opened
      interest_prompt_viewed
      interest_onboarding_viewed
      interest_onboarding_completed
      interest_onboarding_skipped
      recommended_topic_opened
      recommended_user_opened
      recommended_user_profile_opened
      recommended_user_related_topic_opened
      recommended_user_invite_started
      recommended_interest_opened
      recommendation_impression
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
    expect(described_class.rank_bucket(1)).to eq("one_to_two")
    expect(described_class.rank_bucket(3)).to eq("three_to_five")
    expect(described_class.rank_bucket(6)).to eq("six_plus")
    expect(described_class.rank_bucket(0)).to be_nil
    expect(described_class.rank_bucket("not-a-rank")).to be_nil
  end

  it "has no schema columns for location or browser details" do
    forbidden = %w[
      latitude
      longitude
      city
      region
      address
      ip
      user_agent
      query
      target_id
      topic_id
      post_id
      recommended_user_id
    ]

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
      thirty_day_return_rate: 0.5,
      effective_connection_rate: 1.0,
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

  it "measures public participation after recommendation exposure" do
    freeze_time(Time.zone.parse("2026-07-01 12:00:00"))
    engaged = Fabricate(:user)
    passive = Fabricate(:user)
    unexposed = Fabricate(:user)
    [engaged, passive].each do |member|
      described_class.create!(
        user: member,
        event_name: "recommendation_impression",
        surface: "homepage",
        candidate_source: "interest",
        rank_bucket: "one_to_two",
        algorithm_version: "participation_v1",
        result_bucket: "five_to_nineteen"
      )
    end
    described_class.create!(
      user: engaged,
      event_name: "recommended_topic_opened",
      surface: "homepage",
      candidate_source: "interest",
      rank_bucket: "one_to_two",
      algorithm_version: "participation_v1"
    )
    described_class.create!(
      user: passive,
      event_name: "recommended_topic_opened",
      surface: "homepage",
      candidate_source: "interest",
      rank_bucket: "one_to_two",
      algorithm_version: "participation_v1"
    )
    described_class.create!(
      user: engaged,
      event_name: "recommended_user_related_topic_opened",
      surface: "homepage",
      candidate_source: "interest",
      rank_bucket: "one_to_two",
      algorithm_version: "participation_v1"
    )
    described_class.create!(
      user: passive,
      event_name: "recommended_user_invite_started",
      surface: "homepage",
      candidate_source: "interest",
      rank_bucket: "one_to_two",
      algorithm_version: "participation_v1"
    )

    freeze_time(12.hours.from_now)
    engaged_topic = Fabricate(:topic, user: Fabricate(:user))
    Fabricate(:post, topic: engaged_topic, user: engaged, post_number: 2)
    unexposed_topic = Fabricate(:topic, user: Fabricate(:user))
    Fabricate(:post, topic: unexposed_topic, user: unexposed, post_number: 2)

    stats = described_class.aggregate(since: 30.days.ago)

    expect(stats).to include(
      recommendation_exposed_users: 2,
      recommendation_open_rate: 1.0,
      impression_to_24h_reply_rate: 0.5,
      topic_open_to_24h_reply_rate: 0.5,
      recommended_user_related_topic_open_rate: 0.5,
      recommended_user_invite_start_rate: 0.5,
      seven_day_public_interaction_after_impression_rate: 0.5,
      recommendation_surface_distribution: {
        "homepage" => 2
      },
      recommendation_candidate_source_distribution: {
        "interest" => 2
      },
      recommendation_rank_bucket_distribution: {
        "one_to_two" => 2
      },
      recommendation_algorithm_version_distribution: {
        "participation_v1" => 2
      }
    )
  end

  it "counts recommendation opens only after the first exposure" do
    freeze_time(Time.zone.parse("2026-07-01 12:00:00"))
    member = Fabricate(:user)
    described_class.create!(
      user: member,
      event_name: "recommended_topic_opened",
      surface: "interest_page"
    )

    freeze_time(1.hour.from_now)
    described_class.create!(
      user: member,
      event_name: "recommendation_impression",
      surface: "homepage"
    )

    expect(described_class.aggregate(since: 30.days.ago)).to include(
      recommendation_exposed_users: 1,
      recommendation_open_rate: 0.0
    )

    freeze_time(1.hour.from_now)
    described_class.create!(
      user: member,
      event_name: "recommended_user_opened",
      surface: "homepage"
    )

    expect(described_class.aggregate(since: 30.days.ago)).to include(
      recommendation_open_rate: 1.0
    )
  end

  it "counts only messages or local-topic interactions within seven days of joining" do
    freeze_time(Time.zone.parse("2026-07-01 12:00:00"))
    messager = Fabricate(:user)
    topic_participant = Fabricate(:user)
    late_user = Fabricate(:user)

    [messager, topic_participant, late_user].each do |member|
      described_class.create!(
        user: member,
        event_name: "location_saved",
        location_mode: "city"
      )
    end
    described_class.create!(
      user: messager,
      event_name: "message_started",
      created_at: 6.days.from_now
    )
    described_class.create!(
      user: topic_participant,
      event_name: "local_topic_interacted",
      created_at: 2.days.from_now
    )
    described_class.create!(
      user: late_user,
      event_name: "message_started",
      created_at: 8.days.from_now
    )

    stats = described_class.aggregate(since: 30.days.ago)

    expect(stats[:effective_connection_rate]).to eq(0.6667)
  end
end

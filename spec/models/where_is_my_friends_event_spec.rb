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
      recommendation_panel_expanded
      recommendation_panel_collapsed
      recommendation_group_selected
      recommendation_refreshed
      local_callout_viewed
      local_callout_opened
      local_callout_dismissed
      local_callout_location_saved
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

    freeze_time(5.days.from_now)
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
        recommendation_group: "topics",
        result_bucket: "five_to_nineteen"
      )
    end
    described_class.create!(
      user: engaged,
      event_name: "recommended_topic_opened",
      surface: "homepage",
      candidate_source: "interest",
      rank_bucket: "one_to_two",
      algorithm_version: "participation_v1",
      recommendation_group: "topics"
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

    freeze_time(7.days.from_now + 12.hours)
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

  context "with recommendation-group events" do
    fab!(:topic_user, :user)
    fab!(:people_user, :user)
    fab!(:interest_user, :user)

    it "reports exposure, open, and dismissal funnels for each group" do
      {
        topic_user => "topics",
        people_user => "people",
        interest_user => "interests"
      }.each do |member, group|
        described_class.create!(
          user: member,
          event_name: "recommendation_impression",
          surface: "homepage",
          recommendation_group: group
        )
      end
      described_class.create!(
        user: topic_user,
        event_name: "recommended_topic_opened",
        surface: "homepage",
        recommendation_group: "topics"
      )
      described_class.create!(
        user: people_user,
        event_name: "recommendation_dismissed",
        surface: "homepage",
        recommendation_group: "people"
      )

      expect(described_class.aggregate.fetch(:recommendation_groups)).to eq(
        "topics" => {
          exposed_users: 1,
          openers: 1,
          open_rate: 1.0,
          dismissers: 0,
          dismissal_rate: 0.0
        },
        "people" => {
          exposed_users: 1,
          openers: 0,
          open_rate: 0.0,
          dismissers: 1,
          dismissal_rate: 1.0
        },
        "interests" => {
          exposed_users: 1,
          openers: 0,
          open_rate: 0.0,
          dismissers: 0,
          dismissal_rate: 0.0
        }
      )
    end
  end

  context "with homepage Local Friends events" do
    fab!(:opener, :user)
    fab!(:saver, :user)
    fab!(:dismissing_user, :user)

    it "reports the funnel from viewed users" do
      [opener, saver, dismissing_user].each do |member|
        described_class.create!(
          user: member,
          event_name: "local_callout_viewed",
          surface: "homepage"
        )
      end
      described_class.create!(
        user: opener,
        event_name: "local_callout_opened",
        surface: "homepage"
      )
      described_class.create!(
        user: saver,
        event_name: "local_callout_location_saved",
        surface: "homepage"
      )
      described_class.create!(
        user: dismissing_user,
        event_name: "local_callout_dismissed",
        surface: "homepage"
      )

      expect(described_class.aggregate.fetch(:local_callout)).to eq(
        viewed_users: 3,
        opened_users: 1,
        open_rate: 0.3333,
        location_savers: 1,
        location_save_rate: 0.3333,
        dismissers: 1,
        dismissal_rate: 0.3333
      )
    end
  end

  it "reports recommendation panel actions and their active groups" do
    described_class.create!(
      user: user,
      event_name: "recommendation_panel_expanded",
      surface: "homepage",
      recommendation_group: "topics"
    )
    described_class.create!(
      user: user,
      event_name: "recommendation_group_selected",
      surface: "homepage",
      recommendation_group: "people"
    )
    described_class.create!(
      user: user,
      event_name: "recommendation_refreshed",
      surface: "homepage",
      recommendation_group: "people"
    )
    described_class.create!(
      user: user,
      event_name: "recommendation_panel_collapsed",
      surface: "homepage",
      recommendation_group: "people"
    )

    expect(described_class.aggregate.fetch(:recommendation_actions)).to eq(
      expanded_users: 1,
      expansions: 1,
      collapsed_users: 1,
      collapses: 1,
      group_switches: {
        "people" => 1
      },
      refreshes: {
        "people" => 1
      }
    )
  end

  context "with mature and in-progress recommendation cohorts" do
    let(:as_of) { Time.zone.parse("2026-08-10 12:00:00") }

    fab!(:mature_user, :user)
    fab!(:in_progress_user, :user)
    fab!(:legacy_user, :user)
    fab!(:mature_author, :user)
    fab!(:recent_author, :user)
    fab!(:mature_topic) do
      Fabricate(
        :topic,
        user: mature_author,
        created_at: Time.zone.parse("2026-08-03 12:00:00")
      )
    end
    fab!(:mature_reply) do
      Fabricate(
        :post,
        topic: mature_topic,
        user: mature_user,
        post_number: 2,
        created_at: Time.zone.parse("2026-08-03 12:00:00")
      )
    end
    fab!(:recent_topic) do
      Fabricate(
        :topic,
        user: recent_author,
        created_at: Time.zone.parse("2026-08-10 00:00:00")
      )
    end
    fab!(:recent_reply) do
      Fabricate(
        :post,
        topic: recent_topic,
        user: in_progress_user,
        post_number: 2,
        created_at: Time.zone.parse("2026-08-10 00:00:00")
      )
    end

    it "separates seven-day mature users from in-progress and legacy users" do
      described_class.create!(
        user: mature_user,
        event_name: "recommendation_impression",
        recommendation_group: "topics",
        created_at: as_of - 8.days
      )
      described_class.create!(
        user: legacy_user,
        event_name: "recommendation_impression",
        created_at: as_of - 8.days
      )
      described_class.create!(
        user: in_progress_user,
        event_name: "recommendation_impression",
        recommendation_group: "topics",
        created_at: as_of - 12.hours
      )

      stats = described_class.aggregate(since: as_of - 30.days, as_of: as_of)
      cohort = stats.fetch(:mature_cohorts).fetch(:recommendation_exposure)

      expect(cohort).to eq(
        mature_users: 1,
        in_progress_users: 1,
        public_interactors: 1,
        public_interaction_rate: 1.0,
        mature_24h_users: 1,
        in_progress_24h_users: 1,
        repliers_within_24h: 1,
        reply_rate_24h: 1.0
      )
      expect(stats).to include(
        impression_to_24h_reply_rate: 1.0,
        seven_day_public_interaction_after_impression_rate: 1.0
      )
    end
  end

  context "with mature and in-progress onboarding cohorts" do
    let(:as_of) { Time.zone.parse("2026-08-10 12:00:00") }

    fab!(:participating_user, :user)
    fab!(:inactive_user, :user)
    fab!(:recent_user, :user)
    fab!(:public_topic_author, :user)
    fab!(:public_topic) do
      Fabricate(
        :topic,
        user: public_topic_author,
        created_at: Time.zone.parse("2026-08-04 12:00:00")
      )
    end
    fab!(:public_reply) do
      Fabricate(
        :post,
        topic: public_topic,
        user: participating_user,
        post_number: 2,
        created_at: Time.zone.parse("2026-08-04 12:00:00")
      )
    end

    it "reports participation and plugin return only for mature users" do
      [participating_user, inactive_user].each do |member|
        described_class.create!(
          user: member,
          event_name: "interest_onboarding_completed",
          created_at: as_of - 8.days
        )
        described_class.create!(
          user: member,
          event_name: "page_view",
          created_at: as_of - 8.days
        )
      end
      described_class.create!(
        user: participating_user,
        event_name: "page_view",
        created_at: as_of - 6.days
      )
      described_class.create!(
        user: recent_user,
        event_name: "interest_onboarding_completed",
        created_at: as_of - 1.day
      )
      described_class.create!(
        user: recent_user,
        event_name: "page_view",
        created_at: as_of - 1.day
      )

      stats = described_class.aggregate(since: as_of - 30.days, as_of: as_of)
      cohorts = stats.fetch(:mature_cohorts)

      expect(cohorts.fetch(:interest_onboarding)).to eq(
        mature_users: 2,
        in_progress_users: 1,
        public_interactors: 1,
        public_interaction_rate: 0.5,
        first_repliers: 1,
        first_reply_rate: 0.5
      )
      expect(cohorts.fetch(:plugin_visits)).to eq(
        mature_users: 2,
        in_progress_users: 1,
        returning_users: 1,
        seven_day_return_rate: 0.5
      )
      expect(stats).to include(
        seven_day_public_interaction_rate: 0.5,
        seven_day_first_reply_rate: 0.5,
        seven_day_return_rate: 0.5
      )
    end
  end

  context "when a user's first acquisition predates the report window" do
    let(:as_of) { Time.zone.parse("2026-08-10 12:00:00") }

    fab!(:previously_exposed_user, :user)
    fab!(:previously_onboarded_user, :user)
    fab!(:previous_plugin_visitor, :user)

    it "does not reset repeated events into new cohorts" do
      [as_of - 40.days, as_of - 8.days].each do |created_at|
        described_class.create!(
          user: previously_exposed_user,
          event_name: "recommendation_impression",
          recommendation_group: "topics",
          created_at: created_at
        )
        described_class.create!(
          user: previously_onboarded_user,
          event_name: "interest_onboarding_completed",
          created_at: created_at
        )
        described_class.create!(
          user: previous_plugin_visitor,
          event_name: "page_view",
          created_at: created_at
        )
      end

      cohorts =
        described_class.aggregate(since: as_of - 30.days, as_of: as_of).fetch(
          :mature_cohorts
        )

      expect(cohorts.fetch(:recommendation_exposure)).to include(
        mature_users: 0,
        in_progress_users: 0
      )
      expect(cohorts.fetch(:interest_onboarding)).to include(
        mature_users: 0,
        in_progress_users: 0
      )
      expect(cohorts.fetch(:plugin_visits)).to include(
        mature_users: 0,
        in_progress_users: 0
      )
    end
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

    stats =
      described_class.aggregate(since: 30.days.ago, as_of: 8.days.from_now)

    expect(stats[:effective_connection_rate]).to eq(0.6667)
  end
end

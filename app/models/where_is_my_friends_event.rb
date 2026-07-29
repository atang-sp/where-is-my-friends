# frozen_string_literal: true

class WhereIsMyFriendsEvent < ActiveRecord::Base
  EVENT_NAMES = %w[
    page_view
    setup_started
    location_saved
    results_viewed
    profile_clicked
    message_started
    local_topics_clicked
    location_removed
    interest_prompt_viewed
    interest_onboarding_viewed
    interest_onboarding_completed
    interest_onboarding_skipped
    recommended_topic_opened
    recommended_user_opened
    recommended_interest_opened
    recommendation_impression
    recommendation_dismissed
    personalization_disabled
  ].freeze
  LOCATION_MODES = %w[city gps map].freeze
  RESULT_BUCKETS = %w[zero one_to_four five_to_nineteen twenty_plus].freeze
  SURFACES = %w[homepage interest_page topic_footer].freeze
  CANDIDATE_SOURCES = %w[
    interest
    behavior
    city
    relationship_bridge
    exploration
  ].freeze
  RANK_BUCKETS = %w[one_to_two three_to_five six_plus].freeze
  ALGORITHM_VERSIONS = %w[participation_v1].freeze

  belongs_to :user

  validates :event_name, inclusion: { in: EVENT_NAMES }
  validates :location_mode, inclusion: { in: LOCATION_MODES }, allow_nil: true
  validates :result_bucket, inclusion: { in: RESULT_BUCKETS }, allow_nil: true
  validates :surface, inclusion: { in: SURFACES }, allow_nil: true
  validates :candidate_source,
            inclusion: {
              in: CANDIDATE_SOURCES
            },
            allow_nil: true
  validates :rank_bucket, inclusion: { in: RANK_BUCKETS }, allow_nil: true
  validates :algorithm_version,
            inclusion: {
              in: ALGORITHM_VERSIONS
            },
            allow_nil: true

  def self.result_bucket(count)
    value = count.to_i
    return "zero" if value.zero?
    return "one_to_four" if value < 5
    return "five_to_nineteen" if value < 20

    "twenty_plus"
  end

  def self.rank_bucket(rank)
    value = Integer(rank, exception: false)
    return if value.nil? || value < 1

    return "one_to_two" if value <= 2
    return "three_to_five" if value <= 5

    "six_plus"
  end

  def self.aggregate(since: 30.days.ago)
    events =
      where(created_at: since..).select(
        :user_id,
        :event_name,
        :result_bucket,
        :surface,
        :candidate_source,
        :rank_bucket,
        :algorithm_version,
        :created_at
      ).to_a
    viewers = users_for(events, "page_view")
    setup_starters = users_for(events, "setup_started")
    completed_setups = users_for(events, "location_saved")
    results_with_people =
      events
        .select do |event|
          event.event_name == "results_viewed" && event.result_bucket != "zero"
        end
        .map(&:user_id)
        .uniq
    messages = users_for(events, "message_started")
    profiles = users_for(events, "profile_clicked")
    local_topics = users_for(events, "local_topics_clicked")
    interest_onboarding_viewers =
      users_for(events, "interest_onboarding_viewed")
    interest_onboarding_completers =
      users_for(events, "interest_onboarding_completed")
    recommended_topic_openers = users_for(events, "recommended_topic_opened")
    recommended_user_openers = users_for(events, "recommended_user_opened")
    recommended_interest_openers =
      users_for(events, "recommended_interest_opened")
    impression_events =
      events.select { |event| event.event_name == "recommendation_impression" }
    recommendation_exposed_users = impression_events.map(&:user_id).uniq
    recommendation_openers =
      users_with_events_after_anchor(
        events,
        anchor_event_name: "recommendation_impression",
        event_names: %w[
          recommended_topic_opened
          recommended_user_opened
          recommended_interest_opened
        ]
      )
    public_interactors =
      public_interaction_users(
        events,
        anchor_event_name: "interest_onboarding_completed",
        replies_only: false,
        window: 7.days
      )
    first_repliers =
      public_interaction_users(
        events,
        anchor_event_name: "interest_onboarding_completed",
        replies_only: true,
        window: 7.days
      )
    exposed_public_interactors =
      public_interaction_users(
        events,
        anchor_event_name: "recommendation_impression",
        replies_only: false,
        window: 7.days
      )
    exposed_24h_repliers =
      public_interaction_users(
        events,
        anchor_event_name: "recommendation_impression",
        replies_only: true,
        window: 24.hours
      )

    {
      unique_page_visitors: viewers.length,
      setup_completion_rate:
        rate(completed_setups.length, setup_starters.length),
      results_with_people_rate:
        rate(results_with_people.length, completed_setups.length),
      profile_conversion_rate:
        rate(profiles.length, results_with_people.length),
      message_conversion_rate:
        rate(messages.length, results_with_people.length),
      local_topics_conversion_rate:
        rate(local_topics.length, results_with_people.length),
      interest_onboarding_completion_rate:
        rate(
          interest_onboarding_completers.length,
          interest_onboarding_viewers.length
        ),
      recommended_topic_open_rate:
        rate(
          recommended_topic_openers.length,
          interest_onboarding_completers.length
        ),
      recommended_user_open_rate:
        rate(
          recommended_user_openers.length,
          interest_onboarding_completers.length
        ),
      recommendation_exposed_users: recommendation_exposed_users.length,
      recommendation_open_rate:
        rate(
          recommendation_openers.length,
          recommendation_exposed_users.length
        ),
      impression_to_24h_reply_rate:
        rate(exposed_24h_repliers.length, recommendation_exposed_users.length),
      seven_day_public_interaction_after_impression_rate:
        rate(
          exposed_public_interactors.length,
          recommendation_exposed_users.length
        ),
      seven_day_public_interaction_rate:
        rate(public_interactors.length, interest_onboarding_completers.length),
      seven_day_first_reply_rate:
        rate(first_repliers.length, interest_onboarding_completers.length),
      seven_day_return_rate:
        rate(returning_viewers(events).length, viewers.length),
      result_bucket_distribution:
        events
          .select { |event| event.event_name == "results_viewed" }
          .filter_map(&:result_bucket)
          .tally,
      recommendation_surface_distribution:
        impression_events.filter_map(&:surface).tally,
      recommendation_candidate_source_distribution:
        impression_events.filter_map(&:candidate_source).tally,
      recommendation_rank_bucket_distribution:
        impression_events.filter_map(&:rank_bucket).tally,
      recommendation_algorithm_version_distribution:
        impression_events.filter_map(&:algorithm_version).tally,
      recommendation_result_bucket_distribution:
        impression_events.filter_map(&:result_bucket).tally
    }
  end

  def self.users_for(events, event_name)
    events.select { |event| event.event_name == event_name }.map(&:user_id).uniq
  end
  private_class_method :users_for

  def self.returning_viewers(events)
    events
      .select { |event| event.event_name == "page_view" }
      .group_by(&:user_id)
      .filter_map do |user_id, page_views|
        days = page_views.map { |event| event.created_at.to_date }.uniq.sort
        if days
             .combination(2)
             .any? { |first, second| (second - first).between?(1, 7) }
          user_id
        end
      end
  end
  private_class_method :returning_viewers

  def self.public_interaction_users(
    events,
    anchor_event_name:,
    replies_only:,
    window:
  )
    anchored_at_by_user =
      events
        .select { |event| event.event_name == anchor_event_name }
        .group_by(&:user_id)
        .transform_values { |anchors| anchors.map(&:created_at).min }
    return [] if anchored_at_by_user.empty?

    earliest = anchored_at_by_user.values.min
    latest = anchored_at_by_user.values.max + window
    posts =
      Post
        .joins(:topic)
        .joins(
          "LEFT OUTER JOIN categories ON categories.id = topics.category_id"
        )
        .where(user_id: anchored_at_by_user.keys)
        .where(created_at: earliest..latest)
        .where(post_type: Post.types[:regular], hidden: false, deleted_at: nil)
        .where(topics: { visible: true, deleted_at: nil })
        .where.not(topics: { archetype: Archetype.private_message })
        .where("categories.id IS NULL OR categories.read_restricted = FALSE")
    posts = posts.where("posts.post_number > 1") if replies_only

    posts
      .pluck(:user_id, :created_at)
      .filter_map do |user_id, created_at|
        anchored_at = anchored_at_by_user.fetch(user_id)
        user_id if created_at.between?(anchored_at, anchored_at + window)
      end
      .uniq
  end
  private_class_method :public_interaction_users

  def self.users_with_events_after_anchor(
    events,
    anchor_event_name:,
    event_names:
  )
    anchored_at_by_user =
      events
        .select { |event| event.event_name == anchor_event_name }
        .group_by(&:user_id)
        .transform_values { |anchors| anchors.map(&:created_at).min }

    events
      .filter_map do |event|
        next if event_names.exclude?(event.event_name)

        anchored_at = anchored_at_by_user[event.user_id]
        event.user_id if anchored_at && event.created_at >= anchored_at
      end
      .uniq
  end
  private_class_method :users_with_events_after_anchor

  def self.rate(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator.to_f / denominator).round(4)
  end
  private_class_method :rate
end

# frozen_string_literal: true

class WhereIsMyFriendsEvent < ActiveRecord::Base
  EVENT_NAMES = %w[
    page_view
    directory_viewed
    setup_started
    city_previewed
    radius_confirmed
    location_saved
    results_viewed
    profile_clicked
    message_started
    local_topics_clicked
    local_topic_opened
    local_topic_interacted
    notification_opened
    location_removed
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
    dynamics_profile_viewed
    recent_dynamics_viewed
    dynamic_opened
    recommended_user_dynamic_opened
  ].freeze
  LOCATION_MODES = %w[city gps map].freeze
  RESULT_BUCKETS = %w[zero one_to_four five_to_nineteen twenty_plus].freeze
  SURFACES = %w[homepage category interest_page topic_footer profile].freeze
  RECOMMENDATION_GROUPS = %w[topics people interests dynamics].freeze
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
  validates :recommendation_group,
            inclusion: {
              in: RECOMMENDATION_GROUPS
            },
            allow_nil: true
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

  def self.aggregate(since: 30.days.ago, as_of: Time.current)
    WhereIsMyFriends::FunnelMetrics.new(since: since, as_of: as_of).call
  end
end

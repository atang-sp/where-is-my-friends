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
  ].freeze
  LOCATION_MODES = %w[city gps map].freeze
  RESULT_BUCKETS = %w[zero one_to_four five_to_nineteen twenty_plus].freeze

  belongs_to :user

  validates :event_name, inclusion: { in: EVENT_NAMES }
  validates :location_mode, inclusion: { in: LOCATION_MODES }, allow_nil: true
  validates :result_bucket, inclusion: { in: RESULT_BUCKETS }, allow_nil: true

  def self.result_bucket(count)
    value = count.to_i
    return "zero" if value.zero?
    return "one_to_four" if value < 5
    return "five_to_nineteen" if value < 20

    "twenty_plus"
  end

  def self.aggregate(since: 30.days.ago)
    events =
      where(created_at: since..).select(
        :user_id,
        :event_name,
        :result_bucket,
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
      seven_day_return_rate:
        rate(returning_viewers(events).length, viewers.length)
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

  def self.rate(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator.to_f / denominator).round(4)
  end
  private_class_method :rate
end

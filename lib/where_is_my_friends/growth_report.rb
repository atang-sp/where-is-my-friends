# frozen_string_literal: true

module WhereIsMyFriends
  class GrowthReport
    RESPONSE_WINDOW = 7.days

    def initialize(since:, as_of: Time.current)
      @since = since
      @as_of = as_of
    end

    def call
      {
        period: {
          starts_at: @since.iso8601,
          ends_at: @as_of.iso8601
        },
        funnel: FunnelMetrics.new(since: @since, as_of: @as_of).call,
        dynamics: DynamicMetrics.new(since: @since, as_of: @as_of).call,
        content_supply: content_supply,
        daily: daily_trend
      }
    end

    private

    def content_supply
      topics = public_topics
      topic_ids = topics.pluck(:id)
      responses = human_responses(topic_ids)
      mature_topics = topics.where("topics.created_at <= ?", mature_cutoff)
      mature_topic_ids = mature_topics.pluck(:id)
      mature_responses = responses.where(topic_id: mature_topic_ids)

      {
        public_topics_created: topics.count,
        human_topics_created:
          topics.where.not(user_id: Discourse.system_user.id).count,
        imported_topics_created:
          WhereIsMyFriendsLicensedImport
            .published
            .where(topic_id: topic_ids)
            .distinct
            .count(:topic_id),
        unique_human_topic_authors:
          topics
            .where.not(user_id: Discourse.system_user.id)
            .distinct
            .count(:user_id),
        unique_human_repliers: responses.distinct.count(:user_id),
        mature_topics: mature_topics.count,
        in_progress_topics:
          topics.where("topics.created_at > ?", mature_cutoff).count,
        mature_topics_with_human_response:
          mature_responses.distinct.count(:topic_id),
        seven_day_human_response_rate:
          rate(mature_responses.distinct.count(:topic_id), mature_topics.count)
      }
    end

    def public_topics
      Topic
        .joins(
          "LEFT OUTER JOIN categories ON categories.id = topics.category_id"
        )
        .where(created_at: @since..@as_of)
        .where(archetype: Archetype.default, visible: true, deleted_at: nil)
        .where("categories.id IS NULL OR categories.read_restricted = FALSE")
    end

    def daily_trend
      events =
        WhereIsMyFriendsEvent
          .where(created_at: @since..@as_of)
          .select(:user_id, :event_name, :created_at)
          .to_a
      events_by_date = events.group_by { |event| local_date(event.created_at) }
      topics = public_topics.select(:id, :created_at).to_a
      topics_by_date = topics.group_by { |topic| local_date(topic.created_at) }
      responses_by_date =
        daily_human_responses
          .pluck(:topic_id, :created_at)
          .group_by { |_topic_id, created_at| local_date(created_at) }

      (@since.to_date..@as_of.to_date).map do |date|
        day_events = events_by_date.fetch(date, [])
        {
          date: date.iso8601,
          recommendation_panel_expanded_users:
            unique_users(day_events, %w[recommendation_panel_expanded]),
          recommendation_exposed_users:
            unique_users(day_events, %w[recommendation_impression]),
          recommendation_openers:
            unique_users(
              day_events,
              %w[
                recommended_topic_opened
                recommended_user_opened
                recommended_user_profile_opened
                recommended_user_related_topic_opened
                recommended_user_invite_started
                recommended_user_dynamic_opened
                recommended_interest_opened
              ]
            ),
          local_callout_viewers:
            unique_users(day_events, %w[local_callout_viewed]),
          local_callout_openers:
            unique_users(day_events, %w[local_callout_opened]),
          local_callout_location_savers:
            unique_users(day_events, %w[local_callout_location_saved]),
          public_topics_created: topics_by_date.fetch(date, []).length,
          topics_receiving_human_response:
            responses_by_date.fetch(date, []).map(&:first).uniq.length
        }
      end
    end

    def unique_users(events, event_names)
      events
        .select { |event| event_names.include?(event.event_name) }
        .map(&:user_id)
        .uniq
        .length
    end

    def local_date(timestamp)
      timestamp.in_time_zone.to_date
    end

    def human_responses(topic_ids)
      Post
        .joins(:topic)
        .where(topic_id: topic_ids)
        .where(post_type: Post.types[:regular], hidden: false, deleted_at: nil)
        .where("posts.post_number > 1")
        .where.not(user_id: Discourse.system_user.id)
        .where("posts.user_id <> topics.user_id")
        .where(
          "posts.created_at BETWEEN topics.created_at " \
            "AND topics.created_at + INTERVAL '7 days'"
        )
        .where("posts.created_at <= ?", @as_of)
    end

    def daily_human_responses
      Post
        .joins(:topic)
        .joins(
          "LEFT OUTER JOIN categories ON categories.id = topics.category_id"
        )
        .where(created_at: @since..@as_of)
        .where(post_type: Post.types[:regular], hidden: false, deleted_at: nil)
        .where("posts.post_number > 1")
        .where.not(user_id: Discourse.system_user.id)
        .where("posts.user_id <> topics.user_id")
        .where(
          topics: {
            archetype: Archetype.default,
            visible: true,
            deleted_at: nil
          }
        )
        .where("categories.id IS NULL OR categories.read_restricted = FALSE")
    end

    def mature_cutoff
      @as_of - RESPONSE_WINDOW
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.zero?

      (numerator.to_f / denominator).round(4)
    end
  end
end

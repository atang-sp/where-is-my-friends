# frozen_string_literal: true

module WhereIsMyFriends
  class DynamicMetrics
    RESPONSE_WINDOW = 7.days
    REPEAT_WINDOW = 14.days
    MEMBER_CARD_OPEN_EVENTS = %w[
      recommended_user_opened
      recommended_user_profile_opened
      recommended_user_related_topic_opened
      recommended_user_invite_started
      recommended_user_dynamic_opened
    ].freeze

    def initialize(since:, as_of: Time.current)
      @since = since
      @as_of = as_of
    end

    def call
      topics = dynamic_topics.where(created_at: @since..@as_of)
      non_staff_topics = exclude_staff_authors(topics)
      replies = qualifying_replies(non_staff_topics.select(:id))
      participant_replies =
        participating_replies(exclude_staff_authors(dynamic_topics).select(:id))
      mature_topics =
        non_staff_topics.where(
          "topics.created_at <= ?",
          @as_of - RESPONSE_WINDOW
        )
      mature_replies = replies.where(topic_id: mature_topics.select(:id))

      {
        supply: supply_metrics(non_staff_topics),
        replies: reply_metrics(mature_topics, mature_replies, non_staff_topics),
        homepage: homepage_funnel,
        member_cards: member_card_funnels,
        seven_day_return: return_metrics(non_staff_topics, participant_replies)
      }
    end

    private

    def supply_metrics(topics)
      first_topics =
        exclude_staff_authors(dynamic_topics)
          .where("topics.created_at <= ?", @as_of)
          .group(:user_id)
          .minimum(:created_at)
      mature_authors =
        first_topics.select do |_user_id, created_at|
          created_at.between?(@since, @as_of - REPEAT_WINDOW)
        end
      later_topics =
        exclude_staff_authors(dynamic_topics)
          .where(user_id: mature_authors.keys)
          .where("topics.created_at <= ?", @as_of)
          .pluck(:user_id, :created_at)
      repeat_authors =
        later_topics
          .group_by(&:first)
          .count do |user_id, entries|
            first_date = local_date(mature_authors.fetch(user_id))
            entries.any? do |_id, created_at|
              local_date(created_at) > first_date
            end
          end

      {
        dynamics_created: topics.count,
        unique_non_staff_authors: topics.distinct.count(:user_id),
        daily_authors:
          topics
            .pluck(:user_id, :created_at)
            .group_by { |_user_id, created_at| local_date(created_at) }
            .sort_by(&:first)
            .map do |date, entries|
              { date: date.iso8601, authors: entries.map(&:first).uniq.length }
            end,
        mature_authors: mature_authors.length,
        repeat_authors: repeat_authors,
        repeat_author_rate: rate(repeat_authors, mature_authors.length)
      }
    end

    def reply_metrics(mature_topics, mature_replies, all_topics)
      first_reply_times =
        mature_replies
          .group(:topic_id)
          .minimum(:created_at)
          .then do |timestamps|
            created_at_by_topic =
              mature_topics
                .where(id: timestamps.keys)
                .pluck(:id, :created_at)
                .to_h
            timestamps.map do |topic_id, replied_at|
              replied_at - created_at_by_topic.fetch(topic_id)
            end
          end
      replied_topics = mature_replies.distinct.count(:topic_id)
      mature_count = mature_topics.count

      {
        mature_dynamics: mature_count,
        in_progress_dynamics:
          all_topics.where(
            "topics.created_at > ?",
            @as_of - RESPONSE_WINDOW
          ).count,
        dynamics_with_non_author_reply: replied_topics,
        seven_day_reply_rate: rate(replied_topics, mature_count),
        unanswered_mature_dynamics: mature_count - replied_topics,
        median_first_reply_seconds: median(first_reply_times),
        unique_repliers: mature_replies.distinct.count(:user_id)
      }
    end

    def homepage_funnel
      events =
        WhereIsMyFriendsEvent
          .where(created_at: @since..@as_of, surface: "homepage")
          .where(event_name: %w[recent_dynamics_viewed dynamic_opened])
          .select(:user_id, :event_name, :created_at)
          .to_a
      viewers = users_for(events, "recent_dynamics_viewed")
      openers =
        users_after_anchor(events, "recent_dynamics_viewed", %w[dynamic_opened])

      {
        viewed_users: viewers.length,
        opened_users: openers.length,
        open_rate: rate(openers.length, viewers.length)
      }
    end

    def member_card_funnels
      events =
        WhereIsMyFriendsEvent
          .where(created_at: @since..@as_of, recommendation_group: "people")
          .where(
            event_name: ["recommendation_impression", *MEMBER_CARD_OPEN_EVENTS]
          )
          .select(:user_id, :event_name, :has_dynamic_preview, :created_at)
          .to_a

      [true, false].index_with do |preview|
          cohort =
            events.select { |event| event.has_dynamic_preview == preview }
          exposed = users_for(cohort, "recommendation_impression")
          card_openers =
            users_after_anchor(
              cohort,
              "recommendation_impression",
              MEMBER_CARD_OPEN_EVENTS
            )
          dynamic_openers =
            users_after_anchor(
              cohort,
              "recommendation_impression",
              %w[recommended_user_dynamic_opened]
            )

          {
            exposed_users: exposed.length,
            card_openers: card_openers.length,
            composite_open_rate: rate(card_openers.length, exposed.length),
            dynamic_openers: dynamic_openers.length,
            dynamic_open_rate: rate(dynamic_openers.length, exposed.length)
          }
        end
        .transform_keys do |preview|
          preview ? :with_dynamic_preview : :without_dynamic_preview
        end
    end

    def return_metrics(topics, replies)
      publisher_anchors = topics.group(:user_id).minimum(:created_at)
      replier_anchors = replies.group(:user_id).minimum(:created_at)
      opener_anchors =
        WhereIsMyFriendsEvent
          .where(
            created_at: @since..@as_of,
            event_name: %w[dynamic_opened recommended_user_dynamic_opened]
          )
          .group(:user_id)
          .minimum(:created_at)

      seven_day_returns(
        publishers: publisher_anchors,
        repliers: replier_anchors,
        openers: opener_anchors,
        regular_public_content_participants: regular_public_participant_anchors
      )
    end

    def regular_public_participant_anchors
      dynamic_topic_ids =
        TopicCustomField.where(name: DynamicFeed::FIELD).select(:topic_id)
      Post
        .joins(:topic, :user)
        .joins(
          "LEFT OUTER JOIN categories ON categories.id = topics.category_id"
        )
        .where(created_at: @since..@as_of)
        .where(post_type: Post.types[:regular], hidden: false, deleted_at: nil)
        .where(topics: { visible: true, deleted_at: nil })
        .where.not(topics: { archetype: Archetype.private_message })
        .where.not(topic_id: dynamic_topic_ids)
        .where("categories.id IS NULL OR categories.read_restricted = FALSE")
        .where(users: { admin: false, moderator: false })
        .group("posts.user_id")
        .minimum("posts.created_at")
    end

    def seven_day_returns(anchor_groups)
      partitions =
        anchor_groups.transform_values do |anchors|
          mature, in_progress =
            anchors
              .partition do |_user_id, anchored_at|
                anchored_at <= @as_of - RESPONSE_WINDOW
              end
              .map(&:to_h)
          { mature: mature, in_progress: in_progress }
        end
      mature_anchors =
        partitions.values.flat_map { |value| value[:mature].to_a }
      visits_by_user =
        if mature_anchors.empty?
          {}
        else
          first_date = mature_anchors.map { |_id, at| local_date(at) + 1 }.min
          last_date = mature_anchors.map { |_id, at| local_date(at) + 7 }.max
          UserVisit
            .where(
              user_id: mature_anchors.map(&:first).uniq,
              visited_at: first_date..last_date
            )
            .pluck(:user_id, :visited_at)
            .group_by(&:first)
        end

      partitions.transform_values do |partition|
        mature = partition[:mature]
        returning =
          mature.count do |user_id, anchored_at|
            range = (local_date(anchored_at) + 1)..(local_date(anchored_at) + 7)
            visits_by_user
              .fetch(user_id, [])
              .any? { |_id, visited_at| range.cover?(visited_at) }
          end
        {
          mature_users: mature.length,
          in_progress_users: partition[:in_progress].length,
          returning_users: returning,
          return_rate: rate(returning, mature.length)
        }
      end
    end

    def dynamic_topics
      Topic
        .joins(:user)
        .joins(
          "INNER JOIN topic_custom_fields AS metric_dynamic_fields " \
            "ON metric_dynamic_fields.topic_id = topics.id " \
            "AND metric_dynamic_fields.name = " \
            "#{Topic.connection.quote(DynamicFeed::FIELD)}"
        )
        .joins(
          "INNER JOIN posts AS metric_dynamic_first_posts " \
            "ON metric_dynamic_first_posts.topic_id = topics.id " \
            "AND metric_dynamic_first_posts.post_number = 1"
        )
        .where(archetype: Archetype.default, visible: true, deleted_at: nil)
        .where(
          "metric_dynamic_first_posts.deleted_at IS NULL " \
            "AND metric_dynamic_first_posts.hidden = FALSE " \
            "AND metric_dynamic_first_posts.post_type = ?",
          Post.types[:regular]
        )
    end

    def exclude_staff_authors(scope)
      scope.where(users: { admin: false, moderator: false })
    end

    def qualifying_replies(topic_ids)
      Post
        .joins(:user, :topic)
        .where(topic_id: topic_ids)
        .where(post_type: Post.types[:regular], hidden: false, deleted_at: nil)
        .where("posts.post_number > 1")
        .where("users.id > 0")
        .where("posts.user_id <> topics.user_id")
        .where(
          "posts.created_at BETWEEN topics.created_at " \
            "AND topics.created_at + INTERVAL '7 days'"
        )
        .where("posts.created_at <= ?", @as_of)
    end

    def participating_replies(topic_ids)
      Post
        .joins(:user, :topic)
        .where(topic_id: topic_ids, created_at: @since..@as_of)
        .where(post_type: Post.types[:regular], hidden: false, deleted_at: nil)
        .where("posts.post_number > 1")
        .where("users.id > 0")
        .where("posts.user_id <> topics.user_id")
    end

    def users_for(events, event_name)
      events
        .select { |event| event.event_name == event_name }
        .map(&:user_id)
        .uniq
    end

    def users_after_anchor(events, anchor_event_name, event_names)
      anchors =
        events
          .select { |event| event.event_name == anchor_event_name }
          .group_by(&:user_id)
          .transform_values { |items| items.map(&:created_at).min }
      events
        .filter_map do |event|
          anchored_at = anchors[event.user_id]
          if anchored_at && event_names.include?(event.event_name) &&
               event.created_at >= anchored_at
            event.user_id
          end
        end
        .uniq
    end

    def median(values)
      return if values.empty?

      ordered = values.sort
      middle = ordered.length / 2
      value =
        if ordered.length.odd?
          ordered[middle]
        else
          (ordered[middle - 1] + ordered[middle]) / 2.0
        end
      value.round
    end

    def local_date(timestamp)
      timestamp.in_time_zone.to_date
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.zero?

      (numerator.to_f / denominator).round(4)
    end
  end
end

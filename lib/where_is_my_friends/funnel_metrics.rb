# frozen_string_literal: true

module WhereIsMyFriends
  class FunnelMetrics
    RECOMMENDATION_GROUPS = WhereIsMyFriendsEvent::RECOMMENDATION_GROUPS

    def initialize(since:, as_of: Time.current, event_model: WhereIsMyFriendsEvent)
      @since = since
      @as_of = as_of
      @event_model = event_model
    end

    def call
      since = @since
      as_of = @as_of
      events =
        @event_model.where(created_at: since..as_of).select(
          :user_id,
          :event_name,
          :result_bucket,
          :surface,
          :recommendation_group,
          :candidate_source,
          :rank_bucket,
          :algorithm_version,
          :created_at
        ).to_a
      viewers = users_for(events, "page_view")
      setup_starters = users_for(events, "setup_started")
      completed_setups = users_for(events, "location_saved")
      setup_completers =
        users_with_events_after_anchor(
          events,
          anchor_event_name: "setup_started",
          event_names: %w[location_saved]
        )
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
      local_topic_openers = users_for(events, "local_topic_opened")
      local_topic_participants = users_for(events, "local_topic_interacted")
      interest_onboarding_viewers =
        users_for(events, "interest_onboarding_viewed")
      interest_onboarding_completers =
        users_for(events, "interest_onboarding_completed")
      recommended_topic_openers = users_for(events, "recommended_topic_opened")
      recommended_user_openers =
        users_for_any(
          events,
          %w[
            recommended_user_opened
            recommended_user_profile_opened
            recommended_user_related_topic_opened
            recommended_user_invite_started
          ]
        )
      recommended_user_related_topic_openers =
        users_for(events, "recommended_user_related_topic_opened")
      recommended_user_invite_starters =
        users_for(events, "recommended_user_invite_started")
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
            recommended_user_profile_opened
            recommended_user_related_topic_opened
            recommended_user_invite_started
            recommended_interest_opened
          ]
        )
      topic_open_24h_repliers =
        public_interaction_users(
          events,
          anchor_event_name: "recommended_topic_opened",
          replies_only: true,
          window: 24.hours,
          as_of: as_of
        )
      mature_cohorts = mature_cohort_metrics(events, since: since, as_of: as_of)
      mature_recommendation = mature_cohorts.fetch(:recommendation_exposure)
      mature_onboarding = mature_cohorts.fetch(:interest_onboarding)
      mature_plugin_visits = mature_cohorts.fetch(:plugin_visits)

      {
        unique_page_visitors: viewers.length,
        setup_completion_rate:
          rate(setup_completers.length, setup_starters.length),
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
        recommendation_groups: recommendation_group_funnels(events),
        recommendation_actions: recommendation_action_funnel(events),
        local_callout: local_callout_funnel(events),
        mature_cohorts: mature_cohorts,
        impression_to_24h_reply_rate:
          mature_recommendation.fetch(:reply_rate_24h),
        topic_open_to_24h_reply_rate:
          rate(topic_open_24h_repliers.length, recommended_topic_openers.length),
        recommended_user_related_topic_open_rate:
          rate(
            recommended_user_related_topic_openers.length,
            recommendation_exposed_users.length
          ),
        recommended_user_invite_start_rate:
          rate(
            recommended_user_invite_starters.length,
            recommendation_exposed_users.length
          ),
        seven_day_public_interaction_after_impression_rate:
          mature_recommendation.fetch(:public_interaction_rate),
        seven_day_public_interaction_rate:
          mature_onboarding.fetch(:public_interaction_rate),
        seven_day_first_reply_rate: mature_onboarding.fetch(:first_reply_rate),
        seven_day_return_rate: mature_plugin_visits.fetch(:seven_day_return_rate),
        thirty_day_return_rate:
          rate(returning_viewers(events, within_days: 30).length, viewers.length),
        effective_connection_rate:
          rate(effective_connections(events).length, completed_setups.length),
        local_topic_open_rate:
          rate(local_topic_openers.length, completed_setups.length),
        local_topic_interaction_rate:
          rate(local_topic_participants.length, completed_setups.length),
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

    private

    def users_for(events, event_name)
      events.select { |event| event.event_name == event_name }.map(&:user_id).uniq
    end

    def users_for_any(events, event_names)
      events
        .select { |event| event_names.include?(event.event_name) }
        .map(&:user_id)
        .uniq
    end

    def recommendation_group_funnels(events)
      open_events_by_group = {
        "topics" => %w[recommended_topic_opened],
        "people" => %w[
          recommended_user_opened
          recommended_user_profile_opened
          recommended_user_related_topic_opened
          recommended_user_invite_started
        ],
        "interests" => %w[recommended_interest_opened]
      }

      RECOMMENDATION_GROUPS.index_with do |group|
        group_events =
          events.select { |event| event.recommendation_group == group }
        exposed =
          group_events
            .select { |event| event.event_name == "recommendation_impression" }
            .map(&:user_id)
            .uniq
        openers =
          users_with_events_after_anchor(
            group_events,
            anchor_event_name: "recommendation_impression",
            event_names: open_events_by_group.fetch(group)
          )
        dismissers =
          users_with_events_after_anchor(
            group_events,
            anchor_event_name: "recommendation_impression",
            event_names: %w[recommendation_dismissed]
          )

        {
          exposed_users: exposed.length,
          openers: openers.length,
          open_rate: rate(openers.length, exposed.length),
          dismissers: dismissers.length,
          dismissal_rate: rate(dismissers.length, exposed.length)
        }
      end
    end

    def recommendation_action_funnel(events)
      expansions =
        events.select do |event|
          event.event_name == "recommendation_panel_expanded"
        end
      collapses =
        events.select do |event|
          event.event_name == "recommendation_panel_collapsed"
        end
      group_switches =
        events.select do |event|
          event.event_name == "recommendation_group_selected"
        end
      refreshes =
        events.select { |event| event.event_name == "recommendation_refreshed" }

      {
        expanded_users: expansions.map(&:user_id).uniq.length,
        expansions: expansions.length,
        collapsed_users: collapses.map(&:user_id).uniq.length,
        collapses: collapses.length,
        group_switches: group_switches.filter_map(&:recommendation_group).tally,
        refreshes: refreshes.filter_map(&:recommendation_group).tally
      }
    end

    def local_callout_funnel(events)
      homepage_events = events.select { |event| event.surface == "homepage" }
      viewers = users_for(homepage_events, "local_callout_viewed")
      opened =
        users_with_events_after_anchor(
          homepage_events,
          anchor_event_name: "local_callout_viewed",
          event_names: %w[local_callout_opened]
        )
      savers =
        users_with_events_after_anchor(
          homepage_events,
          anchor_event_name: "local_callout_viewed",
          event_names: %w[local_callout_location_saved]
        )
      dismissers =
        users_with_events_after_anchor(
          homepage_events,
          anchor_event_name: "local_callout_viewed",
          event_names: %w[local_callout_dismissed]
        )

      {
        viewed_users: viewers.length,
        opened_users: opened.length,
        open_rate: rate(opened.length, viewers.length),
        location_savers: savers.length,
        location_save_rate: rate(savers.length, viewers.length),
        dismissers: dismissers.length,
        dismissal_rate: rate(dismissers.length, viewers.length)
      }
    end

    def returning_viewers(events, within_days:)
      events
        .select { |event| event.event_name == "page_view" }
        .group_by(&:user_id)
        .filter_map do |user_id, page_views|
          days = page_views.map { |event| event.created_at.to_date }.uniq.sort
          if days
               .combination(2)
               .any? { |first, second| (second - first).between?(1, within_days) }
            user_id
          end
        end
    end

    def public_interaction_users(
      events,
      anchor_event_name:,
      replies_only:,
      window:,
      as_of: Time.current
    )
      anchored_at_by_user =
        events
          .select { |event| event.event_name == anchor_event_name }
          .group_by(&:user_id)
          .transform_values { |anchors| anchors.map(&:created_at).min }
      public_interaction_users_for_anchors(
        anchored_at_by_user,
        replies_only: replies_only,
        window: window,
        as_of: as_of
      )
    end

    def public_interaction_users_for_anchors(
      anchored_at_by_user,
      replies_only:,
      window:,
      as_of:
    )
      return [] if anchored_at_by_user.empty?

      earliest = anchored_at_by_user.values.min
      latest = [anchored_at_by_user.values.max + window, as_of].min
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

    def mature_cohort_metrics(events, since:, as_of:)
      cutoff = as_of - 7.days
      grouped_recommendation_events =
        events.select do |event|
          event.event_name == "recommendation_impression" &&
            event.recommendation_group.present?
        end
      recommendation_anchors =
        first_recorded_anchors(
          event_name: "recommendation_impression",
          user_ids: grouped_recommendation_events.map(&:user_id).uniq,
          since: since,
          as_of: as_of,
          require_recommendation_group: true
        )
      recommendation_mature, recommendation_in_progress =
        mature_anchors(recommendation_anchors, cutoff: cutoff)
      recommendation_interactors =
        public_interaction_users_for_anchors(
          recommendation_mature,
          replies_only: false,
          window: 7.days,
          as_of: as_of
        )
      recommendation_24h_mature, recommendation_24h_in_progress =
        mature_anchors(recommendation_anchors, cutoff: as_of - 24.hours)
      recommendation_24h_repliers =
        public_interaction_users_for_anchors(
          recommendation_24h_mature,
          replies_only: true,
          window: 24.hours,
          as_of: as_of
        )
      onboarding_anchors =
        first_recorded_anchors(
          event_name: "interest_onboarding_completed",
          user_ids: users_for(events, "interest_onboarding_completed"),
          since: since,
          as_of: as_of
        )
      onboarding_mature, onboarding_in_progress =
        mature_anchors(onboarding_anchors, cutoff: cutoff)
      onboarding_interactors =
        public_interaction_users_for_anchors(
          onboarding_mature,
          replies_only: false,
          window: 7.days,
          as_of: as_of
        )
      onboarding_repliers =
        public_interaction_users_for_anchors(
          onboarding_mature,
          replies_only: true,
          window: 7.days,
          as_of: as_of
        )
      visit_anchors =
        first_recorded_anchors(
          event_name: "page_view",
          user_ids: users_for(events, "page_view"),
          since: since,
          as_of: as_of
        )
      visit_mature, visit_in_progress =
        mature_anchors(visit_anchors, cutoff: cutoff)
      returning_users =
        returning_users_for_anchors(events, visit_mature, within_days: 7)

      {
        as_of: as_of.iso8601,
        seven_day_cutoff: cutoff.iso8601,
        recommendation_exposure: {
          mature_users: recommendation_mature.length,
          in_progress_users: recommendation_in_progress.length,
          public_interactors: recommendation_interactors.length,
          public_interaction_rate:
            rate(recommendation_interactors.length, recommendation_mature.length),
          mature_24h_users: recommendation_24h_mature.length,
          in_progress_24h_users: recommendation_24h_in_progress.length,
          repliers_within_24h: recommendation_24h_repliers.length,
          reply_rate_24h:
            rate(
              recommendation_24h_repliers.length,
              recommendation_24h_mature.length
            )
        },
        interest_onboarding: {
          mature_users: onboarding_mature.length,
          in_progress_users: onboarding_in_progress.length,
          public_interactors: onboarding_interactors.length,
          public_interaction_rate:
            rate(onboarding_interactors.length, onboarding_mature.length),
          first_repliers: onboarding_repliers.length,
          first_reply_rate:
            rate(onboarding_repliers.length, onboarding_mature.length)
        },
        plugin_visits: {
          mature_users: visit_mature.length,
          in_progress_users: visit_in_progress.length,
          returning_users: returning_users.length,
          seven_day_return_rate: rate(returning_users.length, visit_mature.length)
        }
      }
    end

    def first_recorded_anchors(
      event_name:,
      user_ids:,
      since:,
      as_of:,
      require_recommendation_group: false
    )
      return {} if user_ids.empty?

      scope =
        @event_model.where(user_id: user_ids, event_name: event_name).where(
          "created_at <= ?",
          as_of
        )
      if require_recommendation_group
        scope = scope.where.not(recommendation_group: nil)
      end

      scope
        .group(:user_id)
        .minimum(:created_at)
        .select { |_user_id, anchored_at| anchored_at >= since }
    end

    def mature_anchors(anchors, cutoff:)
      mature = anchors.select { |_user_id, anchored_at| anchored_at <= cutoff }

      [mature, anchors.except(*mature.keys)]
    end

    def returning_users_for_anchors(events, anchors, within_days:)
      views_by_user =
        events
          .select { |event| event.event_name == "page_view" }
          .group_by(&:user_id)

      anchors.filter_map do |user_id, anchored_at|
        returned =
          Array(views_by_user[user_id]).any? do |event|
            days_after = event.created_at.to_date - anchored_at.to_date
            days_after.between?(1, within_days)
          end
        user_id if returned
      end
    end

    def users_with_events_after_anchor(
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

    def effective_connections(events)
      actions = %w[message_started local_topic_interacted]
      events
        .select { |event| event.event_name == "location_saved" }
        .group_by(&:user_id)
        .filter_map do |user_id, setup_events|
          joined_at = setup_events.min_by(&:created_at).created_at
          connected =
            events.any? do |event|
              event.user_id == user_id && actions.include?(event.event_name) &&
                event.created_at.between?(joined_at, joined_at + 7.days)
            end
          user_id if connected
        end
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.zero?

      (numerator.to_f / denominator).round(4)
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  class ConnectionMetrics
    RESPONSE_WINDOW = 7.days

    def initialize(since:, as_of: Time.current)
      @since = since
      @as_of = as_of
    end

    def call
      invitations =
        WhereIsMyFriendsPracticeInvitation
          .where(created_at: @since..@as_of)
          .select(
            :id,
            :source,
            :status,
            :sender_id,
            :recipient_id,
            :created_at,
            :responded_at,
            :pm_topic_id
          )
          .to_a
      @sender_follow_up_invitation_ids =
        sender_follow_up_invitation_ids(invitations)

      {
        as_of: @as_of.iso8601,
        seven_day_cutoff: (@as_of - RESPONSE_WINDOW).iso8601,
        privacy_threshold: AggregatePrivacy.threshold,
        by_source:
          WhereIsMyFriendsPracticeInvitation::SOURCES.index_with do |source|
            source_metrics(
              invitations.select { |invitation| invitation.source == source }
            )
          end
      }
    end

    private

    def source_metrics(invitations)
      return limited if source_limited?(invitations)

      mature, in_progress =
        invitations.partition do |invitation|
          invitation.created_at <= @as_of - RESPONSE_WINDOW
        end

      {
        limited: false,
        window: window_metrics(invitations),
        response_cohort_7d: response_metrics(mature, in_progress),
        reciprocal_conversation_7d: reciprocal_metrics(invitations)
      }
    end

    def window_metrics(invitations)
      state_groups =
        WhereIsMyFriendsPracticeInvitation::STATUSES.index_with do |status|
          invitations.select do |invitation|
            status_at_as_of(invitation) == status
          end
        end
      responded =
        invitations.select do |invitation|
          invitation.responded_at.present? && invitation.responded_at <= @as_of
        end
      unresponded = invitations - responded
      breakdown_limited =
        atomic_breakdown_limited?(*state_groups.values, responded, unresponded)

      {
        invitations_sent: invitations.length,
        unique_senders: invitations.map(&:sender_id).uniq.length,
        unique_recipients: invitations.map(&:recipient_id).uniq.length,
        state_breakdown:
          if breakdown_limited
            limited
          else
            { limited: false, responded_at_present: responded.length }.merge(
              state_groups.transform_values(&:length).symbolize_keys
            )
          end
      }
    end

    def response_metrics(mature, in_progress)
      outcomes =
        %w[accepted declined ignored].index_with do |status|
          mature.select do |invitation|
            invitation.status == status && responded_within_window?(invitation)
          end
        end
      responded = outcomes.values.flatten
      unresolved = mature - responded
      late = late_responses(mature)
      if atomic_breakdown_limited?(
           mature,
           in_progress,
           *outcomes.values,
           unresolved,
           late
         )
        return limited
      end

      {
        limited: false,
        mature_invitations: mature.length,
        in_progress_invitations: in_progress.length,
        responded_within_7d: responded.length,
        accepted_within_7d: outcomes.fetch("accepted").length,
        declined_within_7d: outcomes.fetch("declined").length,
        ignored_within_7d: outcomes.fetch("ignored").length,
        unresolved_within_7d: unresolved.length,
        response_rate_7d: rate(responded.length, mature.length),
        acceptance_rate_of_mature_7d:
          rate(outcomes.fetch("accepted").length, mature.length),
        acceptance_rate_of_responded_7d:
          rate(outcomes.fetch("accepted").length, responded.length),
        median_response_seconds: median_response_seconds(responded),
        late_responses: late.length
      }
    end

    def source_limited?(invitations)
      AggregatePrivacy.suppressed?(invitations.map(&:sender_id).uniq.length) ||
        AggregatePrivacy.suppressed?(
          invitations.map(&:recipient_id).uniq.length
        ) || AggregatePrivacy.suppressed?(participant_ids(invitations).length)
    end

    def reciprocal_metrics(invitations)
      accepted_with_pm =
        invitations.select do |invitation|
          invitation.status == "accepted" && invitation.pm_topic_id.present? &&
            invitation.responded_at.present? &&
            invitation.responded_at <= @as_of
        end
      mature, in_progress =
        accepted_with_pm.partition do |invitation|
          invitation.responded_at <= @as_of - RESPONSE_WINDOW
        end
      followed_up =
        mature.select do |invitation|
          @sender_follow_up_invitation_ids.include?(invitation.id)
        end
      without_follow_up = mature - followed_up
      if atomic_breakdown_limited?(
           mature,
           in_progress,
           followed_up,
           without_follow_up
         )
        return limited
      end

      {
        limited: false,
        mature_accepted_invitations: mature.length,
        accepted_in_progress: in_progress.length,
        sender_followed_up_within_7d: followed_up.length,
        reciprocal_conversation_rate_7d: rate(followed_up.length, mature.length)
      }
    end

    def sender_follow_up_invitation_ids(invitations)
      mature_ids =
        invitations.filter_map do |invitation|
          if invitation.status == "accepted" &&
               invitation.pm_topic_id.present? &&
               invitation.responded_at.present? &&
               invitation.responded_at <= @as_of - RESPONSE_WINDOW
            invitation.id
          end
        end
      return Set.new if mature_ids.empty?

      invitation_table = WhereIsMyFriendsPracticeInvitation.table_name
      Post
        .joins(
          "INNER JOIN #{invitation_table} ON " \
            "#{invitation_table}.pm_topic_id = posts.topic_id"
        )
        .where(invitation_table => { id: mature_ids })
        .where("posts.user_id = #{invitation_table}.sender_id")
        .where(post_type: Post.types[:regular], deleted_at: nil, hidden: false)
        .where("posts.post_number > 1")
        .where("posts.created_at > #{invitation_table}.responded_at")
        .where(
          "posts.created_at <= #{invitation_table}.responded_at + " \
            "INTERVAL '7 days'"
        )
        .where("posts.created_at <= ?", @as_of)
        .distinct
        .pluck(Arel.sql("#{invitation_table}.id"))
        .to_set
    end

    def atomic_breakdown_limited?(*groups)
      groups.any? do |group|
        group.present? &&
          AggregatePrivacy.suppressed?(participant_ids(group).length)
      end
    end

    def participant_ids(invitations)
      invitations
        .flat_map do |invitation|
          [invitation.sender_id, invitation.recipient_id]
        end
        .uniq
    end

    def status_at_as_of(invitation)
      if invitation.responded_at.present? && invitation.responded_at > @as_of
        "pending"
      else
        invitation.status
      end
    end

    def responded_within_window?(invitation)
      invitation.responded_at.present? && invitation.responded_at <= @as_of &&
        invitation.responded_at <= invitation.created_at + RESPONSE_WINDOW
    end

    def late_responses(invitations)
      invitations.select do |invitation|
        %w[accepted declined ignored].include?(invitation.status) &&
          invitation.responded_at.present? &&
          invitation.responded_at <= @as_of &&
          invitation.responded_at > invitation.created_at + RESPONSE_WINDOW
      end
    end

    def median_response_seconds(invitations)
      values =
        invitations
          .map do |invitation|
            (invitation.responded_at - invitation.created_at).to_i
          end
          .sort
      return if values.empty?

      middle = values.length / 2
      return values.fetch(middle) if values.length.odd?

      (values.fetch(middle - 1) + values.fetch(middle)) / 2.0
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.zero?

      (numerator.to_f / denominator).round(4)
    end

    def limited
      { limited: true }
    end
  end
end

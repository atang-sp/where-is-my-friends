# frozen_string_literal: true

module WhereIsMyFriends
  class PracticeInvitationEligibility
    CONTRIBUTION_WINDOW = 50

    def initialize(sender:, recipient:)
      @sender = sender
      @recipient = recipient
      @guardian = Guardian.new(sender)
    end

    def available?
      unavailable_reason.nil?
    end

    def communication_available?
      feature_enabled? && sender_available? && recipient_available? &&
        !blocked_relationship? && private_messages_available?
    end

    def unavailable_reason
      return :feature_disabled unless feature_enabled?
      return :self_invitation if @sender.id == @recipient.id
      return :participant_unavailable unless sender_available?
      return :trust_level if @sender.trust_level < minimum_trust_level
      return :recipient_unavailable unless recipient_available?
      return :recipient_opted_out unless recipient_accepts_invitations?
      return :blocked if blocked_relationship?
      return :private_messages_unavailable unless private_messages_available?
      return :profile_incomplete unless sender_profile&.state == "complete"

      nil
    end

    def common_interests
      return [] unless available?

      ids = public_common_interest_ids | contribution_interest_ids
      visible_sender_interests.where(id: ids).order(:name).to_a
    end

    def public_common_interests
      return [] unless available?

      visible_sender_interests
        .where(id: public_common_interest_ids)
        .order(:name)
        .to_a
    end

    private

    def feature_enabled?
      SiteSetting.where_is_my_friends_enabled &&
        SiteSetting.where_is_my_friends_interest_onboarding_enabled &&
        SiteSetting.where_is_my_friends_practice_invitations_enabled
    end

    def minimum_trust_level
      SiteSetting.where_is_my_friends_practice_invitation_min_trust_level
    end

    def sender_profile
      @sender_profile ||=
        WhereIsMyFriendsInterestProfile.find_by(user_id: @sender.id)
    end

    def recipient_profile
      @recipient_profile ||=
        WhereIsMyFriendsInterestProfile.find_by(user_id: @recipient.id)
    end

    def recipient_available?
      @recipient.active? && !@recipient.staged? && !@recipient.suspended? &&
        !@recipient.silenced? && @guardian.can_see_profile?(@recipient)
    end

    def sender_available?
      @sender.active? && !@sender.staged? && !@sender.suspended? &&
        !@sender.silenced?
    end

    def recipient_accepts_invitations?
      @recipient.user_option.where_is_my_friends_accept_practice_invitations?
    end

    def private_messages_available?
      @guardian.can_send_private_message?(@recipient) &&
        Guardian.new(@recipient).can_send_private_message?(@sender) &&
        communication_allowed?(@sender, @recipient) &&
        communication_allowed?(@recipient, @sender)
    end

    def communication_allowed?(actor, target)
      UserCommScreener
        .new(acting_user: actor, target_user_ids: [target.id])
        .preventing_actor_communication
        .exclude?(target.id)
    end

    def blocked_relationship?
      ids = [@sender.id, @recipient.id]
      pair_sql =
        "(user_id = :sender AND muted_user_id = :recipient) OR " \
          "(user_id = :recipient AND muted_user_id = :sender)"
      muted =
        MutedUser.where(
          pair_sql,
          sender: @sender.id,
          recipient: @recipient.id
        ).exists?
      return true if muted

      ignored_pair_sql =
        "(user_id = :sender AND ignored_user_id = :recipient) OR " \
          "(user_id = :recipient AND ignored_user_id = :sender)"
      IgnoredUser
        .where(ignored_pair_sql, sender: ids.first, recipient: ids.last)
        .where("expiring_at > ?", Time.current)
        .exists?
    end

    def public_common_interest_ids
      profile = recipient_profile
      return [] unless profile&.state == "complete"
      return [] unless profile.show_interests_publicly?

      sender_interest_ids & profile.interests.pluck(:tag_id)
    end

    def contribution_interest_ids
      profile = recipient_profile
      return [] unless profile&.state == "complete" && profile.recommendable?

      topic_ids = visible_contribution_topics.map(&:id)
      return [] if topic_ids.empty?

      contributed_topic_ids =
        Post
          .where(
            user_id: @recipient.id,
            topic_id: topic_ids,
            post_type: Post.types[:regular],
            deleted_at: nil,
            hidden: false
          )
          .pluck(:topic_id)
          .uniq

      visible_contribution_topics
        .select { |topic| contributed_topic_ids.include?(topic.id) }
        .flat_map(&:tags)
        .map(&:id)
        .uniq & sender_interest_ids
    end

    def visible_contribution_topics
      @visible_contribution_topics ||=
        begin
          names = visible_sender_interests.pluck(:name)
          if names.empty?
            []
          else
            TopicQuery
              .new(@sender, per_page: CONTRIBUTION_WINDOW, tags: names)
              .list_latest
              .topics
          end
        end
    end

    def sender_interest_ids
      @sender_interest_ids ||= sender_profile.interests.pluck(:tag_id)
    end

    def visible_sender_interests
      @visible_sender_interests ||=
        DiscourseTagging.visible_tags(@guardian).where(
          id: sender_profile.interests.select(:tag_id)
        )
    end
  end
end

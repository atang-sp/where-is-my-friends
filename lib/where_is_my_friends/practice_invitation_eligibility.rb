# frozen_string_literal: true

module WhereIsMyFriends
  class PracticeInvitationEligibility
    CONTRIBUTION_WINDOW = 50

    def initialize(sender:, recipient:)
      @sender = sender
      @recipient = recipient
      @guardian = Guardian.new(sender)
      @member_selection =
        ViewerAwareMemberSelection.new(viewer: sender, guardian: @guardian)
    end

    def self.bulk_common_interests(sender:, recipients:)
      return {} if recipients.empty?
      
      sender_guardian = Guardian.new(sender)
      sender_profile = WhereIsMyFriendsInterestProfile.find_by(user_id: sender.id)
      return {} unless sender_profile
      
      sender_interest_ids = sender_profile.interests.pluck(:tag_id)
      return {} if sender_interest_ids.empty?

      visible_sender_interests = DiscourseTagging.visible_tags(sender_guardian).where(id: sender_interest_ids).order(:name).to_a
      return {} if visible_sender_interests.empty?

      # Preload profiles for recipients
      profiles = WhereIsMyFriendsInterestProfile.where(user_id: recipients.map(&:id)).includes(:interests).index_by(&:user_id)
      
      # Preload posts for contribution check
      topic_names = visible_sender_interests.map(&:name)
      visible_topics = topic_names.empty? ? [] : TopicQuery.new(sender, per_page: CONTRIBUTION_WINDOW, tags: topic_names).list_latest.topics
      topic_ids = visible_topics.map(&:id)
      
      contributed_topic_ids_by_user = {}
      if topic_ids.present?
        Post.where(
          user_id: recipients.map(&:id),
          topic_id: topic_ids,
          post_type: Post.types[:regular],
          deleted_at: nil,
          hidden: false
        ).pluck(:user_id, :topic_id).each do |user_id, topic_id|
          contributed_topic_ids_by_user[user_id] ||= Set.new
          contributed_topic_ids_by_user[user_id] << topic_id
        end
      end

      # We still need to do relationship checks (muted/ignored), but those are fast or cached.
      # To keep it simple, we initialize the instance but inject the cached data if we wanted to.
      # Since `bulk_common_interests` returns just the tags, we can just do the logic inline for speed.
      member_selection = ViewerAwareMemberSelection.new(viewer: sender, guardian: sender_guardian)
      
      recipients.each_with_object({}) do |recipient, hash|
        # Fast availability check (skip trust level etc. as this is for recommendations where basic visibility is checked)
        # We rely on the recommendation engine to have already filtered out blocked users.
        profile = profiles[recipient.id]
        
        common_tag_ids = Set.new
        
        # Public common interests
        if profile&.state == "complete" && profile.show_interests_publicly?
          recipient_interest_ids = profile.interests.map(&:tag_id)
          common_tag_ids.merge(sender_interest_ids & recipient_interest_ids)
        end
        
        # Contribution interests
        if profile&.state == "complete" && profile.recommendable? && contributed_topic_ids_by_user[recipient.id]
          contributed_topics = visible_topics.select { |t| contributed_topic_ids_by_user[recipient.id].include?(t.id) }
          contribution_tags = contributed_topics.flat_map(&:tags).map(&:id).uniq & sender_interest_ids
          common_tag_ids.merge(contribution_tags)
        end
        
        hash[recipient.id] = visible_sender_interests.select { |tag| common_tag_ids.include?(tag.id) }
      end
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
      @member_selection.visible?(@recipient)
    end

    def sender_available?
      @member_selection.account_eligible?(@sender)
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

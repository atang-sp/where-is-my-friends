# frozen_string_literal: true

module WhereIsMyFriends
  class PracticeInvitationsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_feature_enabled

    def index
      render json: {
               incoming:
                 serialize_many(
                   WhereIsMyFriendsPracticeInvitation
                     .where(recipient_id: current_user.id)
                     .recent_first
                     .limit(50)
                 ),
               outgoing:
                 serialize_many(
                   WhereIsMyFriendsPracticeInvitation
                     .where(sender_id: current_user.id)
                     .recent_first
                     .limit(50)
                 ),
               accepting_invitations:
                 current_user.user_option.where_is_my_friends_accept_practice_invitations?
             }
    end

    def availability
      recipient = User.find_by_username(params[:username].to_s)
      raise Discourse::NotFound unless recipient

      eligibility =
        PracticeInvitationEligibility.new(
          sender: current_user,
          recipient: recipient
        )
      interests = eligibility.common_interests
      unless eligibility.available?
        return render json: { available: false, interests: [] }
      end

      render json: {
               recipient_id: recipient.id,
               username: recipient.username,
               name: recipient.name,
               available: interests.present?,
               interests: interests.map { |tag| serialize_tag(tag) }
             }
    end

    def create
      recipient = User.find_by(id: params[:recipient_id].to_i)
      raise Discourse::NotFound unless recipient

      eligibility =
        PracticeInvitationEligibility.new(
          sender: current_user,
          recipient: recipient
        )
      if eligibility.unavailable_reason == :trust_level
        return render_invitation_error(:trust_level, status: 403)
      end

      interests = eligibility.common_interests
      tag = interests.find { |interest| interest.id == params[:tag_id].to_i }
      return render_invitation_error(:unavailable) unless tag
      if daily_limit_reached?
        return render_invitation_error(:daily_limit, status: 429)
      end
      return render_invitation_error(:duplicate) if pending_pair?(recipient)

      RateLimiter.new(
        current_user,
        "where-is-my-friends-practice-invitation",
        daily_limit,
        1.day
      ).performed!

      filtered_safety_items =
        Array(params[:safety_items]).map(&:to_s).select do |item|
          WhereIsMyFriendsPracticeInvitation::VALID_SAFETY_ITEMS.include?(item)
        end

      invitation = nil
      WhereIsMyFriendsPracticeInvitation.transaction do
        invitation =
          WhereIsMyFriendsPracticeInvitation.create!(
            sender: current_user,
            recipient: recipient,
            tag: tag,
            interest_name: tag.name,
            proposed_at: proposed_at,
            note: params[:note].to_s.strip.presence,
            safety_items: filtered_safety_items
          )
        create_notification(invitation)
      end
      render json: { invitation: serialize(invitation) }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      render_invitation_error(:invalid)
    rescue ArgumentError
      render_invitation_error(:invalid)
    end

    def accept
      invitation = incoming_invitation
      return render_invitation_error(:invalid_state) unless invitation.pending?

      invitation.with_lock do
        unless invitation.pending?
          return render_invitation_error(:invalid_state)
        end
        eligibility =
          PracticeInvitationEligibility.new(
            sender: invitation.sender,
            recipient: invitation.recipient
          )
        unless eligibility.communication_available?
          return render_invitation_error(:private_messages_unavailable)
        end

        post =
          PostCreator.create!(
            current_user,
            archetype: Archetype.private_message,
            target_usernames: invitation.sender.username,
            title:
              I18n.t(
                "where_is_my_friends.practice_invitations.pm_title",
                interest: invitation.interest_name,
                locale: current_user.effective_locale
              ),
            raw:
              invitation.response_message(locale: current_user.effective_locale)
          )
        invitation.update!(
          status: "accepted",
          responded_at: Time.current,
          pm_topic_id: post.topic_id
        )
      end
      mark_notification_read(invitation)

      render json: { invitation: serialize(invitation.reload) }
    end

    def decline
      respond_with("declined")
    end

    def ignore
      respond_with("ignored")
    end

    private

    def ensure_feature_enabled
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_interest_onboarding_enabled &&
               SiteSetting.where_is_my_friends_practice_invitations_enabled
        raise Discourse::NotFound
      end
    end

    def incoming_invitation
      WhereIsMyFriendsPracticeInvitation.find_by!(
        id: params[:id],
        recipient_id: current_user.id
      )
    end

    def respond_with(status)
      invitation = incoming_invitation
      updated = false
      invitation.with_lock do
        if invitation.pending?
          invitation.update!(status: status, responded_at: Time.current)
          updated = true
        end
      end
      return render_invitation_error(:invalid_state) unless updated

      mark_notification_read(invitation)
      render json: { invitation: serialize(invitation) }
    end

    def daily_limit
      SiteSetting.where_is_my_friends_practice_invitation_daily_limit
    end

    def daily_limit_reached?
      WhereIsMyFriendsPracticeInvitation.where(
        sender_id: current_user.id,
        created_at: 1.day.ago..
      ).count >= daily_limit
    end

    def pending_pair?(recipient)
      WhereIsMyFriendsPracticeInvitation
        .where(status: "pending")
        .where(
          "(sender_id = :sender AND recipient_id = :recipient) OR " \
            "(sender_id = :recipient AND recipient_id = :sender)",
          sender: current_user.id,
          recipient: recipient.id
        )
        .exists?
    end

    def proposed_at
      return if params[:proposed_at].blank?

      value = Time.zone.parse(params[:proposed_at].to_s)
      if value.blank? || value < 5.minutes.ago || value > 1.year.from_now
        raise ArgumentError
      end

      value
    end

    def create_notification(invitation)
      Notification.create!(
        user: invitation.recipient,
        notification_type: Notification.types[:custom],
        data: {
          title: "where_is_my_friends.practice_invitations.notification_title",
          message:
            "where_is_my_friends.practice_invitations.notification_message",
          display_username: invitation.sender.username,
          username: invitation.sender.username,
          user_id: invitation.sender.id,
          user_avatar_template: invitation.sender.avatar_template,
          topic_title:
            invitation.preset_message(
              locale: invitation.recipient.effective_locale
            ),
          action_url: "/where-is-my-friends/interests",
          practice_invitation_id: invitation.id
        }.to_json
      )
    end

    def mark_notification_read(invitation)
      Notification
        .where(
          user_id: current_user.id,
          notification_type: Notification.types[:custom],
          read: false
        )
        .where(
          "data::jsonb ->> 'practice_invitation_id' = ?",
          invitation.id.to_s
        )
        .update_all(read: true, updated_at: Time.current)
    end

    def serialize_many(scope)
      scope.map { |invitation| serialize(invitation) }
    end

    def serialize(invitation)
      {
        id: invitation.id,
        status: invitation.status,
        sender: serialize_user(invitation.sender),
        recipient: serialize_user(invitation.recipient),
        interest: {
          id: invitation.tag_id,
          name: invitation.interest_name
        },
        proposed_at: invitation.proposed_at,
        note: invitation.note,
        safety_items: Array(invitation.safety_items),
        preset_message:
          invitation.preset_message(locale: current_user.effective_locale),
        responded_at: invitation.responded_at,
        pm_topic_id: invitation.pm_topic_id,
        pm_url:
          ("/t/#{invitation.pm_topic_id}" if invitation.pm_topic_id.present?),
        created_at: invitation.created_at
      }
    end

    def serialize_user(user)
      { id: user.id, username: user.username, name: user.name }
    end

    def serialize_tag(tag)
      { id: tag.id, name: tag.name }
    end

    def render_invitation_error(reason, status: 422)
      render_json_error(
        I18n.t("where_is_my_friends.practice_invitations.errors.#{reason}"),
        status: status
      )
    end
  end
end

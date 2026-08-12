# frozen_string_literal: true

module WhereIsMyFriends
  class UserTagsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_feature_enabled

    def index
      target = User.find_by_username(params[:username].to_s)
      raise Discourse::NotFound unless target

      render json: { user_tags: public_tags_for(target) }
    end

    def mine
      tags =
        WhereIsMyFriendsUserTag
          .for_target(current_user)
          .or(WhereIsMyFriendsUserTag.by_proposer(current_user))
          .pending_first
          .limit(100)

      render json: {
               accepting_user_tags:
                 current_user.user_option.where_is_my_friends_accept_user_tags?,
               pending:
                 serialize_many(
                   tags
                     .select { |tag| tag.pending? }
                     .select do |tag|
                       tag.target_user_id == current_user.id ||
                         tag.proposer_id == current_user.id
                     end
                 ),
               managed: serialize_many(tags.select { |tag| !tag.pending? })
             }
    end

    def create
      target = User.find_by_username(params[:username].to_s)
      raise Discourse::NotFound unless target
      if target.id == current_user.id
        return render_tag_error(:self_tag, status: 403)
      end

      selection = ViewerAwareMemberSelection.new(viewer: current_user)
      unless selection.visible?(target)
        return render_tag_error(:unavailable, status: 403)
      end
      if UserTagVisibility.blocked_relationship?(current_user, target)
        return render_tag_error(:unavailable, status: 403)
      end
      unless target.user_option.where_is_my_friends_accept_user_tags?
        return render_tag_error(:opted_out, status: 403)
      end
      return render_tag_error(:daily_limit, status: 429) if daily_limit_reached?
      if duplicate_pending?(target, params[:label].to_s)
        return render_tag_error(:duplicate, status: 422)
      end

      RateLimiter.new(
        current_user,
        "where-is-my-friends-user-tag",
        daily_proposal_limit,
        1.day
      ).performed!

      tag = nil
      WhereIsMyFriendsUserTag.transaction do
        tag =
          WhereIsMyFriendsUserTag.create!(
            proposer: current_user,
            target_user: target,
            label: params[:label].to_s
          )
        create_notification(tag)
      end
      record_event("user_tag_proposed")
      render json: { user_tag: serialize(tag) }
    rescue ActiveRecord::RecordInvalid
      render_tag_error(:invalid)
    rescue RateLimiter::LimitExceeded
      render_tag_error(:daily_limit, status: 429)
    end

    def approve
      respond_with_state(:approve!)
    end

    def reject
      respond_with_state(:reject!)
    end

    def remove
      respond_with_state(:remove!)
    end

    def endorse
      tag = own_or_visible_tag
      return render_tag_error(:invalid_state) unless tag&.approved?

      endorsement =
        WhereIsMyFriendsTagEndorsement.new(user: current_user, tag: tag)
      return render_tag_error(:invalid_endorsement) if endorsement.invalid?

      WhereIsMyFriendsTagEndorsement.create!(user: current_user, tag: tag)
      record_event("user_tag_endorsed")
      render json: { user_tag: public_serialize(tag) }
    rescue ActiveRecord::RecordNotUnique
      render_tag_error(:already_endorsed)
    end

    def unendorse
      tag = own_or_visible_tag
      endorsement =
        WhereIsMyFriendsTagEndorsement.find_by(tag: tag, user: current_user)
      if endorsement
        endorsement.destroy!
        record_event("user_tag_endorsement_removed")
      end
      render json: { user_tag: public_serialize(tag) }
    rescue ActiveRecord::RecordInvalid
      render_tag_error(:invalid_endorsement)
    end

    private

    def respond_with_state(action)
      tag =
        if action == :remove!
          current_user_approved_tag
        else
          current_user_pending_tag
        end
      return render_tag_error(:invalid_state) unless tag

      event = {
        approve!: "user_tag_approved",
        reject!: "user_tag_rejected",
        remove!: "user_tag_removed"
      }.fetch(action)
      tag.send(action)
      record_event(event)
      render json: { user_tag: serialize(tag) }
    end

    def current_user_pending_tag
      WhereIsMyFriendsUserTag.for_target(current_user).find_by(
        id: params[:id].to_i,
        status: "pending"
      )
    end

    def current_user_approved_tag
      WhereIsMyFriendsUserTag.for_target(current_user).find_by(
        id: params[:id].to_i,
        status: "approved"
      )
    end

    def own_or_visible_tag
      WhereIsMyFriendsUserTag.find_by(id: params[:id].to_i)
    end

    def public_tags_for(target)
      UserTagVisibility.public_tags_for(target, viewer: current_user)
    end

    def public_serialize(tag)
      UserTagVisibility.serialize_tag(tag, current_user)
    end

    def serialize_many(tags)
      tags.map { |tag| serialize(tag) }
    end

    def serialize(tag)
      {
        id: tag.id,
        label: tag.label,
        status: tag.status,
        proposer: serialize_user(tag.proposer),
        target: serialize_user(tag.target_user),
        responded_at: tag.responded_at,
        created_at: tag.created_at
      }
    end

    def serialize_user(user)
      { id: user.id, username: user.username, name: user.name }
    end

    def duplicate_pending?(target, label)
      normalized = label.to_s.strip.gsub(/\s+/, " ")
      WhereIsMyFriendsUserTag
        .by_proposer(current_user)
        .for_target(target)
        .where("LOWER(label) = LOWER(?)", normalized)
        .exists?
    end

    def daily_limit_reached?
      WhereIsMyFriendsUserTag
        .by_proposer(current_user)
        .where("created_at > ?", 1.day.ago)
        .count >= daily_proposal_limit
    end

    def daily_proposal_limit
      SiteSetting.where_is_my_friends_user_tag_daily_proposal_limit.to_i.clamp(
        1,
        100
      )
    end

    def create_notification(tag)
      Notification.create!(
        user: tag.target_user,
        notification_type: Notification.types[:custom],
        data: {
          title: "where_is_my_friends.user_tags.notification_title",
          message: "where_is_my_friends.user_tags.notification_message",
          display_username: tag.proposer.username,
          username: tag.proposer.username,
          user_id: tag.proposer.id,
          user_avatar_template: tag.proposer.avatar_template,
          topic_title: tag.label,
          action_url: "/where-is-my-friends/tags",
          user_tag_id: tag.id
        }.to_json
      )
    end

    def record_event(event_name)
      WhereIsMyFriendsEvent.create!(
        user_id: current_user.id,
        event_name: event_name
      )
    end

    def render_tag_error(reason, status: 422)
      render_json_error(
        I18n.t("where_is_my_friends.user_tags.errors.#{reason}"),
        status: status
      )
    end

    def ensure_feature_enabled
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_user_tags_enabled
        raise Discourse::NotFound
      end
    end
  end
end

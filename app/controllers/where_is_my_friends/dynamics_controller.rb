# frozen_string_literal: true

module WhereIsMyFriends
  class DynamicsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in

    def index
      render json:
               dynamic_feed.feed(
                 username: params.require(:username),
                 before_id: params[:before_id]
               )
    end

    def recent
      unless SiteSetting.where_is_my_friends_dynamics_homepage_enabled
        raise Discourse::NotFound
      end
      render json: dynamic_feed.recent
    end

    def feed
      unless SiteSetting.where_is_my_friends_dynamics_feed_enabled
        raise Discourse::NotFound
      end
      render json: dynamic_feed.discover(before_id: params[:before_id])
    end

    def create
      result = dynamic_feed.create(raw: params.require(:raw))
      render json: result, status: result[:queued] ? 202 : 200
    rescue DynamicFeed::InvalidContent => error
      render_json_error(error.message, status: 422)
    end

    private

    def dynamic_feed
      @dynamic_feed ||= DynamicFeed.new(viewer: current_user)
    end
  end
end

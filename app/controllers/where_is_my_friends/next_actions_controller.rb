# frozen_string_literal: true

module WhereIsMyFriends
  class NextActionsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_feature_enabled

    def show
      render json:
               NextAction.new(
                 user: current_user,
                 guardian: guardian,
                 as_of: Time.current
               ).call
    end

    private

    def ensure_feature_enabled
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_first_connection_enabled
        raise Discourse::NotFound
      end
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  class EventsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_plugin_enabled

    def create
      event =
        WhereIsMyFriendsEvent.create!(
          user_id: current_user.id,
          event_name: params[:event_name],
          location_mode: params[:location_mode].presence,
          result_bucket: result_bucket
        )

      render json: success_json.merge(event_id: event.id)
    rescue ActiveRecord::RecordInvalid
      render_json_error(
        I18n.t("where_is_my_friends.invalid_event"),
        status: 422
      )
    end

    private

    def result_bucket
      return if params[:result_count].blank?

      WhereIsMyFriendsEvent.result_bucket(params[:result_count])
    end

    def ensure_plugin_enabled
      raise Discourse::NotFound unless SiteSetting.where_is_my_friends_enabled
    end
  end
end

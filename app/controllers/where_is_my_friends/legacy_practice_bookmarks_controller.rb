# frozen_string_literal: true

module WhereIsMyFriends
  class LegacyPracticeBookmarksController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_feature_enabled

    def index
      bookmarks =
        WhereIsMyFriendsLegacyPracticeBookmark
          .where(user_id: current_user.id)
          .recent_first
          .limit(100)

      render json: {
               bookmarks: bookmarks.map { |bookmark| serialize(bookmark) }
             }
    end

    def reconfirm
      update_state("reconfirmed", confirmed_at: Time.current)
    end

    def dismiss
      update_state("dismissed", dismissed_at: Time.current)
    end

    private

    def ensure_feature_enabled
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_interest_onboarding_enabled
        raise Discourse::NotFound
      end
    end

    def current_bookmark
      WhereIsMyFriendsLegacyPracticeBookmark.find_by!(
        id: params[:id],
        user_id: current_user.id
      )
    end

    def update_state(state, timestamp)
      bookmark = current_bookmark
      updated = false
      bookmark.with_lock do
        if bookmark.state == "needs_reconfirmation"
          bookmark.update!({ state: state }.merge(timestamp))
          updated = true
        end
      end
      unless updated
        return(
          render_json_error(
            I18n.t(
              "where_is_my_friends.legacy_practice_bookmarks.already_handled"
            ),
            status: 422
          )
        )
      end

      render json: { bookmark: serialize(bookmark) }
    end

    def serialize(bookmark)
      {
        id: bookmark.id,
        state: bookmark.state,
        target: {
          id: bookmark.target_user.id,
          username: bookmark.target_user.username,
          name: bookmark.target_user.name
        },
        source_created_at: bookmark.source_created_at,
        mutual_history: bookmark.mutual_history?,
        confirmed_at: bookmark.confirmed_at,
        dismissed_at: bookmark.dismissed_at
      }
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  class FlyingChessClaimsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in

    def create
      FlyingChess::CompletionClaim::Redeem.call(service_params) do
        on_success do |profile:|
          render json:
                   success_json.merge(
                     achievement:
                       WhereIsMyFriendsFlyingChessProfileSerializer.new(
                         profile,
                         scope: guardian,
                         root: false
                       ).as_json
                   )
        end
        on_failed_contract do |contract|
          render_json_error(contract.errors.full_messages, status: 400)
        end
        on_model_not_found(:user) { raise Discourse::NotFound }
        on_failed_policy(:claims_enabled) { raise Discourse::NotFound }
        on_failed_policy(:claim_available) { render_claim_conflict }
        on_lock_not_acquired(:user) do
          render_json_error(
            I18n.t("where_is_my_friends.flying_chess.claim_failed"),
            status: 503
          )
        end
        on_exceptions(FlyingChess::ClaimToken::InvalidClaim) do |error|
          render_json_error(error.message, status: 422)
        end
        on_exceptions(ActiveRecord::RecordNotUnique) { render_claim_conflict }
        on_failure do
          render_json_error(
            I18n.t("where_is_my_friends.flying_chess.claim_failed"),
            status: 422
          )
        end
      end
    end

    def update_profile
      FlyingChess::AchievementProfile::SetVisibility.call(service_params) do
        on_success do |updated_profile:|
          render json:
                   success_json.merge(
                     achievement:
                       WhereIsMyFriendsFlyingChessProfileSerializer.new(
                         updated_profile,
                         scope: guardian,
                         root: false
                       ).as_json
                   )
        end
        on_failed_contract do |contract|
          render_json_error(contract.errors.full_messages, status: 400)
        end
        on_model_not_found(:user) { raise Discourse::NotFound }
        on_failed_policy(:achievements_enabled) { raise Discourse::NotFound }
        on_model_not_found(:profile) { raise Discourse::NotFound }
        on_failed_policy(:can_manage_profile) do
          raise Discourse::InvalidAccess.new
        end
        on_failure do
          render_json_error(
            I18n.t("where_is_my_friends.flying_chess.profile_update_failed"),
            status: 422
          )
        end
      end
    end

    private

    def render_claim_conflict
      render_json_error(
        I18n.t("where_is_my_friends.flying_chess.already_claimed"),
        status: 409
      )
    end
  end
end

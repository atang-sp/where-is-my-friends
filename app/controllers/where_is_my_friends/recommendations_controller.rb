# frozen_string_literal: true

module WhereIsMyFriends
  class RecommendationsController < ::ApplicationController
    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_feature_enabled

    def index
      profile = current_profile
      render json: RecommendationEngine.new(current_user).call(profile: profile)
    end

    def update_profile
      catalogue_ids =
        RecommendationEngine
          .catalogue_for(current_user)
          .map { |entry| entry[:id] }
      interest_ids = Array(params[:interest_ids]).map(&:to_i).uniq
      minimum = [3, catalogue_ids.length].min

      unless interest_ids.length.between?(minimum, 5) &&
               (interest_ids - catalogue_ids).empty?
        return(
          render_json_error(
            I18n.t("where_is_my_friends.invalid_interests"),
            status: 422
          )
        )
      end

      purpose = params[:purpose].to_s
      if WhereIsMyFriendsInterestProfile::PURPOSES.exclude?(purpose)
        return(
          render_json_error(
            I18n.t("where_is_my_friends.invalid_purpose"),
            status: 422
          )
        )
      end

      profile = nil
      WhereIsMyFriendsInterestProfile.transaction do
        profile = current_profile
        profile.update!(
          purpose: purpose,
          personalization_enabled: true,
          recommendable: boolean_param(:recommendable, default: true),
          show_interests_publicly:
            boolean_param(:show_interests_publicly, default: false),
          completed_at: Time.current,
          dismissed_at: nil
        )
        profile.interests.delete_all
        interest_ids.each_with_index do |tag_id, position|
          profile.interests.create!(tag_id: tag_id, position: position)
        end
        record_event("interest_onboarding_completed")
      end

      render json: RecommendationEngine.new(current_user).call(profile: profile)
    end

    def skip
      profile = clear_personalization("interest_onboarding_skipped")
      render json: { state: profile.state }
    end

    def destroy_profile
      profile = clear_personalization("personalization_disabled")
      render json: { state: profile.state }
    end

    def dismiss
      profile = current_profile
      target_type = params[:target_type].to_s
      target_id = params[:target_id].to_i
      payload = RecommendationEngine.new(current_user).call(profile: profile)
      recommendation_key =
        target_type == "topic" ? :recommended_topics : :recommended_users
      visible_ids =
        if WhereIsMyFriendsRecommendationDismissal::TARGET_TYPES.include?(
             target_type
           )
          payload.fetch(recommendation_key).pluck(:id)
        else
          []
        end

      if visible_ids.exclude?(target_id)
        return(
          render_json_error(
            I18n.t("where_is_my_friends.invalid_recommendation"),
            status: 422
          )
        )
      end

      profile.dismissals.find_or_create_by!(
        target_type: target_type,
        target_id: target_id
      )
      record_event("recommendation_dismissed")

      render json: RecommendationEngine.new(current_user).call(profile: profile)
    end

    private

    def current_profile
      WhereIsMyFriendsInterestProfile.find_or_create_by!(
        user_id: current_user.id
      )
    end

    def boolean_param(name, default:)
      value = params[name]
      return default if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def clear_personalization(event_name)
      profile = current_profile

      WhereIsMyFriendsInterestProfile.transaction do
        profile.update!(
          purpose: nil,
          personalization_enabled: false,
          recommendable: false,
          show_interests_publicly: false,
          completed_at: nil,
          dismissed_at: Time.current
        )
        profile.interests.delete_all
        profile.dismissals.delete_all
        record_event(event_name)
      end

      profile
    end

    def record_event(event_name)
      WhereIsMyFriendsEvent.create!(
        user_id: current_user.id,
        event_name: event_name
      )
    end

    def ensure_feature_enabled
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_interest_onboarding_enabled
        raise Discourse::NotFound
      end
    end
  end
end

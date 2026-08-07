# frozen_string_literal: true

module WhereIsMyFriends
  class RecommendationsController < ::ApplicationController
    TARGET_RECOMMENDATIONS = {
      "topic" => {
        group: "topics",
        key: :recommended_topics
      },
      "user" => {
        group: "people",
        key: :recommended_users
      },
      "interest" => {
        group: "interests",
        key: :recommended_interests
      }
    }.freeze

    requires_plugin "where-is-my-friends"

    before_action :ensure_logged_in
    before_action :ensure_feature_enabled

    def index
      group = params[:group].presence
      if group && !RecommendationEngine::GROUP_METHODS.key?(group)
        return(
          render_json_error(
            I18n.t("where_is_my_friends.invalid_recommendation"),
            status: 422
          )
        )
      end

      profile = current_profile
      render json:
               RecommendationEngine.new(
                 current_user,
                 diversity_seed: params[:refresh]
               ).call(profile: profile, group: group)
    end

    def update_profile
      engine = RecommendationEngine.new(current_user)
      catalogue = engine.catalogue
      catalogue_ids = catalogue.map { |entry| entry[:id] }
      interest_ids = Array(params[:interest_ids]).map(&:to_i).uniq
      minimum = [RecommendationEngine::MIN_INTERESTS, catalogue_ids.length].min

      unless interest_ids.length.between?(
               minimum,
               RecommendationEngine::MAX_INTERESTS
             ) && (interest_ids - catalogue_ids).empty?
        return(
          render_json_error(
            I18n.t("where_is_my_friends.invalid_interests"),
            status: 422
          )
        )
      end

      unless valid_per_group_limits?(interest_ids, catalogue)
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
      recommendation = TARGET_RECOMMENDATIONS[target_type]
      requested_group = params[:group].presence
      if recommendation.nil? ||
           (
             requested_group.present? &&
               requested_group != recommendation[:group]
           )
        return(
          render_json_error(
            I18n.t("where_is_my_friends.invalid_recommendation"),
            status: 422
          )
        )
      end

      engine = RecommendationEngine.new(current_user)
      payload = engine.call(profile: profile, group: recommendation[:group])
      visible_ids =
        if WhereIsMyFriendsRecommendationDismissal::TARGET_TYPES.include?(
             target_type
           )
          payload.fetch(recommendation[:key]).pluck(:id)
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
      record_event(
        "recommendation_dismissed",
        recommendation_event_metadata(target_type: target_type)
      )

      render json: engine.call(profile: profile, group: requested_group)
    end

    private

    def valid_per_group_limits?(interest_ids, catalogue)
      ids_by_group =
        catalogue
          .select { |entry| interest_ids.include?(entry[:id]) }
          .group_by { |entry| entry[:group_key] }
      ids_by_group.all? do |group_key, entries|
        group = InterestCatalogue.group(group_key)
        next true unless group

        max = InterestCatalogue.group_max_per_group(group)
        next true unless max

        entries.length <= max
      end
    end

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

    def record_event(event_name, metadata = {})
      WhereIsMyFriendsEvent.create!(
        user_id: current_user.id,
        event_name: event_name,
        **metadata
      )
    end

    def recommendation_event_metadata(target_type: nil)
      metadata = {}
      recommendation_group = TARGET_RECOMMENDATIONS.dig(target_type, :group)
      metadata[
        :recommendation_group
      ] = recommendation_group if recommendation_group
      surface = params[:surface].presence
      metadata[:surface] = surface if WhereIsMyFriendsEvent::SURFACES.include?(
        surface
      )
      candidate_source = params[:candidate_source].presence
      if WhereIsMyFriendsEvent::CANDIDATE_SOURCES.include?(candidate_source)
        metadata[:candidate_source] = candidate_source
      end
      algorithm_version = params[:algorithm_version].presence
      if WhereIsMyFriendsEvent::ALGORITHM_VERSIONS.include?(algorithm_version)
        metadata[:algorithm_version] = algorithm_version
      end
      if params[:rank].present?
        metadata[:rank_bucket] = WhereIsMyFriendsEvent.rank_bucket(
          params[:rank]
        )
      end
      metadata
    end

    def ensure_feature_enabled
      unless SiteSetting.where_is_my_friends_enabled &&
               SiteSetting.where_is_my_friends_interest_onboarding_enabled
        raise Discourse::NotFound
      end
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  module Recommendations
    class UserEngine < Base
      def initialize(user:, guardian:, diversity_seed: nil, topic_engine:, member_selection:)
        super(user: user, guardian: guardian, diversity_seed: diversity_seed)
        @topic_engine = topic_engine
        @member_selection = member_selection
      end

      def call(profile:, limit: RecommendationEngine::MAX_USERS, include_optional_details: true)
        viewer_tags = profile_interest_tags(profile)
        return [] if viewer_tags.empty?

        topics = @topic_engine.scored_topic_candidates(profile).map(&:first)
        contributions = contribution_topics(topics)
        similar_tag_ids = visible_interest_tags.where(
          name: InterestCatalogue.member_candidate_names(viewer_tags.map(&:name))
        ).select(:id)
        matching_profile_ids = WhereIsMyFriendsUserInterest.where(tag_id: similar_tag_ids).select(:user_id)
        
        base_profile_scope = WhereIsMyFriendsInterestProfile
          .where(personalization_enabled: true, recommendable: true)
          .where.not(completed_at: nil)
          .where.not(user_id: relationship_exclusions)
        
        profile_scope = base_profile_scope.where(user_id: matching_profile_ids).or(
          base_profile_scope.where(user_id: contributions.keys)
        )
        
        excluded_ids = relationship_exclusions
        user_scope = ViewerAwareMemberSelection
          .eligible_users(User.where(id: profile_scope.select(:user_id)))
          .where("last_seen_at >= ?", RecommendationEngine::MEMBER_ACTIVE_WINDOW.ago)
          .where.not(id: excluded_ids)
          .includes(:user_profile, :user_option, :user_stat)
          .order(last_seen_at: :desc)
          
        users = @member_selection.select(scope: user_scope, limit: RecommendationEngine::MAX_MEMBER_CANDIDATES).items
        eligible_profiles = profile_scope.where(user_id: users.map(&:id)).includes(:interests).index_by(&:user_id)
        
        interest_ids = eligible_profiles.values.flat_map { |p| p.interests.map(&:tag_id) }
        visible_candidate_tags = visible_interest_tags.where(id: interest_ids).index_by(&:id)
        
        candidate_matches = users.each_with_object({}) do |candidate, matches|
          candidate_profile = eligible_profiles.fetch(candidate.id)
          candidate_names = candidate_profile.interests.filter_map do |interest|
            visible_candidate_tags[interest.tag_id]&.name
          end
          match = InterestCatalogue.match(viewer_names: viewer_tags.map(&:name), candidate_names: candidate_names)
          contribution_score = [contributions.fetch(candidate.id, []).length, 3].min
          next if match.score.zero? && contribution_score.zero?

          matches[candidate.id] = { match: match, contribution_score: contribution_score }
        end

        dismissed_ids = WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id, target_type: "user"
        ).pluck(:target_id)
        
        selected_candidates = users
          .select { |candidate| candidate_matches.key?(candidate.id) }
          .reject { |candidate| dismissed_ids.include?(candidate.id) }
          .sort_by do |candidate|
            candidate_profile = eligible_profiles.fetch(candidate.id)
            candidate_match = candidate_matches.fetch(candidate.id)
            [
              -candidate_match.fetch(:match).score,
              -candidate_match.fetch(:contribution_score),
              -purpose_complement_score(profile.purpose, candidate_profile.purpose),
              -candidate.last_seen_at.to_i,
              diversity_key(candidate.id)
            ]
          end
          .then { |candidates| refresh_record_candidates(candidates) }
          .first([limit, RecommendationEngine::MAX_USERS].min)

        latest_dynamics = include_optional_details ? latest_member_dynamics(selected_candidates) : {}

        # Preload UserTags for all selected candidates to prevent N+1 queries
        user_tags_lookup = if include_optional_details
                             preload_user_tags(selected_candidates)
                           else
                             {}
                           end

        # Preload PracticeInvitations for all selected candidates to prevent N+1 queries
        invitation_tags_lookup = if include_optional_details
                                   preload_invitation_tags(selected_candidates)
                                 else
                                   {}
                                 end

        selected_candidates.each_with_index.map do |candidate, index|
          candidate_match = candidate_matches.fetch(candidate.id)
          {
            candidate: candidate,
            contributions: contributions.fetch(candidate.id, []),
            viewer_tags: viewer_tags,
            match: candidate_match.fetch(:match),
            candidate_source: member_candidate_source(candidate_match),
            rank: index + 1,
            latest_dynamic: latest_dynamics[candidate.id],
            invitation_tags: invitation_tags_lookup[candidate.id] || [],
            user_tags: user_tags_lookup[candidate.id] || [],
            include_optional_details: include_optional_details
          }
        end
      end

      private

      def preload_user_tags(candidates)
        # Instead of calling UserTagVisibility.public_tags_for in a loop, we fetch in bulk.
        # This prevents N+1 queries for user tags.
        UserTagVisibility.bulk_public_tags_for(candidates, viewer: @user)
      end

      def preload_invitation_tags(candidates)
        # Bulk eligibility check to prevent N+1
        PracticeInvitationEligibility.bulk_common_interests(sender: @user, recipients: candidates)
      end

      def contribution_topics(topics)
        topics_by_id = topics.index_by(&:id)
        contributions = Hash.new { |hash, user_id| hash[user_id] = [] }

        Post.where(topic_id: topics_by_id.keys, post_type: Post.types[:regular])
          .where(deleted_at: nil)
          .where.not(user_id: Discourse.system_user.id)
          .visible
          .secured(@guardian)
          .pluck("posts.user_id", "posts.topic_id")
          .each do |user_id, topic_id|
            topic = topics_by_id[topic_id]
            next if topic.blank?
            next if contributions[user_id].any? { |entry| entry.id == topic_id }

            contributions[user_id] << topic
          end

        contributions.delete(@user.id)
        contributions
      end

      def purpose_complement_score(viewer_purpose, candidate_purpose)
        if RecommendationEngine::COMPLEMENTARY_PURPOSES.fetch(viewer_purpose, []).include?(candidate_purpose)
          1
        else
          0
        end
      end

      def refresh_record_candidates(candidates)
        refresh_candidates(candidates, pool_size: RecommendationEngine::REFRESH_MEMBER_POOL, &:id)
      end

      def latest_member_dynamics(candidates)
        unless SiteSetting.where_is_my_friends_dynamics_member_preview_enabled
          return {}
        end
        DynamicFeed.new(viewer: @user).latest_by_user_ids(candidates.map(&:id))
      rescue Discourse::NotFound
        {}
      end

      def member_candidate_source(candidate_match)
        if candidate_match.fetch(:match).score.positive?
          "interest"
        else
          "relationship_bridge"
        end
      end
    end
  end
end

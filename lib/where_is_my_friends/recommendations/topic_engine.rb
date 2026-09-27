# frozen_string_literal: true

module WhereIsMyFriends
  module Recommendations
    class TopicEngine < Base
      def call(profile:)
        selected_tags = profile_interest_tags(profile)
        return [] if selected_tags.empty?

        dismissed_ids = WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id, target_type: "topic"
        ).pluck(:target_id)

        scored_topic_candidates(profile)
          .reject { |topic, _matches, _score| dismissed_ids.include?(topic.id) }
          .then { |candidates| refresh_topic_candidates(candidates) }
          .then { |candidates| mixed_topic_candidates(candidates) }
      end

      # Used by other engines
      def scored_topic_candidates(profile)
        return @scored_topic_candidates if defined?(@scored_topic_candidates)

        selected_tags = profile_interest_tags(profile)
        if selected_tags.empty?
          @scored_topic_candidates = []
          return @scored_topic_candidates
        end

        query_names = InterestCatalogue.topic_query_names(selected_tags.map(&:name))
        latest = TopicQuery.new(@user, per_page: RecommendationEngine::MAX_TOPIC_CANDIDATES).list_latest.topics
        tagged = query_names.empty? ? [] : TopicQuery.new(@user, per_page: RecommendationEngine::MAX_TOPIC_CANDIDATES, tags: query_names).list_latest.topics
        raw_candidates = (latest + tagged).uniq(&:id).reject do |topic|
          relationship_exclusions.include?(topic.user_id) || topic.tags.any? { |tag| muted_tag_ids.include?(tag.id) }
        end.filter_map do |topic|
          matches = InterestCatalogue.topic_matches(topic: topic, selected_tags: selected_tags)
          next if matches.empty?
          [topic, matches]
        end
        @candidate_topics = raw_candidates.map(&:first)
        @scored_topic_candidates = raw_candidates.map do |topic, matches|
          [topic, matches, topic_recommendation_score(topic, matches)]
        end.sort_by do |topic, _matches, score|
          [-score, -topic.bumped_at.to_i, -topic.like_count.to_i, diversity_key(topic.id)]
        end
      end

      def candidate_topics
        @candidate_topics || []
      end
      
      def topic_candidate_source(topic, matches)
        if matches.all? { |_tag, score| score == 1 }
          "exploration"
        elsif behavior_relevant?(topic)
          "behavior"
        elsif relationship_bridge_author_ids.include?(topic.user_id)
          "relationship_bridge"
        else
          "interest"
        end
      end

      def participation_state(topic)
        return "participated" if viewer_replied?(topic)
        return "awaiting_response" if awaiting_response?(topic)
        return "unread" if topic_unread?(topic)
        "active"
      end

      def awaiting_response?(topic)
        topic.created_at >= 72.hours.ago && topic.posts_count.to_i <= 2
      end

      def viewer_replied?(topic)
        viewer_replied_topic_ids.include?(topic.id)
      end

      def topic_unread?(topic)
        return false if viewer_replied?(topic)
        topic_user = topic_user_lookup[topic.id]
        topic_user.blank? || topic_user.last_read_post_number.to_i < topic.highest_post_number.to_i
      end

      def author_active?(topic)
        active_author_ids.include?(topic.user_id)
      end

      private

      def topic_recommendation_score(topic, matches)
        match_score = matches.sum(&:last)
        exact_interest = [match_score.to_f / 18, 1.0].min
        score = RecommendationEngine::TOPIC_WEIGHTS.fetch(:interest) * exact_interest
        score += RecommendationEngine::TOPIC_WEIGHTS.fetch(:behavior) if behavior_relevant?(topic)
        score += RecommendationEngine::TOPIC_WEIGHTS.fetch(:participation) * participation_value(topic)
        score += RecommendationEngine::TOPIC_WEIGHTS.fetch(:freshness) * freshness_value(topic)
        score += RecommendationEngine::TOPIC_WEIGHTS.fetch(:relationship_bridge) if relationship_bridge_author_ids.include?(topic.user_id)
        score += RecommendationEngine::TOPIC_WEIGHTS.fetch(:new_member) if new_member_author_ids.include?(topic.user_id)
        score += RecommendationEngine::TOPIC_WEIGHTS.fetch(:exploration) if matches.all? { |_tag, match| match == 1 }
        score += 3 if topic.title.to_s.match?(RecommendationEngine::OPEN_DISCUSSION_PATTERN)
        score -= 24 if viewer_replied?(topic)
        score -= 10 unless topic_unread?(topic) || viewer_replied?(topic)
        score -= repeated_view_penalty(topic)
        score -= same_author_concentration_penalty(topic)
        score -= 12 if topic.created_at < 30.days.ago && topic.posts_count.to_i <= 1
        score
      end

      def same_author_concentration_penalty(topic)
        duplicate_count = candidate_topic_count_by_author.fetch(topic.user_id, 1) - 1
        [duplicate_count, 3].min * 4
      end

      def repeated_view_penalty(topic)
        viewed_msecs = topic_user_lookup[topic.id]&.total_msecs_viewed.to_i
        return 12 if viewed_msecs >= 20.minutes.in_milliseconds
        return 8 if viewed_msecs >= 5.minutes.in_milliseconds
        0
      end

      def candidate_topic_count_by_author
        @candidate_topic_count_by_author ||= candidate_topics.group_by(&:user_id).transform_values(&:length)
      end

      def participation_value(topic)
        return 0.0 if viewer_replied?(topic)
        return 1.0 if awaiting_response?(topic) && author_active?(topic)
        return 0.85 if topic_unread?(topic) && author_active?(topic)
        return 0.6 if topic_unread?(topic)
        author_active?(topic) ? 0.35 : 0.1
      end

      def freshness_value(topic)
        return 1.0 if topic.created_at >= 72.hours.ago
        return 0.7 if topic.created_at >= 1.week.ago
        return 0.3 if topic.created_at >= 30.days.ago
        0.0
      end

      def behavior_relevant?(topic)
        (topic.tags.map(&:name) & recent_behavior_tag_names).present?
      end

      def recent_behavior_tag_names
        @recent_behavior_tag_names ||= Tag.joins(:topic_tags).where(topic_tags: { topic_id: recent_behavior_topic_ids }).distinct.pluck(:name)
      end

      def recent_behavior_topic_ids
        @recent_behavior_topic_ids ||= begin
          visited = TopicUser.where(user_id: @user.id, last_visited_at: RecommendationEngine::RECENT_BEHAVIOR_WINDOW.ago..).order(last_visited_at: :desc).limit(RecommendationEngine::MAX_TOPIC_CANDIDATES).pluck(:topic_id)
          replied = Post.where(user_id: @user.id, created_at: RecommendationEngine::RECENT_BEHAVIOR_WINDOW.ago.., post_type: Post.types[:regular]).where(deleted_at: nil).order(created_at: :desc).limit(RecommendationEngine::MAX_TOPIC_CANDIDATES).pluck(:topic_id)
          liked = PostAction.joins(:post).where(user_id: @user.id, post_action_type_id: PostActionType.types[:like], created_at: RecommendationEngine::RECENT_BEHAVIOR_WINDOW.ago..).where(deleted_at: nil, posts: { deleted_at: nil }).order(created_at: :desc).limit(RecommendationEngine::MAX_TOPIC_CANDIDATES).pluck("posts.topic_id")
          (visited + replied + liked).uniq
        end
      end

      def relationship_bridge_author_ids
        @relationship_bridge_author_ids ||= begin
          shared_topic_ids = Post.where(user_id: @user.id, created_at: RecommendationEngine::MEMBER_ACTIVE_WINDOW.ago.., post_type: Post.types[:regular]).where(deleted_at: nil).distinct.pluck(:topic_id)
          if shared_topic_ids.empty?
            []
          else
            Post.where(topic_id: shared_topic_ids, user_id: candidate_topics.map(&:user_id), post_type: Post.types[:regular]).where(deleted_at: nil).visible.secured(@guardian).distinct.pluck(:user_id)
          end
        end
      end

      def new_member_author_ids
        @new_member_author_ids ||= User.where(id: candidate_topics.map(&:user_id), created_at: 30.days.ago..).pluck(:id)
      end

      def mixed_topic_candidates(candidates)
        waiting = candidates.find { |topic, _matches, _score| awaiting_response?(topic) }
        exploration = candidates.find do |topic, matches, _score|
          matches.all? { |_tag, score| score == 1 } && topic != waiting&.first
        end
        reserved = [waiting, exploration].compact
        selected = candidates.reject { |candidate| reserved.include?(candidate) }.first(3)
        selected.concat(reserved)
        candidates.each do |candidate|
          break if selected.length >= RecommendationEngine::MAX_TOPICS
          selected << candidate if selected.exclude?(candidate)
        end
        cap_licensed_imports(selected.compact + candidates)
      end

      def cap_licensed_imports(candidates)
        unique = candidates.uniq { |candidate| candidate.first.id }
        imported_ids = WhereIsMyFriendsLicensedImport.published.where(topic_id: unique.map { |candidate| candidate.first.id }).pluck(:topic_id).to_set
        imported_count = 0
        unique.each_with_object([]) do |candidate, selected|
          topic_id = candidate.first.id
          if imported_ids.include?(topic_id)
            next if imported_count >= 2
            imported_count += 1
          end
          selected << candidate
          break selected if selected.length >= RecommendationEngine::MAX_TOPICS
        end
      end

      def refresh_topic_candidates(candidates)
        refresh_candidates(candidates, pool_size: RecommendationEngine::REFRESH_TOPIC_POOL) { |candidate| candidate.first.id }
      end

      def viewer_replied_topic_ids
        @viewer_replied_topic_ids ||= Post.where(user_id: @user.id, topic_id: candidate_topics.map(&:id), post_type: Post.types[:regular], post_number: 2..).where(deleted_at: nil).distinct.pluck(:topic_id)
      end

      def topic_user_lookup
        @topic_user_lookup ||= TopicUser.lookup_for(@user, candidate_topics)
      end

      def active_author_ids
        @active_author_ids ||= User.where(id: candidate_topics.map(&:user_id)).where("last_seen_at >= ?", 30.days.ago).pluck(:id)
      end
    end
  end
end

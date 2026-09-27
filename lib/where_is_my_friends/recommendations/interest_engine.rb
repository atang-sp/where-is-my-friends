# frozen_string_literal: true

module WhereIsMyFriends
  module Recommendations
    class InterestEngine < Base
      def initialize(user:, guardian:, diversity_seed: nil, topic_engine:)
        super(user: user, guardian: guardian, diversity_seed: diversity_seed)
        @topic_engine = topic_engine
      end

      def call(profile:)
        selected_tags = profile_interest_tags(profile)
        return [] if selected_tags.empty?

        dismissed_ids = WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id, target_type: "interest"
        ).pluck(:target_id)

        scored_candidates = @topic_engine.scored_topic_candidates(profile)
        exact_entries = selected_tags
          .reject { |tag| dismissed_ids.include?(tag.id) }
          .filter_map do |tag|
            matching_candidates = scored_candidates.select do |_topic, matches, _score|
              matches.any? { |matched_tag, _match_score| matched_tag.id == tag.id }
            end
            { tag: tag, candidates: matching_candidates, candidate_source: "interest" }
          end
          .sort_by { |entry| interest_entrance_sort_key(entry[:candidates]) }
          .then { |entries| refresh_hash_candidates(entries) }

        selected_by_name = selected_tags.index_by(&:name)
        exploration_candidates = InterestCatalogue.exploration_candidates(selected_by_name.keys)
        exploration_tags = visible_interest_tags.where(name: exploration_candidates.pluck(:name)).index_by(&:name)
        exploration_entries = exploration_candidates
          .filter_map do |candidate|
            tag = exploration_tags[candidate.fetch(:name)]
            next if tag.blank? || dismissed_ids.include?(tag.id)

            matching_candidates = scored_candidates.select do |topic, _matches, _score|
              topic.tags.any? { |topic_tag| topic_tag.id == tag.id }
            end
            {
              tag: tag,
              candidates: matching_candidates,
              candidate_source: "exploration",
              reason_tag: selected_by_name[candidate.fetch(:reason_name)]
            }
          end
          .sort_by { |entry| interest_entrance_sort_key(entry[:candidates]) }
          .then { |entries| refresh_hash_candidates(entries) }

        entries = [exact_entries.first, exploration_entries.first].compact
        (exact_entries.drop(1) + exploration_entries.drop(1)).each do |entry|
          break if entries.length >= RecommendationEngine::MAX_INTEREST_ENTRANCES
          entries << entry
        end
        entries.first(RecommendationEngine::MAX_INTEREST_ENTRANCES)
      end

      private

      def interest_entrance_sort_key(candidates)
        topics = candidates.map(&:first).uniq(&:id)
        new_count = topics.count { |topic| topic.created_at >= 1.week.ago }
        [-topics.length, -new_count]
      end

      def refresh_hash_candidates(candidates)
        refresh_candidates(candidates, pool_size: RecommendationEngine::REFRESH_INTEREST_POOL) { |entry| entry.fetch(:tag).id }
      end
    end
  end
end

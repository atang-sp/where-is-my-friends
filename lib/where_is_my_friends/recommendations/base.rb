# frozen_string_literal: true

require "zlib"

module WhereIsMyFriends
  module Recommendations
    class Base
      def initialize(user:, guardian:, diversity_seed: nil)
        @user = user
        @guardian = guardian
        @diversity_seed = diversity_seed.to_s.first(32)
      end

      protected

      def diversity_key(candidate_id)
        Zlib.crc32("#{@user.id}:#{candidate_id}:#{Date.current.cweek}:#{@diversity_seed}")
      end

      def refresh_candidates(candidates, pool_size:)
        return candidates if @diversity_seed.blank? || candidates.length < 2
        pool = candidates.first(pool_size)
        pool.sort_by { |candidate| diversity_key(yield(candidate)) } + candidates.drop(pool_size)
      end

      def relationship_exclusions
        @relationship_exclusions ||= begin
          ignored = IgnoredUser.where(expiring_at: Time.current..).where("user_id = :user_id OR ignored_user_id = :user_id", user_id: @user.id).pluck(:user_id, :ignored_user_id).flatten
          muted = MutedUser.where("user_id = :user_id OR muted_user_id = :user_id", user_id: @user.id).pluck(:user_id, :muted_user_id).flatten
          (ignored + muted + [@user.id]).uniq
        end
      end

      def muted_tag_ids
        @muted_tag_ids ||= TagUser.lookup(@user, :muted).pluck(:tag_id)
      end

      def visible_interest_tags
        DiscourseTagging.visible_tags(@guardian).where.not(id: muted_tag_ids)
      end

      def profile_interest_tags(profile)
        @profile_interest_tags ||= begin
          interests = profile.interests.to_a
          visible = visible_interest_tags.where(id: interests.map(&:tag_id)).index_by(&:id)
          interests.filter_map { |interest| visible[interest.tag_id] }
        end
      end
      def current_interest_tag_ids
        @current_interest_tag_ids ||= WhereIsMyFriendsUserInterest.where(user_id: @user.id).pluck(:tag_id)
      end

      def configured_interest_tags
        @configured_interest_tags ||= visible_interest_tags.where(name: RecommendationEngine.new(@user).send(:configured_interest_names)).to_a
      end
    end
  end
end

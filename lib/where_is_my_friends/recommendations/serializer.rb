# frozen_string_literal: true

module WhereIsMyFriends
  module Recommendations
    class Serializer
      def initialize(user, guardian = nil)
        @user = user
        @guardian = guardian || Guardian.new(user)
      end

      def serialize_profile(profile, interest_tags = nil)
        tags = interest_tags || []
        {
          purpose: profile.purpose,
          personalization_enabled: profile.personalization_enabled?,
          recommendable: profile.recommendable?,
          show_interests_publicly: profile.show_interests_publicly?,
          interests: tags.map { |tag| serialize_tag(tag) }
        }
      end

      def serialize_catalogue_group(group)
        key = group.fetch("key")
        payload = {
          key: key,
          name: catalogue_group_translation(key, "name"),
          description: catalogue_group_translation(key, "description"),
          selection_mode: InterestCatalogue.group_selection_mode(group)
        }
        max = InterestCatalogue.group_max_per_group(group)
        payload[:max_per_group] = max if max
        payload
      end

      def serialize_catalogue_tag(tag, entry)
        group_key = entry["group_key"] || entry.fetch("key")
        payload =
          serialize_tag(tag).merge(
            group_key: group_key,
            group_name: catalogue_group_translation(group_key, "name")
          )
        aliases = Array(entry["aliases"])
        payload[:aliases] = aliases if aliases.present?
        payload
      end

      def catalogue_group_translation(group_key, field)
        I18n.t(
          "where_is_my_friends.interest_catalogue.groups.#{group_key}.#{field}"
        )
      end

      def serialize_tag(tag)
        { id: tag.id, name: tag.name }
      end

      def rank_bucket(rank)
        return "one_to_two" if rank <= 2
        return "three_to_five" if rank <= 5

        "six_plus"
      end

      def serialize_topic(topic, matches, rank: nil, context: nil)
        payload = {
          id: topic.id,
          title: topic.title,
          fancy_title: topic.fancy_title,
          slug: topic.slug,
          url: "/t/#{topic.slug}/#{topic.id}",
          posts_count: topic.posts_count,
          like_count: topic.like_count,
          bumped_at: topic.bumped_at,
          matching_interests:
            matches
              .sort_by { |_tag, score| -score }
              .map { |tag, _score| serialize_tag(tag) }
        }
        if rank
          participation_state =
            context ? context.participation_state(topic) : "none"
          unread = context ? context.topic_unread?(topic) : false
          viewer_replied = context ? context.viewer_replied?(topic) : false
          author_active = context ? context.author_active?(topic) : false
          candidate_source =
            context ? context.topic_candidate_source(topic, matches) : "interest"

          payload.merge!(
            participation_state: participation_state,
            unread: unread,
            viewer_replied: viewer_replied,
            author_active: author_active,
            reply_count: [topic.posts_count.to_i - 1, 0].max,
            candidate_source: candidate_source,
            rank: rank,
            rank_bucket: rank_bucket(rank)
          )
        end
        payload
      end

      def serialize_user(
        candidate,
        topics,
        viewer_tags,
        match,
        candidate_source:,
        rank:,
        latest_dynamic: nil,
        invitation_tags: nil,
        user_tags: nil,
        include_optional_details: true
      )
        representative_topics = topics.sort_by(&:bumped_at).reverse.first(2)
        public_reason_tags =
          representative_topics
            .flat_map do |topic|
              InterestCatalogue.topic_matches(
                topic: topic,
                selected_tags: viewer_tags
              ).map(&:first)
            end
            .uniq(&:id)
        private_match_reason_tags =
          viewer_tags.select { |tag| match.reason_names.include?(tag.name) }
        reason_tags =
          (public_reason_tags.presence || private_match_reason_tags).first(3)

        effective_invitation_tags =
          if invitation_tags
            invitation_tags
          elsif include_optional_details
            PracticeInvitationEligibility.new(
              sender: @user,
              recipient: candidate
            ).common_interests
          else
            []
          end

        effective_user_tags =
          user_tags ||
            UserTagVisibility.public_tags_for(candidate, viewer: @user)

        payload = {
          id: candidate.id,
          username: candidate.username,
          name: candidate.name,
          avatar_template: candidate.avatar_template,
          profile_url: "/u/#{candidate.username}",
          invite_url:
            (
              if effective_invitation_tags.present?
                "/where-is-my-friends/interests?invite_to=#{candidate.username}"
              end
            ),
          candidate_source: candidate_source,
          rank: rank,
          rank_bucket: rank_bucket(rank),
          bio_excerpt:
            candidate
              .user_profile
              &.bio_raw
              .to_s
              .gsub(/\s+/, " ")
              .strip
              .truncate(120)
              .presence,
          match_strength:
            match.score.positive? ? match.strength : "public_activity",
          reason_interests: reason_tags.map { |tag| serialize_tag(tag) },
          invitation_interests:
            effective_invitation_tags.map { |tag| serialize_tag(tag) },
          user_tags: effective_user_tags,
          representative_topics:
            representative_topics.map do |topic|
              serialize_topic(
                topic,
                InterestCatalogue.topic_matches(
                  topic: topic,
                  selected_tags: viewer_tags
                )
              )
            end
        }
        payload[:latest_dynamic] = latest_dynamic if latest_dynamic
        payload
      end

      def serialize_interest_entrance(
        tag,
        candidates,
        candidate_source:,
        reason_tag: nil
      )
        return if candidates.empty?

        topics = candidates.map(&:first).uniq(&:id)
        active_member_count = active_contributor_count(topics)
        protected_count =
          AggregatePrivacy.protect_counts(
            { active_member_count: active_member_count },
            :active_member_count
          )
        {
          id: tag.id,
          name: tag.name,
          url: tag.url,
          candidate_source: candidate_source,
          reason_interest: reason_tag && serialize_tag(reason_tag),
          topic_count: topics.length,
          new_topic_count:
            topics.count { |topic| topic.created_at >= 1.week.ago },
          active_member_count: protected_count[:active_member_count],
          active_member_count_suppressed:
            protected_count[:active_member_count_suppressed]
        }
      end

      def active_contributor_count(topics)
        author_ids =
          User
            .where(id: topics.map(&:user_id), last_seen_at: 30.days.ago..)
            .where.not(id: Discourse.system_user.id)
            .pluck(:id)
        contributor_ids =
          Post
            .where(
              topic_id: topics.map(&:id),
              post_type: Post.types[:regular],
              created_at: 30.days.ago..
            )
            .where(deleted_at: nil)
            .where.not(user_id: Discourse.system_user.id)
            .visible
            .secured(@guardian)
            .distinct
            .pluck(:user_id)

        (author_ids + contributor_ids).compact.uniq.length
      end
    end
  end
end

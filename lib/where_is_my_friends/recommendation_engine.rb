# frozen_string_literal: true

require "zlib"

module WhereIsMyFriends
  class RecommendationEngine
    MAX_CATALOGUE = 100
    MAX_CUSTOM_INTERESTS = 20
    MIN_INTERESTS = 3
    MAX_INTERESTS = 12
    MAX_TOPIC_CANDIDATES = 100
    MAX_TOPICS = 5
    MAX_USERS = 6
    MAX_MEMBER_CANDIDATES = 250
    MEMBER_ACTIVE_WINDOW = 90.days
    COMPLEMENTARY_PURPOSES = {
      "learn" => %w[share help],
      "share" => %w[learn ask],
      "connect" => %w[connect],
      "ask" => %w[help share],
      "help" => %w[ask learn],
      "browse" => []
    }.freeze

    def self.catalogue_for(user)
      new(user).catalogue
    end

    def initialize(user)
      @user = user
      @guardian = Guardian.new(user)
    end

    def call(profile:)
      {
        state: profile.state,
        catalogue: catalogue,
        catalogue_groups: catalogue_groups,
        selection_limits: {
          minimum: [MIN_INTERESTS, catalogue.length].min,
          maximum: MAX_INTERESTS
        },
        purposes: WhereIsMyFriendsInterestProfile::PURPOSES,
        profile: serialize_profile(profile),
        recommended_topics: recommended_topics(profile),
        recommended_users: recommended_users(profile)
      }
    end

    def catalogue
      @catalogue ||=
        begin
          visible_by_name =
            visible_interest_tags.where(name: InterestCatalogue.names).index_by(
              &:name
            )
          curated =
            InterestCatalogue.entries.filter_map do |entry|
              tag = visible_by_name[entry.fetch("name")]
              serialize_catalogue_tag(tag, entry) if tag
            end
          curated_ids = curated.pluck(:id)
          custom_tags =
            visible_interest_tags
              .where(
                id:
                  current_interest_tag_ids + configured_interest_tags.pluck(:id)
              )
              .where.not(id: curated_ids)
              .to_a
              .sort_by do |tag|
                configured_interest_names.index(tag.name) ||
                  current_interest_tag_ids.index(tag.id) || MAX_CUSTOM_INTERESTS
              end
          custom =
            custom_tags
              .first(MAX_CUSTOM_INTERESTS)
              .map do |tag|
                serialize_catalogue_tag(tag, InterestCatalogue::COMMUNITY_GROUP)
              end

          (curated + custom).first(MAX_CATALOGUE)
        end
    end

    private

    def configured_interest_names
      SiteSetting
        .where_is_my_friends_interest_tags
        .to_s
        .split("|")
        .map(&:strip)
        .reject(&:blank?)
        .uniq
        .first(MAX_CUSTOM_INTERESTS)
    end

    def configured_interest_tags
      @configured_interest_tags ||=
        visible_interest_tags.where_name(configured_interest_names).to_a
    end

    def current_interest_tag_ids
      @current_interest_tag_ids ||=
        WhereIsMyFriendsUserInterest.where(user_id: @user.id).pluck(:tag_id)
    end

    def catalogue_groups
      present_keys = catalogue.pluck(:group_key)
      groups =
        InterestCatalogue.groups.filter_map do |group|
          if present_keys.include?(group["key"])
            serialize_catalogue_group(group)
          end
        end
      if present_keys.include?(InterestCatalogue::COMMUNITY_GROUP["key"])
        groups << serialize_catalogue_group(InterestCatalogue::COMMUNITY_GROUP)
      end
      groups
    end

    def serialize_profile(profile)
      {
        purpose: profile.purpose,
        personalization_enabled: profile.personalization_enabled?,
        recommendable: profile.recommendable?,
        show_interests_publicly: profile.show_interests_publicly?,
        interests:
          profile_interest_tags(profile).map { |tag| serialize_tag(tag) }
      }
    end

    def recommended_topics(profile)
      return [] if profile_interest_tags(profile).empty?

      dismissed_ids =
        WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id,
          target_type: "topic"
        ).pluck(:target_id)

      scored_topic_candidates(profile)
        .reject { |topic, _matches, _score| dismissed_ids.include?(topic.id) }
        .first(MAX_TOPICS)
        .map { |topic, matches, _score| serialize_topic(topic, matches) }
    end

    def recommended_users(profile)
      viewer_tags = profile_interest_tags(profile)
      return [] if viewer_tags.empty?

      topics = scored_topic_candidates(profile).map(&:first)
      contributions = contribution_topics(topics)
      similar_tag_ids =
        visible_interest_tags.where(
          name:
            InterestCatalogue.member_candidate_names(viewer_tags.map(&:name))
        ).select(:id)
      matching_profile_ids =
        WhereIsMyFriendsUserInterest.where(tag_id: similar_tag_ids).select(
          :user_id
        )
      base_profile_scope =
        WhereIsMyFriendsInterestProfile
          .where(personalization_enabled: true, recommendable: true)
          .where.not(completed_at: nil)
          .where.not(user_id: relationship_exclusions)
      profile_scope =
        base_profile_scope.where(user_id: matching_profile_ids).or(
          base_profile_scope.where(user_id: contributions.keys)
        )
      excluded_ids = relationship_exclusions
      users =
        User
          .where(id: profile_scope.select(:user_id))
          .activated
          .not_staged
          .not_suspended
          .not_silenced
          .where("last_seen_at >= ?", MEMBER_ACTIVE_WINDOW.ago)
          .where.not(id: excluded_ids)
          .includes(:user_profile, :user_option, :user_stat)
          .order(last_seen_at: :desc)
          .limit(MAX_MEMBER_CANDIDATES)
          .select { |candidate| @guardian.can_see_profile?(candidate) }
      eligible_profiles =
        profile_scope
          .where(user_id: users.map(&:id))
          .includes(:interests)
          .index_by(&:user_id)
      interest_ids =
        eligible_profiles.values.flat_map do |candidate_profile|
          candidate_profile.interests.map(&:tag_id)
        end
      visible_candidate_tags =
        visible_interest_tags.where(id: interest_ids).index_by(&:id)
      candidate_matches =
        users.each_with_object({}) do |candidate, matches|
          candidate_profile = eligible_profiles.fetch(candidate.id)
          candidate_names =
            candidate_profile.interests.filter_map do |interest|
              visible_candidate_tags[interest.tag_id]&.name
            end
          match =
            InterestCatalogue.match(
              viewer_names: viewer_tags.map(&:name),
              candidate_names: candidate_names
            )
          contribution_score = [
            contributions.fetch(candidate.id, []).length,
            3
          ].min
          next if match.score.zero? && contribution_score.zero?

          matches[candidate.id] = {
            match: match,
            contribution_score: contribution_score
          }
        end

      dismissed_ids =
        WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id,
          target_type: "user"
        ).pluck(:target_id)
      users
        .select { |candidate| candidate_matches.key?(candidate.id) }
        .reject { |candidate| dismissed_ids.include?(candidate.id) }
        .sort_by do |candidate|
          candidate_profile = eligible_profiles.fetch(candidate.id)
          candidate_match = candidate_matches.fetch(candidate.id)
          [
            -candidate_match.fetch(:match).score,
            -candidate_match.fetch(:contribution_score),
            -purpose_complement_score(
              profile.purpose,
              candidate_profile.purpose
            ),
            -candidate.last_seen_at.to_i,
            diversity_key(candidate.id)
          ]
        end
        .first(MAX_USERS)
        .map do |candidate|
          serialize_user(
            candidate,
            contributions.fetch(candidate.id, []),
            viewer_tags,
            candidate_matches.fetch(candidate.id).fetch(:match)
          )
        end
    end

    def scored_topic_candidates(profile)
      return @scored_topic_candidates if defined?(@scored_topic_candidates)

      selected_tags = profile_interest_tags(profile)
      if selected_tags.empty?
        @scored_topic_candidates = []
        return @scored_topic_candidates
      end

      query_names =
        InterestCatalogue.topic_query_names(selected_tags.map(&:name))
      latest =
        TopicQuery.new(@user, per_page: MAX_TOPIC_CANDIDATES).list_latest.topics
      tagged =
        if query_names.empty?
          []
        else
          TopicQuery
            .new(@user, per_page: MAX_TOPIC_CANDIDATES, tags: query_names)
            .list_latest
            .topics
        end
      @scored_topic_candidates =
        (latest + tagged)
          .uniq(&:id)
          .reject do |topic|
            relationship_exclusions.include?(topic.user_id) ||
              topic.tags.any? { |tag| muted_tag_ids.include?(tag.id) }
          end
          .filter_map do |topic|
            matches =
              InterestCatalogue.topic_matches(
                topic: topic,
                selected_tags: selected_tags
              )
            next if matches.empty?

            [topic, matches, matches.sum(&:last)]
          end
          .sort_by do |topic, _matches, score|
            [-score, -topic.bumped_at.to_i, -topic.like_count.to_i]
          end
    end

    def contribution_topics(topics)
      topics_by_id = topics.index_by(&:id)
      contributions = Hash.new { |hash, user_id| hash[user_id] = [] }

      Post
        .where(topic_id: topics_by_id.keys, post_type: Post.types[:regular])
        .where(deleted_at: nil)
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

    def relationship_exclusions
      @relationship_exclusions ||=
        begin
          ignored =
            IgnoredUser
              .where(expiring_at: Time.current..)
              .where(
                "user_id = :user_id OR ignored_user_id = :user_id",
                user_id: @user.id
              )
              .pluck(:user_id, :ignored_user_id)
              .flatten
          muted =
            MutedUser
              .where(
                "user_id = :user_id OR muted_user_id = :user_id",
                user_id: @user.id
              )
              .pluck(:user_id, :muted_user_id)
              .flatten

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
      @profile_interest_tags ||=
        begin
          interests = profile.interests.to_a
          visible =
            visible_interest_tags.where(id: interests.map(&:tag_id)).index_by(
              &:id
            )
          interests.filter_map { |interest| visible[interest.tag_id] }
        end
    end

    def purpose_complement_score(viewer_purpose, candidate_purpose)
      if COMPLEMENTARY_PURPOSES.fetch(viewer_purpose, []).include?(
           candidate_purpose
         )
        1
      else
        0
      end
    end

    def diversity_key(candidate_id)
      Zlib.crc32("#{@user.id}:#{candidate_id}:#{Date.current.cweek}")
    end

    def serialize_topic(topic, matches)
      {
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
    end

    def serialize_user(candidate, topics, viewer_tags, match)
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
      invitation_tags =
        PracticeInvitationEligibility.new(
          sender: @user,
          recipient: candidate
        ).common_interests

      {
        id: candidate.id,
        username: candidate.username,
        name: candidate.name,
        avatar_template: candidate.avatar_template,
        profile_url: "/u/#{candidate.username}",
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
        invitation_interests: invitation_tags.map { |tag| serialize_tag(tag) },
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
    end

    def serialize_catalogue_group(group)
      key = group.fetch("key")
      {
        key: key,
        name: catalogue_group_translation(key, "name"),
        description: catalogue_group_translation(key, "description")
      }
    end

    def serialize_catalogue_tag(tag, entry)
      group_key = entry["group_key"] || entry.fetch("key")

      serialize_tag(tag).merge(
        group_key: group_key,
        group_name: catalogue_group_translation(group_key, "name")
      )
    end

    def catalogue_group_translation(group_key, field)
      I18n.t(
        "where_is_my_friends.interest_catalogue.groups.#{group_key}.#{field}"
      )
    end

    def serialize_tag(tag)
      { id: tag.id, name: tag.name }
    end
  end
end

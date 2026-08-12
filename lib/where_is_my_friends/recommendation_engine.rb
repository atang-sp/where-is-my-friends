# frozen_string_literal: true

require "zlib"

module WhereIsMyFriends
  class RecommendationEngine
    MAX_CATALOGUE = 100
    MAX_CUSTOM_INTERESTS = 20
    MIN_INTERESTS = 3
    MAX_INTERESTS = 20
    MAX_TOPIC_CANDIDATES = 100
    MAX_TOPICS = 5
    MAX_USERS = 6
    REFRESH_TOPIC_POOL = 12
    REFRESH_MEMBER_POOL = 12
    REFRESH_INTEREST_POOL = 6
    MAX_INTEREST_ENTRANCES = 2
    MAX_MEMBER_CANDIDATES = 250
    MEMBER_ACTIVE_WINDOW = 90.days
    RECENT_BEHAVIOR_WINDOW = 30.days
    ALGORITHM_VERSION = "participation_v1"
    GROUP_METHODS = {
      "topics" => :recommended_topics,
      "people" => :recommended_users,
      "interests" => :recommended_interests
    }.freeze
    TOPIC_WEIGHTS = {
      interest: 32,
      behavior: 18,
      participation: 18,
      freshness: 12,
      relationship_bridge: 10,
      new_member: 5,
      exploration: 5
    }.freeze
    OPEN_DISCUSSION_PATTERN = /[?？]|求助|请问|经验|分享|help|how|what|why/i
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

    def initialize(user, diversity_seed: nil, guardian: nil)
      @user = user
      @guardian = guardian || Guardian.new(user)
      @member_selection =
        ViewerAwareMemberSelection.new(viewer: user, guardian: @guardian)
      @diversity_seed = diversity_seed.to_s.first(32)
    end

    def call(profile:, group: nil)
      group = group.to_s.presence
      return full_payload(profile) if group.blank?

      method_name = GROUP_METHODS.fetch(group)
      {
        :algorithm_version => ALGORITHM_VERSION,
        :state => profile.state,
        :recommendation_group => group,
        method_name => send(method_name, profile)
      }
    end

    def first_recommended_user(profile:)
      recommended_users(
        profile,
        limit: 1,
        include_optional_details: false
      ).first
    end

    def full_payload(profile)
      {
        algorithm_version: ALGORITHM_VERSION,
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
        recommended_users: recommended_users(profile),
        recommended_interests: recommended_interests(profile)
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
        .then { |candidates| refresh_topic_candidates(candidates) }
        .then { |candidates| mixed_topic_candidates(candidates) }
        .each_with_index
        .map do |(topic, matches, _score), index|
          serialize_topic(topic, matches, rank: index + 1)
        end
    end

    def recommended_users(
      profile,
      limit: MAX_USERS,
      include_optional_details: true
    )
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
      user_scope =
        ViewerAwareMemberSelection
          .eligible_users(User.where(id: profile_scope.select(:user_id)))
          .where("last_seen_at >= ?", MEMBER_ACTIVE_WINDOW.ago)
          .where.not(id: excluded_ids)
          .includes(:user_profile, :user_option, :user_stat)
          .order(last_seen_at: :desc)
      users =
        @member_selection.select(
          scope: user_scope,
          limit: MAX_MEMBER_CANDIDATES
        ).items
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
      selected_candidates =
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
          .then { |candidates| refresh_record_candidates(candidates) }
          .first([limit, MAX_USERS].min)
      latest_dynamics =
        if include_optional_details
          latest_member_dynamics(selected_candidates)
        else
          {}
        end

      selected_candidates.each_with_index.map do |candidate, index|
        candidate_match = candidate_matches.fetch(candidate.id)
        serialize_user(
          candidate,
          contributions.fetch(candidate.id, []),
          viewer_tags,
          candidate_match.fetch(:match),
          candidate_source: member_candidate_source(candidate_match),
          rank: index + 1,
          latest_dynamic: latest_dynamics[candidate.id],
          include_optional_details: include_optional_details
        )
      end
    end

    def recommended_interests(profile)
      selected_tags = profile_interest_tags(profile)
      return [] if selected_tags.empty?

      dismissed_ids =
        WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id,
          target_type: "interest"
        ).pluck(:target_id)

      scored_candidates = scored_topic_candidates(profile)
      exact_entries =
        selected_tags
          .reject { |tag| dismissed_ids.include?(tag.id) }
          .filter_map do |tag|
            matching_candidates =
              scored_candidates.select do |_topic, matches, _score|
                matches.any? do |matched_tag, _match_score|
                  matched_tag.id == tag.id
                end
              end
            serialize_interest_entrance(
              tag,
              matching_candidates,
              candidate_source: "interest"
            )
          end
          .sort_by { |entry| interest_entrance_sort_key(entry) }
          .then { |entries| refresh_hash_candidates(entries) }
      selected_by_name = selected_tags.index_by(&:name)
      exploration_candidates =
        InterestCatalogue.exploration_candidates(selected_by_name.keys)
      exploration_tags =
        visible_interest_tags.where(
          name: exploration_candidates.pluck(:name)
        ).index_by(&:name)
      exploration_entries =
        exploration_candidates
          .filter_map do |candidate|
            tag = exploration_tags[candidate.fetch(:name)]
            next if tag.blank? || dismissed_ids.include?(tag.id)

            matching_candidates =
              scored_candidates.select do |topic, _matches, _score|
                topic.tags.any? { |topic_tag| topic_tag.id == tag.id }
              end
            serialize_interest_entrance(
              tag,
              matching_candidates,
              candidate_source: "exploration",
              reason_tag: selected_by_name[candidate.fetch(:reason_name)]
            )
          end
          .sort_by { |entry| interest_entrance_sort_key(entry) }
          .then { |entries| refresh_hash_candidates(entries) }

      entries = [exact_entries.first, exploration_entries.first].compact
      (exact_entries.drop(1) + exploration_entries.drop(1)).each do |entry|
        break if entries.length >= MAX_INTEREST_ENTRANCES
        entries << entry
      end
      entries
        .first(MAX_INTEREST_ENTRANCES)
        .each_with_index
        .map do |entry, index|
          entry.merge(rank: index + 1, rank_bucket: rank_bucket(index + 1))
        end
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

    def interest_entrance_sort_key(entry)
      [-entry.fetch(:topic_count), -entry.fetch(:new_topic_count)]
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
      raw_candidates =
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

            [topic, matches]
          end
      @candidate_topics = raw_candidates.map(&:first)
      @scored_topic_candidates =
        raw_candidates
          .map do |topic, matches|
            [topic, matches, topic_recommendation_score(topic, matches)]
          end
          .sort_by do |topic, _matches, score|
            [
              -score,
              -topic.bumped_at.to_i,
              -topic.like_count.to_i,
              diversity_key(topic.id)
            ]
          end
    end

    def topic_recommendation_score(topic, matches)
      match_score = matches.sum(&:last)
      exact_interest = [match_score.to_f / 18, 1.0].min
      score = TOPIC_WEIGHTS.fetch(:interest) * exact_interest
      score += TOPIC_WEIGHTS.fetch(:behavior) if behavior_relevant?(topic)
      score += TOPIC_WEIGHTS.fetch(:participation) * participation_value(topic)
      score += TOPIC_WEIGHTS.fetch(:freshness) * freshness_value(topic)
      if relationship_bridge_author_ids.include?(topic.user_id)
        score += TOPIC_WEIGHTS.fetch(:relationship_bridge)
      end
      score +=
        TOPIC_WEIGHTS.fetch(:new_member) if new_member_author_ids.include?(
        topic.user_id
      )
      score += TOPIC_WEIGHTS.fetch(:exploration) if matches.all? { |_tag, match|
        match == 1
      }
      score += 3 if topic.title.to_s.match?(OPEN_DISCUSSION_PATTERN)
      score -= 24 if viewer_replied?(topic)
      score -= 10 unless topic_unread?(topic) || viewer_replied?(topic)
      score -= repeated_view_penalty(topic)
      score -= same_author_concentration_penalty(topic)
      score -= 12 if topic.created_at < 30.days.ago &&
        topic.posts_count.to_i <= 1
      score
    end

    def same_author_concentration_penalty(topic)
      duplicate_count =
        candidate_topic_count_by_author.fetch(topic.user_id, 1) - 1
      [duplicate_count, 3].min * 4
    end

    def repeated_view_penalty(topic)
      viewed_msecs = topic_user_lookup[topic.id]&.total_msecs_viewed.to_i
      return 12 if viewed_msecs >= 20.minutes.in_milliseconds
      return 8 if viewed_msecs >= 5.minutes.in_milliseconds

      0
    end

    def candidate_topic_count_by_author
      @candidate_topic_count_by_author ||=
        candidate_topics.group_by(&:user_id).transform_values(&:length)
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
      @recent_behavior_tag_names ||=
        Tag
          .joins(:topic_tags)
          .where(topic_tags: { topic_id: recent_behavior_topic_ids })
          .distinct
          .pluck(:name)
    end

    def recent_behavior_topic_ids
      @recent_behavior_topic_ids ||=
        begin
          visited =
            TopicUser
              .where(
                user_id: @user.id,
                last_visited_at: RECENT_BEHAVIOR_WINDOW.ago..
              )
              .order(last_visited_at: :desc)
              .limit(MAX_TOPIC_CANDIDATES)
              .pluck(:topic_id)
          replied =
            Post
              .where(
                user_id: @user.id,
                created_at: RECENT_BEHAVIOR_WINDOW.ago..,
                post_type: Post.types[:regular]
              )
              .where(deleted_at: nil)
              .order(created_at: :desc)
              .limit(MAX_TOPIC_CANDIDATES)
              .pluck(:topic_id)
          liked =
            PostAction
              .joins(:post)
              .where(
                user_id: @user.id,
                post_action_type_id: PostActionType.types[:like],
                created_at: RECENT_BEHAVIOR_WINDOW.ago..
              )
              .where(deleted_at: nil, posts: { deleted_at: nil })
              .order(created_at: :desc)
              .limit(MAX_TOPIC_CANDIDATES)
              .pluck("posts.topic_id")

          (visited + replied + liked).uniq
        end
    end

    def relationship_bridge_author_ids
      @relationship_bridge_author_ids ||=
        begin
          shared_topic_ids =
            Post
              .where(
                user_id: @user.id,
                created_at: MEMBER_ACTIVE_WINDOW.ago..,
                post_type: Post.types[:regular]
              )
              .where(deleted_at: nil)
              .distinct
              .pluck(:topic_id)
          if shared_topic_ids.empty?
            []
          else
            Post
              .where(
                topic_id: shared_topic_ids,
                user_id: candidate_topics.map(&:user_id),
                post_type: Post.types[:regular]
              )
              .where(deleted_at: nil)
              .visible
              .secured(@guardian)
              .distinct
              .pluck(:user_id)
          end
        end
    end

    def new_member_author_ids
      @new_member_author_ids ||=
        User.where(
          id: candidate_topics.map(&:user_id),
          created_at: 30.days.ago..
        ).pluck(:id)
    end

    def mixed_topic_candidates(candidates)
      waiting =
        candidates.find { |topic, _matches, _score| awaiting_response?(topic) }
      exploration =
        candidates.find do |topic, matches, _score|
          matches.all? { |_tag, score| score == 1 } && topic != waiting&.first
        end
      reserved = [waiting, exploration].compact
      selected =
        candidates.reject { |candidate| reserved.include?(candidate) }.first(3)
      selected.concat(reserved)
      candidates.each do |candidate|
        break if selected.length >= MAX_TOPICS
        selected << candidate if selected.exclude?(candidate)
      end

      cap_licensed_imports(selected.compact + candidates)
    end

    def cap_licensed_imports(candidates)
      unique = candidates.uniq { |candidate| candidate.first.id }
      imported_ids =
        WhereIsMyFriendsLicensedImport
          .published
          .where(topic_id: unique.map { |candidate| candidate.first.id })
          .pluck(:topic_id)
          .to_set
      imported_count = 0
      unique.each_with_object([]) do |candidate, selected|
        topic_id = candidate.first.id
        if imported_ids.include?(topic_id)
          next if imported_count >= 2

          imported_count += 1
        end
        selected << candidate
        break selected if selected.length >= MAX_TOPICS
      end
    end

    def refresh_topic_candidates(candidates)
      refresh_candidates(
        candidates,
        pool_size: REFRESH_TOPIC_POOL
      ) { |candidate| candidate.first.id }
    end

    def refresh_record_candidates(candidates)
      refresh_candidates(candidates, pool_size: REFRESH_MEMBER_POOL, &:id)
    end

    def refresh_hash_candidates(candidates)
      refresh_candidates(
        candidates,
        pool_size: REFRESH_INTEREST_POOL
      ) { |entry| entry.fetch(:id) }
    end

    def refresh_candidates(candidates, pool_size:)
      return candidates if @diversity_seed.blank? || candidates.length < 2

      pool = candidates.first(pool_size)
      pool.sort_by { |candidate| diversity_key(yield(candidate)) } +
        candidates.drop(pool_size)
    end

    def contribution_topics(topics)
      topics_by_id = topics.index_by(&:id)
      contributions = Hash.new { |hash, user_id| hash[user_id] = [] }

      Post
        .where(topic_id: topics_by_id.keys, post_type: Post.types[:regular])
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
      Zlib.crc32(
        "#{@user.id}:#{candidate_id}:#{Date.current.cweek}:#{@diversity_seed}"
      )
    end

    def serialize_topic(topic, matches, rank: nil)
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
        payload.merge!(
          participation_state: participation_state(topic),
          unread: topic_unread?(topic),
          viewer_replied: viewer_replied?(topic),
          author_active: author_active?(topic),
          reply_count: [topic.posts_count.to_i - 1, 0].max,
          candidate_source: topic_candidate_source(topic, matches),
          rank: rank,
          rank_bucket: rank_bucket(rank)
        )
      end
      payload
    end

    def awaiting_response?(topic)
      topic.created_at >= 72.hours.ago && topic.posts_count.to_i <= 2
    end

    def participation_state(topic)
      return "participated" if viewer_replied?(topic)
      return "awaiting_response" if awaiting_response?(topic)
      return "unread" if topic_unread?(topic)

      "active"
    end

    def viewer_replied?(topic)
      viewer_replied_topic_ids.include?(topic.id)
    end

    def viewer_replied_topic_ids
      @viewer_replied_topic_ids ||=
        Post
          .where(
            user_id: @user.id,
            topic_id: candidate_topics.map(&:id),
            post_type: Post.types[:regular],
            post_number: 2..
          )
          .where(deleted_at: nil)
          .distinct
          .pluck(:topic_id)
    end

    def topic_unread?(topic)
      return false if viewer_replied?(topic)

      topic_user = topic_user_lookup[topic.id]
      topic_user.blank? ||
        topic_user.last_read_post_number.to_i < topic.highest_post_number.to_i
    end

    def topic_user_lookup
      @topic_user_lookup ||= TopicUser.lookup_for(@user, candidate_topics)
    end

    def author_active?(topic)
      active_author_ids.include?(topic.user_id)
    end

    def active_author_ids
      @active_author_ids ||=
        User
          .where(id: candidate_topics.map(&:user_id))
          .where("last_seen_at >= ?", 30.days.ago)
          .pluck(:id)
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

    def rank_bucket(rank)
      return "one_to_two" if rank <= 2
      return "three_to_five" if rank <= 5

      "six_plus"
    end

    def serialize_user(
      candidate,
      topics,
      viewer_tags,
      match,
      candidate_source:,
      rank:,
      latest_dynamic: nil,
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
      invitation_tags =
        if include_optional_details
          PracticeInvitationEligibility.new(
            sender: @user,
            recipient: candidate
          ).common_interests
        else
          []
        end

      payload = {
        id: candidate.id,
        username: candidate.username,
        name: candidate.name,
        avatar_template: candidate.avatar_template,
        profile_url: "/u/#{candidate.username}",
        invite_url:
          (
            if invitation_tags.present?
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
        invitation_interests: invitation_tags.map { |tag| serialize_tag(tag) },
        user_tags: UserTagVisibility.public_tags_for(candidate, viewer: @user),
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
  end
end

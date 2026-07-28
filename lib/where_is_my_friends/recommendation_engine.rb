# frozen_string_literal: true

require "zlib"

module WhereIsMyFriends
  class RecommendationEngine
    MAX_CATALOGUE = 20
    MAX_TOPIC_CANDIDATES = 50
    MAX_TOPICS = 5
    MAX_USERS = 3
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
        purposes: WhereIsMyFriendsInterestProfile::PURPOSES,
        profile: serialize_profile(profile),
        recommended_topics: recommended_topics(profile),
        recommended_users: recommended_users(profile)
      }
    end

    def catalogue
      @catalogue ||=
        begin
          configured = configured_interest_names
          tags =
            if configured.present?
              visible_interest_tags
                .where_name(configured)
                .to_a
                .sort_by do |tag|
                  configured.index(tag.name) || configured.length
                end
            else
              tags_from_visible_topics
            end

          tags.first(MAX_CATALOGUE).map { |tag| serialize_tag(tag) }
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
        .first(MAX_CATALOGUE)
    end

    def tags_from_visible_topics
      topics = TopicQuery.new(@user, per_page: 100).list_latest.topics
      counts = Hash.new(0)
      topics.each { |topic| topic.tags.each { |tag| counts[tag.id] += 1 } }

      visible_interest_tags
        .where(id: counts.keys)
        .to_a
        .sort_by { |tag| [-counts[tag.id], tag.name] }
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
      names = interest_names(profile)
      return [] if names.empty?

      dismissed_ids =
        WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id,
          target_type: "topic"
        ).pluck(:target_id)

      topic_candidates(profile)
        .reject { |topic| dismissed_ids.include?(topic.id) }
        .first(MAX_TOPICS)
        .map { |topic| serialize_topic(topic, names) }
    end

    def recommended_users(profile)
      topics = topic_candidates(profile)
      return [] if topics.empty?

      contributions = contribution_topics(topics)
      eligible_profiles =
        WhereIsMyFriendsInterestProfile
          .where(
            user_id: contributions.keys,
            personalization_enabled: true,
            recommendable: true
          )
          .where.not(completed_at: nil)
          .index_by(&:user_id)
      excluded_ids = relationship_exclusions
      users =
        User
          .where(id: eligible_profiles.keys)
          .activated
          .not_staged
          .not_suspended
          .not_silenced
          .where("last_seen_at >= ?", MEMBER_ACTIVE_WINDOW.ago)
          .where.not(id: excluded_ids)
          .includes(:user_profile, :user_option, :user_stat)
          .select { |candidate| @guardian.can_see_profile?(candidate) }

      dismissed_ids =
        WhereIsMyFriendsRecommendationDismissal.where(
          user_id: @user.id,
          target_type: "user"
        ).pluck(:target_id)
      users
        .reject { |candidate| dismissed_ids.include?(candidate.id) }
        .sort_by do |candidate|
          candidate_profile = eligible_profiles.fetch(candidate.id)
          [
            -purpose_complement_score(
              profile.purpose,
              candidate_profile.purpose
            ),
            -[contributions.fetch(candidate.id).length, 3].min,
            -candidate.last_seen_at.to_i,
            diversity_key(candidate.id)
          ]
        end
        .first(MAX_USERS)
        .map do |candidate|
          serialize_user(
            candidate,
            contributions.fetch(candidate.id),
            interest_names(profile)
          )
        end
    end

    def interest_names(profile)
      profile_interest_tags(profile).map(&:name)
    end

    def topic_candidates(profile)
      names = interest_names(profile)
      return [] if names.empty?

      @topic_candidates ||=
        TopicQuery
          .new(@user, per_page: MAX_TOPIC_CANDIDATES, tags: names)
          .list_latest
          .topics
          .reject do |topic|
            relationship_exclusions.include?(topic.user_id) ||
              topic.tags.any? { |tag| muted_tag_ids.include?(tag.id) }
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

    def serialize_topic(topic, interest_names)
      matching =
        topic
          .tags
          .select { |tag| interest_names.include?(tag.name) }
          .map { |tag| serialize_tag(tag) }

      {
        id: topic.id,
        title: topic.title,
        fancy_title: topic.fancy_title,
        slug: topic.slug,
        url: "/t/#{topic.slug}/#{topic.id}",
        posts_count: topic.posts_count,
        like_count: topic.like_count,
        bumped_at: topic.bumped_at,
        matching_interests: matching
      }
    end

    def serialize_user(candidate, topics, interest_names)
      representative_topics = topics.sort_by(&:bumped_at).reverse.first(2)
      matching_tags =
        representative_topics
          .flat_map(&:tags)
          .select { |tag| interest_names.include?(tag.name) }
          .uniq(&:id)
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
        reason_interests: matching_tags.map { |tag| serialize_tag(tag) },
        invitation_interests: invitation_tags.map { |tag| serialize_tag(tag) },
        representative_topics:
          representative_topics.map do |topic|
            serialize_topic(topic, interest_names)
          end
      }
    end

    def serialize_tag(tag)
      { id: tag.id, name: tag.name }
    end
  end
end

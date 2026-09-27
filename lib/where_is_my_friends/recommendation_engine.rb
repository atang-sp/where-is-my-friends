# frozen_string_literal: true

require_relative "recommendations/base"
require_relative "recommendations/topic_engine"
require_relative "recommendations/user_engine"
require_relative "recommendations/interest_engine"
require_relative "recommendations/serializer"

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
      @diversity_seed = diversity_seed
      @member_selection = ViewerAwareMemberSelection.new(viewer: user, guardian: @guardian)
      
      @serializer = Recommendations::Serializer.new(@user, @guardian)
      @topic_engine = Recommendations::TopicEngine.new(user: @user, guardian: @guardian, diversity_seed: @diversity_seed)
      @user_engine = Recommendations::UserEngine.new(user: @user, guardian: @guardian, diversity_seed: @diversity_seed, topic_engine: @topic_engine, member_selection: @member_selection)
      @interest_engine = Recommendations::InterestEngine.new(user: @user, guardian: @guardian, diversity_seed: @diversity_seed, topic_engine: @topic_engine)
      @base_engine = Recommendations::Base.new(user: @user, guardian: @guardian, diversity_seed: @diversity_seed)
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
      @user_engine.call(profile: profile, limit: 1, include_optional_details: false).map do |result|
        @serializer.serialize_user(
          result[:candidate],
          result[:contributions],
          result[:viewer_tags],
          result[:match],
          candidate_source: result[:candidate_source],
          rank: result[:rank],
          latest_dynamic: result[:latest_dynamic],
          invitation_tags: result[:invitation_tags],
          user_tags: result[:user_tags]
        )
      end.first
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
        profile: @serializer.serialize_profile(profile, @base_engine.send(:profile_interest_tags, profile)),
        recommended_topics: recommended_topics(profile),
        recommended_users: recommended_users(profile),
        recommended_interests: recommended_interests(profile)
      }
    end

    def catalogue
      @catalogue ||= begin
        visible_tags = @base_engine.send(:visible_interest_tags)
        visible_by_name = visible_tags.where(name: InterestCatalogue.names).index_by(&:name)
        curated = InterestCatalogue.entries.filter_map do |entry|
          tag = visible_by_name[entry.fetch("name")]
          @serializer.serialize_catalogue_tag(tag, entry) if tag
        end
        curated_ids = curated.pluck(:id)
        current_ids = @base_engine.send(:current_interest_tag_ids) rescue WhereIsMyFriendsUserInterest.where(user_id: @user.id).pluck(:tag_id)
        configured_tags = @base_engine.send(:configured_interest_tags) rescue visible_tags.where(name: configured_interest_names).to_a
        custom_tags = visible_tags.where(id: current_ids + configured_tags.pluck(:id)).where.not(id: curated_ids).to_a
          .sort_by do |tag|
            configured_interest_names.index(tag.name) || current_ids.index(tag.id) || MAX_CUSTOM_INTERESTS
          end
        custom = custom_tags.first(MAX_CUSTOM_INTERESTS).map do |tag|
          @serializer.serialize_catalogue_tag(tag, InterestCatalogue::COMMUNITY_GROUP)
        end

        (curated + custom).first(MAX_CATALOGUE)
      end
    end

    private

    def configured_interest_names
      SiteSetting.where_is_my_friends_interest_tags.to_s.split("|").map(&:strip).reject(&:blank?).uniq.first(MAX_CUSTOM_INTERESTS)
    end

    def catalogue_groups
      present_keys = catalogue.pluck(:group_key)
      groups = InterestCatalogue.groups.filter_map do |group|
        if present_keys.include?(group["key"])
          @serializer.serialize_catalogue_group(group)
        end
      end
      if present_keys.include?(InterestCatalogue::COMMUNITY_GROUP["key"])
        groups << @serializer.serialize_catalogue_group(InterestCatalogue::COMMUNITY_GROUP)
      end
      groups
    end

    def recommended_topics(profile)
      @topic_engine.call(profile: profile).each_with_index.map do |(topic, matches, _score), index|
        @serializer.serialize_topic(topic, matches, rank: index + 1, context: @topic_engine)
      end
    end

    def recommended_users(profile)
      @user_engine.call(profile: profile).map do |result|
        @serializer.serialize_user(
          result[:candidate],
          result[:contributions],
          result[:viewer_tags],
          result[:match],
          candidate_source: result[:candidate_source],
          rank: result[:rank],
          latest_dynamic: result[:latest_dynamic],
          invitation_tags: result[:invitation_tags],
          user_tags: result[:user_tags]
        )
      end
    end

    def recommended_interests(profile)
      @interest_engine.call(profile: profile).each_with_index.map do |entry, index|
        serialized = @serializer.serialize_interest_entrance(
          entry[:tag],
          entry[:candidates],
          candidate_source: entry[:candidate_source],
          reason_tag: entry[:reason_tag]
        )
        serialized.merge(rank: index + 1, rank_bucket: @serializer.send(:rank_bucket, index + 1))
      end
    end
  end
end

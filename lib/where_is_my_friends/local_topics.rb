# frozen_string_literal: true

require "uri"

module WhereIsMyFriends
  class LocalTopics
    CITY_TAG_PREFIX = "local-city-"
    DEFAULT_LIMIT = 6
    QUERY_LIMIT_MULTIPLIER = 3

    def self.tag_name_for(city_key)
      cleaned_city = DiscourseTagging.clean_tag(city_key.to_s)
      return if cleaned_city.blank?

      DiscourseTagging.clean_tag("#{CITY_TAG_PREFIX}#{cleaned_city}")
    end

    def self.compose_url(city_key)
      return unless SiteSetting.tagging_enabled

      tag_name = tag_name_for(city_key)
      return if tag_name.blank?

      query = { tags: tag_name }
      category_slug =
        SiteSetting.where_is_my_friends_target_category_slug.to_s.strip
      query[:category] = category_slug if category_slug.present?
      "/new-topic?#{URI.encode_www_form(query)}"
    end

    def self.local_topic?(topic)
      return false if topic.blank?

      topic.tags.count { |tag| tag.name.start_with?(CITY_TAG_PREFIX) } == 1
    end

    def initialize(user:, city_keys:, limit: DEFAULT_LIMIT)
      @user = user
      @city_keys = city_keys.map(&:to_s).reject(&:blank?).uniq
      @limit = limit
    end

    def call
      return [] unless SiteSetting.tagging_enabled
      return [] if @city_keys.empty?

      city_by_tag =
        @city_keys.each_with_object({}) do |city_key, result|
          tag_name = self.class.tag_name_for(city_key)
          result[tag_name] = city_key if tag_name.present?
        end
      return [] if city_by_tag.empty?

      topics =
        TopicQuery
          .new(
            @user,
            tags: city_by_tag.keys,
            per_page: [@limit * QUERY_LIMIT_MULTIPLIER, 100].min
          )
          .list_latest
          .topics

      topics
        .filter_map do |topic|
          city_tags =
            topic.tags.filter_map do |tag|
              tag.name if tag.name.start_with?(CITY_TAG_PREFIX)
            end
          next unless city_tags.one?

          city_tag = city_tags.first
          activity_city = city_by_tag[city_tag]
          next if activity_city.blank?

          {
            id: topic.id,
            title: topic.title,
            url: topic.relative_url,
            posts_count: topic.posts_count,
            bumped_at: topic.bumped_at&.iso8601,
            activity_city: activity_city,
            city_tag: city_tag
          }
        end
        .first(@limit)
    end
  end
end

# frozen_string_literal: true

require "uri"

module WhereIsMyFriends
  class LocalTopics
    DEFAULT_LIMIT = 6
    QUERY_LIMIT = 100

    CITY_TAG_ALIASES = {
      "tokyo" => "东京都",
      "东京" => "东京都",
      "osaka" => "大阪府",
      "大阪" => "大阪府"
    }.freeze
    REGION_TAG_ALIASES = {
      "Japan" => nil,
      "United States" => "美国",
      "Canada" => "加拿大",
      "United Kingdom" => "英国",
      "Germany" => "德国",
      "France" => "法国",
      "Australia" => "澳大利亚",
      "New Zealand" => "新西兰"
    }.freeze

    def self.target_category
      category_id = SiteSetting.where_is_my_friends_target_category_id.to_i
      return Category.find_by(id: category_id) if category_id.positive?

      slug = SiteSetting.where_is_my_friends_target_category_slug.to_s.strip
      Category.find_by(slug: slug) if slug.present?
    end

    def self.area_for(city_key)
      category = target_category
      return if category.blank? || !SiteSetting.tagging_enabled

      resolve_area(city_key, area_pairs(category))
    end

    def self.compose_url(city_key)
      category = target_category
      return if category.blank?

      query = { category_id: category.id }
      if (area = area_for(city_key))
        query[:tags] = [area[:parent], area[:child]].join(",")
      end
      "/new-topic?#{URI.encode_www_form(query).gsub("%2C", ",")}"
    end

    def self.desired_area_tag(city_key)
      key = city_key.to_s.downcase
      return CITY_TAG_ALIASES[key] if CITY_TAG_ALIASES.key?(key)

      region = CityCentroidLookup.instance.centroid_for(key)&.fetch(:region)
      REGION_TAG_ALIASES.fetch(region, region)
    end
    private_class_method :desired_area_tag

    def self.area_pairs(category)
      groups =
        CategoryTagGroup
          .where(category_id: category.id)
          .includes(tag_group: %i[parent_tag tags])
          .map(&:tag_group)
      top_level_tags =
        groups
          .select { |group| group.parent_tag_id.blank? }
          .flat_map(&:tags)
          .to_h { |tag| [tag.id, tag.name] }

      groups
        .filter_map do |group|
          parent_name = top_level_tags[group.parent_tag_id]
          next if parent_name.blank?

          group.tags.map { |tag| { parent: parent_name, child: tag.name } }
        end
        .flatten
    end
    private_class_method :area_pairs

    def self.local_topic?(topic)
      return false if topic.blank?
      return false unless SiteSetting.tagging_enabled

      category = target_category
      return false if category.blank? || topic.category_id != category.id

      topic_area(topic, area_pairs(category)).present?
    end

    def initialize(user:, city_keys:, limit: DEFAULT_LIMIT)
      @user = user
      @city_keys = city_keys.map(&:to_s).reject(&:blank?).uniq
      @limit = limit
    end

    def call
      return [] unless SiteSetting.tagging_enabled
      return [] if @city_keys.empty?

      category = self.class.target_category
      return [] if category.blank?

      pairs = self.class.send(:area_pairs, category)
      requested_areas =
        @city_keys
          .filter_map do |city_key|
            self.class.send(:resolve_area, city_key, pairs)
          end
          .uniq { |area| area[:child] }
      return [] if requested_areas.empty?

      requested_children = requested_areas.pluck(:child)

      topics =
        TopicQuery
          .new(
            @user,
            category: category.id.to_s,
            tags: requested_children,
            per_page: QUERY_LIMIT
          )
          .list_latest
          .topics

      topics
        .uniq(&:id)
        .filter_map do |topic|
          area = self.class.send(:topic_area, topic, pairs)
          next if area.blank? || !requested_children.include?(area[:child])

          {
            id: topic.id,
            title: topic.title,
            url: topic.relative_url,
            posts_count: topic.posts_count,
            bumped_at: topic.bumped_at&.iso8601,
            activity_area: area[:child]
          }
        end
        .first(@limit)
    end

    def self.resolve_area(city_key, pairs)
      desired_tag = desired_area_tag(city_key)
      return if desired_tag.blank?

      matches = pairs.select { |pair| pair[:child] == desired_tag }
      matches.one? ? matches.first : nil
    end
    private_class_method :resolve_area

    def self.topic_area(topic, pairs)
      topic_tag_names = topic.tags.map(&:name)
      child_names = pairs.pluck(:child).uniq & topic_tag_names
      parent_names = pairs.pluck(:parent).uniq & topic_tag_names
      matching_pairs =
        pairs.select do |pair|
          topic_tag_names.include?(pair[:child]) &&
            topic_tag_names.include?(pair[:parent])
        end

      if child_names.one? && parent_names.one? && matching_pairs.one?
        matching_pairs.first
      end
    end
    private_class_method :topic_area
  end
end

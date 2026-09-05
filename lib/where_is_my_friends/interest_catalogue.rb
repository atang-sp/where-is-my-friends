# frozen_string_literal: true

require "yaml"

module WhereIsMyFriends
  class InterestCatalogue
    Match = Struct.new(:score, :reason_names, :strength, keyword_init: true)
    COMMUNITY_GROUP = { "key" => "community" }.freeze

    SELECTION_MODES = %w[single multi].freeze
    DEFAULT_SELECTION_MODE = "multi"

    ROLE_KEYS = %w[active_role passive_role switch_role brat_interaction].freeze

    ROLE_COMPLEMENT_SCORES = {
      "active_role" => {
        "passive_role" => 6,
        "brat_interaction" => 6,
        "switch_role" => 5,
        "active_role" => 1
      },
      "passive_role" => {
        "active_role" => 6,
        "switch_role" => 5,
        "passive_role" => 1,
        "brat_interaction" => 1
      },
      "switch_role" => {
        "active_role" => 5,
        "passive_role" => 5,
        "switch_role" => 5,
        "brat_interaction" => 4
      },
      "brat_interaction" => {
        "active_role" => 6,
        "switch_role" => 5,
        "brat_interaction" => 2,
        "passive_role" => 1
      }
    }.freeze

    class << self
      def groups
        @groups ||= load_groups.freeze
      end

      def group_selection_mode(group)
        mode = group["selection_mode"].to_s
        SELECTION_MODES.include?(mode) ? mode : DEFAULT_SELECTION_MODE
      end

      def group_max_per_group(group)
        mode = group_selection_mode(group)
        return 1 if mode == "single"

        group["max_per_group"]&.to_i
      end

      def entries
        @entries ||=
          groups
            .flat_map do |group|
              group
                .fetch("interests")
                .map do |entry|
                  entry.merge("group_key" => group.fetch("key")).freeze
                end
            end
            .freeze
      end

      def names
        entries.map { |entry| entry.fetch("name") }
      end

      def group(key)
        groups.find { |entry| entry.fetch("key") == key }
      end

      def entries_for_name(name)
        entries_by_name.fetch(name.to_s.downcase, [])
      end

      def match(viewer_names:, candidate_names:)
        candidate_names = candidate_names.map(&:to_s)
        reason_scores =
          viewer_names.filter_map do |viewer_name|
            score =
              candidate_names
                .map do |candidate_name|
                  pair_score(viewer_name.to_s, candidate_name)
                end
                .max
                .to_i
            [viewer_name.to_s, score] if score.positive?
          end
        total = reason_scores.sum(&:last)

        Match.new(
          score: total,
          reason_names:
            reason_scores.sort_by { |name, score| [-score, name] }.map(&:first),
          strength: match_strength(total)
        )
      end

      def topic_matches(topic:, selected_tags:)
        topic_tag_names = topic.tags.map(&:name)
        normalized_title = topic.title.to_s.downcase

        selected_tags.filter_map do |tag|
          score =
            topic_score(
              selected_name: tag.name,
              topic_tag_names: topic_tag_names,
              normalized_title: normalized_title
            )
          [tag, score] if score.positive?
        end
      end

      def topic_query_names(selected_names)
        selected_names
          .flat_map do |name|
            matching_entries = entries_for_name(name)
            if matching_entries.empty?
              name
            else
              query_entries =
                matching_entries +
                  matching_entries.flat_map do |entry|
                    related_keys_for(entry.fetch("key")).map do |key|
                      entries_by_key.fetch(key)
                    end
                  end
              query_entries.flat_map do |entry|
                [entry.fetch("name")] + Array(entry["aliases"]) +
                  Array(entry["topic_tags"]) + Array(entry["topic_query_tags"])
              end
            end
          end
          .uniq
      end

      def member_candidate_names(selected_names)
        selected_names
          .flat_map do |name|
            matching_entries = entries_for_name(name)
            if matching_entries.empty?
              name
            else
              candidate_entries =
                matching_entries +
                  matching_entries.flat_map do |entry|
                    related_keys_for(entry.fetch("key")).map do |key|
                      entries_by_key.fetch(key)
                    end
                  end
              candidate_entries.flat_map do |entry|
                [entry.fetch("name")] + Array(entry["aliases"])
              end
            end
          end
          .uniq
      end

      def exploration_candidates(selected_names)
        selected_names = selected_names.map(&:to_s)
        selected_names
          .flat_map do |reason_name|
            entries_for_name(reason_name).flat_map do |entry|
              related_keys_for(entry.fetch("key")).map do |related_key|
                {
                  name: entries_by_key.fetch(related_key).fetch("name"),
                  reason_name: reason_name
                }
              end
            end
          end
          .reject { |candidate| selected_names.include?(candidate[:name]) }
          .uniq { |candidate| candidate[:name] }
      end

      def pair_score(viewer_name, candidate_name)
        viewer_entries = entries_for_name(viewer_name)
        candidate_entries = entries_for_name(candidate_name)

        if viewer_entries.present? && candidate_entries.present?
          viewer_keys = viewer_entries.map { |entry| entry.fetch("key") }
          candidate_keys = candidate_entries.map { |entry| entry.fetch("key") }

          viewer_role = (viewer_keys & ROLE_KEYS).first
          candidate_role = (candidate_keys & ROLE_KEYS).first
          if viewer_role && candidate_role
            return ROLE_COMPLEMENT_SCORES.dig(viewer_role, candidate_role) || 0
          end
        end

        return 6 if viewer_name == candidate_name
        return 0 if viewer_entries.empty? || candidate_entries.empty?
        return 5 if (viewer_keys & candidate_keys).present?

        related_keys =
          viewer_entries.flat_map do |entry|
            related_keys_for(entry.fetch("key"))
          end
        (related_keys & candidate_keys).present? ? 2 : 0
      end

      private

      def catalogue_path
        File.expand_path("../../config/interest_catalogue.yml", __dir__)
      end

      def load_groups
        raw = YAML.safe_load_file(catalogue_path)
        loaded_groups = raw.fetch("groups")
        validate!(loaded_groups)
        loaded_groups.map(&:freeze)
      end

      def validate!(loaded_groups)
        group_keys = loaded_groups.map { |group| group.fetch("key") }
        entry_keys =
          loaded_groups.flat_map do |group|
            group.fetch("interests").map { |entry| entry.fetch("key") }
          end
        entry_names =
          loaded_groups.flat_map do |group|
            group.fetch("interests").map { |entry| entry.fetch("name") }
          end

        unless group_keys.uniq == group_keys
          raise "Duplicate interest group key"
        end
        raise "Duplicate interest key" unless entry_keys.uniq == entry_keys
        raise "Duplicate interest name" unless entry_names.uniq == entry_names

        unknown_related =
          loaded_groups
            .flat_map { |group| group.fetch("interests") }
            .flat_map { |entry| Array(entry["related"]) }
            .uniq - entry_keys
        if unknown_related.present?
          raise "Unknown related interests: #{unknown_related.join(", ")}"
        end
      end

      def entries_by_name
        @entries_by_name ||=
          entries.each_with_object(
            Hash.new { |hash, key| hash[key] = [] }
          ) do |entry, index|
            ([entry.fetch("name")] + Array(entry["aliases"])).each do |name|
              index[name.to_s.downcase] << entry
            end
          end
      end

      def entries_by_key
        @entries_by_key ||= entries.index_by { |entry| entry.fetch("key") }
      end

      def related_keys_for(key)
        direct = Array(entries_by_key.fetch(key)["related"])
        inverse =
          entries.filter_map do |entry|
            entry.fetch("key") if Array(entry["related"]).include?(key)
          end
        (direct + inverse).uniq
      end

      def match_strength(score)
        return "strong" if score >= 10
        return "medium" if score >= 5

        "related"
      end

      def topic_score(selected_name:, topic_tag_names:, normalized_title:)
        return 6 if topic_tag_names.include?(selected_name)

        selected_entries = entries_for_name(selected_name)
        return 0 if selected_entries.empty?

        selected_entries.each do |entry|
          mapped_names =
            Array(entry["aliases"]) + Array(entry["topic_tags"]) +
              [entry.fetch("name")]
          return 5 if (mapped_names & topic_tag_names).present?
        end

        selected_entries.each do |entry|
          keywords = Array(entry["topic_keywords"]).map(&:downcase)
          if keywords.any? { |keyword| normalized_title.include?(keyword) }
            return 3
          end
        end

        related_names =
          selected_entries
            .flat_map { |entry| related_keys_for(entry.fetch("key")) }
            .flat_map do |key|
              entry = entries_by_key.fetch(key)
              [entry.fetch("name")] + Array(entry["aliases"]) +
                Array(entry["topic_tags"])
            end
            .uniq
        (related_names & topic_tag_names).present? ? 1 : 0
      end
    end
  end
end

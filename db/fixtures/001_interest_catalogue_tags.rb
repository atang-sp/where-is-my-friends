# frozen_string_literal: true

require "yaml"

catalogue_path =
  Rails.root.join("plugins/where-is-my-friends/config/interest_catalogue.yml")
interest_names =
  YAML
    .safe_load_file(catalogue_path)
    .fetch("groups")
    .flat_map do |group|
      group.fetch("interests").map { |interest| interest.fetch("name") }
    end

interest_names.each { |name| Tag.seed(:name) { |tag| tag.name = name } }

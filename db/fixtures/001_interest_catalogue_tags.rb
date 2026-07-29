# frozen_string_literal: true

require "yaml"

catalogue_path =
  File.expand_path("../../config/interest_catalogue.yml", __dir__)
interest_names =
  YAML
    .safe_load_file(catalogue_path)
    .fetch("groups")
    .flat_map do |group|
      group.fetch("interests").map { |interest| interest.fetch("name") }
    end

interest_names.each do |name|
  Tag.seed(:name) do |tag|
    tag.name = name
    tag.slug = ""
  end
end

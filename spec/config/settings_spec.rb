# frozen_string_literal: true

RSpec.describe SiteSetting do
  it "ships all personal dynamics surfaces enabled by default" do
    settings =
      YAML.safe_load(
        File.read(File.expand_path("../../config/settings.yml", __dir__))
      ).fetch("plugins")

    expect(
      settings
        .values_at(
          "where_is_my_friends_dynamics_enabled",
          "where_is_my_friends_dynamics_homepage_enabled",
          "where_is_my_friends_dynamics_feed_enabled",
          "where_is_my_friends_dynamics_member_preview_enabled"
        )
        .map { |setting| setting.fetch("default") }
    ).to eq([true, true, true, true])
  end
end

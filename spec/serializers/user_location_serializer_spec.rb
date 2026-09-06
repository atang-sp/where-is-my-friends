# frozen_string_literal: true

RSpec.describe UserLocationSerializer do
  fab!(:user) { Fabricate(:user) }
  fab!(:location) { UserLocation.upsert_city_location(user.id, city: "上海") }
  fab!(:origin) { UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海") }

  it "serializes community_level and role_key when provided" do
    serializer =
      described_class.new(
        {
          user: user,
          location: location,
          origin: origin,
          community_level: { level: 3, name: "日常冒泡" },
          role_key: "active_role",
        },
        root: false,
      )

    json = serializer.as_json
    expect(json[:community_level]).to eq(level: 3, name: "日常冒泡")
    expect(json[:role_key]).to eq("active_role")
  end

  it "handles nil community_level gracefully" do
    serializer =
      described_class.new(
        {
          user: user,
          location: location,
          origin: origin,
          community_level: nil,
        },
        root: false,
      )

    json = serializer.as_json
    expect(json[:community_level]).to be_nil
    expect(json[:role_key]).to be_nil
  end

  it "resolves role_key from custom fields when matching active/passive/switch/brat" do
    serializer =
      described_class.new(
        {
          user: user,
          location: location,
          origin: origin,
          custom_field_values: { "身份" => "主动" },
        },
        root: false,
      )

    json = serializer.as_json
    expect(json[:role_key]).to eq("active_role")
  end
end

# frozen_string_literal: true

RSpec.describe UserLocation do
  describe ".normalize_city" do
    it "normalizes Chinese administrative suffixes and whitespace to one key" do
      expect(described_class.normalize_city("  上海市 ")).to eq("上海")
      expect(described_class.normalize_city("上海")).to eq("上海")
      expect(described_class.normalize_city(" New   York ")).to eq("new york")
    end
  end

  describe ".upsert_city_location" do
    it "stores a city-only location without coordinates" do
      user = Fabricate(:user)

      location =
        described_class.upsert_city_location(user.id, city: "上海市", region: "上海")

      expect(location).to have_attributes(
        city: "上海市",
        city_key: "上海",
        region: "上海",
        discovery_mode: "city",
        latitude: nil,
        longitude: nil,
        enabled: true
      )
    end
  end

  describe ".upsert_precise_location" do
    it "requires valid coordinates for gps and map modes" do
      user = Fabricate(:user)

      expect {
        described_class.upsert_precise_location(
          user.id,
          city: "上海",
          discovery_mode: "gps",
          latitude: nil,
          longitude: nil
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "stores an optional precise location with its city boundary" do
      user = Fabricate(:user)

      location =
        described_class.upsert_precise_location(
          user.id,
          city: "上海",
          region: "上海",
          discovery_mode: "map",
          latitude: 31.2304,
          longitude: 121.4737
        )

      expect(location).to have_attributes(
        city_key: "上海",
        discovery_mode: "map",
        latitude: 31.2304,
        longitude: 121.4737,
        is_virtual: true
      )
    end
  end

  describe ".active_for_discovery" do
    it "includes only enabled locations with a city" do
      active =
        described_class.upsert_city_location(Fabricate(:user).id, city: "上海")
      disabled =
        described_class.upsert_city_location(Fabricate(:user).id, city: "上海")
      disabled.update_column(:enabled, false)

      expect(described_class.active_for_discovery).to contain_exactly(active)
    end
  end

  describe ".discovery_limit" do
    it "clamps result limits to a safe range" do
      expect(described_class.discovery_limit(5_000)).to eq(200)
      expect(described_class.discovery_limit(50)).to eq(50)
      expect(described_class.discovery_limit(0)).to eq(10)
    end
  end

  describe "#distance_band_to" do
    it "returns a coarse band rather than an exact distance" do
      origin =
        described_class.upsert_precise_location(
          Fabricate(:user).id,
          city: "上海",
          discovery_mode: "map",
          latitude: 31.2304,
          longitude: 121.4737
        )
      close =
        described_class.upsert_precise_location(
          Fabricate(:user).id,
          city: "上海",
          discovery_mode: "map",
          latitude: 31.2304,
          longitude: 121.49
        )
      medium =
        described_class.upsert_precise_location(
          Fabricate(:user).id,
          city: "上海",
          discovery_mode: "map",
          latitude: 31.35,
          longitude: 121.4737
        )
      far =
        described_class.upsert_precise_location(
          Fabricate(:user).id,
          city: "上海",
          discovery_mode: "map",
          latitude: 32.0,
          longitude: 121.4737
        )

      expect(origin.distance_band_to(close)).to eq("under_5")
      expect(origin.distance_band_to(medium)).to eq("5_to_20")
      expect(origin.distance_band_to(far)).to eq("over_20")
    end

    it "returns no distance band when either user is in city-only mode" do
      city_only =
        described_class.upsert_city_location(Fabricate(:user).id, city: "上海")
      precise =
        described_class.upsert_precise_location(
          Fabricate(:user).id,
          city: "上海",
          discovery_mode: "map",
          latitude: 31.2304,
          longitude: 121.4737
        )

      expect(city_only.distance_band_to(precise)).to eq("same_city")
      expect(precise.distance_band_to(city_only)).to eq("same_city")
    end

    it "uses city centroids for cross-city bands" do
      shanghai =
        described_class.upsert_city_location(Fabricate(:user).id, city: "上海")
      suzhou =
        described_class.upsert_city_location(Fabricate(:user).id, city: "苏州")
      beijing =
        described_class.upsert_city_location(Fabricate(:user).id, city: "北京")

      expect(shanghai.distance_band_to(suzhou)).to eq("moderate")
      expect(shanghai.distance_band_to(beijing)).to eq("far")
    end
  end

  describe "#effective_discovery_radius_km" do
    it "falls back to the site setting default" do
      location =
        described_class.upsert_city_location(Fabricate(:user).id, city: "上海")

      expect(location.effective_discovery_radius_km).to eq(100)
    end

    it "uses the stored preference when present" do
      location =
        described_class.upsert_city_location(
          Fabricate(:user).id,
          city: "上海",
          discovery_radius_km: 50
        )

      expect(location.effective_discovery_radius_km).to eq(50)
    end
  end
end

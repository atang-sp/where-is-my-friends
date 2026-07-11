# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::CityCentroidLookup do
  subject(:lookup) { described_class.new }

  after { described_class.reset! }

  describe "#centroid_for" do
    it "returns coordinates for a known normalized city key" do
      expect(lookup.centroid_for("上海")).to include(
        lat: a_value_within(0.01).of(31.23),
        lng: a_value_within(0.01).of(121.47)
      )
    end

    it "returns nil for unknown cities" do
      expect(lookup.centroid_for("nowhere-ville")).to be_nil
    end
  end

  describe "#city_keys_within_radius" do
    it "includes origin and nearby cities within the radius" do
      keys = lookup.city_keys_within_radius("上海", 100)

      expect(keys).to include("上海", "苏州", "嘉兴")
      expect(keys).not_to include("北京", "杭州")
    end

    it "falls back to exact city matching when the origin is unknown" do
      expect(lookup.city_keys_within_radius("未知城", 100)).to eq(["未知城"])
    end

    it "expands farther cities when the radius grows" do
      near = lookup.city_keys_within_radius("上海", 50)
      far = lookup.city_keys_within_radius("上海", 200)

      expect(near).to eq(["上海"])
      expect(far).to include("上海", "苏州", "杭州")
      expect(far.length).to be > near.length
    end
  end

  describe "#distance_km_between" do
    it "returns a finite distance between known cities" do
      distance = lookup.distance_km_between("上海", "苏州")

      expect(distance).to be_between(50, 100)
    end

    it "returns nil when either city is missing" do
      expect(lookup.distance_km_between("上海", "未知城")).to be_nil
    end
  end

  describe "#nearest_city_for" do
    it "maps coordinates to the nearest known city within max distance" do
      match = lookup.nearest_city_for(31.2304, 121.4737, max_km: 80)

      expect(match).to include(city_key: "上海", region: "上海")
      expect(match[:distance_km]).to be < 5
    end

    it "returns nil when no city is close enough" do
      expect(lookup.nearest_city_for(0.0, 0.0, max_km: 50)).to be_nil
    end
  end
end

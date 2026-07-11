# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LocationsController do
  fab!(:user)

  before { SiteSetting.where_is_my_friends_enabled = true }

  it "requires login for every data endpoint" do
    get "/where-is-my-friends/locations/nearby.json"
    expect(response.status).to eq(403)

    post "/where-is-my-friends/locations.json", params: { city: "上海" }
    expect(response.status).to eq(403)

    delete "/where-is-my-friends/locations.json"
    expect(response.status).to eq(403)

    get "/where-is-my-friends/debug-stats.json"
    expect(response.status).to eq(403)
  end

  describe "GET /where-is-my-friends.json" do
    it "requires a logged-in user" do
      get "/where-is-my-friends.json"

      expect(response.status).to eq(403)
    end

    it "returns explicit setup state without coordinates" do
      sign_in(user)

      get "/where-is-my-friends.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "state" => "setup",
        "location" => nil
      )
      expect(response.body).not_to include(
        "latitude",
        "longitude",
        "location_accuracy"
      )
    end

    it "deduplicates city suggestions by normalized city key" do
      sign_in(user)
      UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海")
      UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海市")
      UserLocation.upsert_city_location(Fabricate(:user).id, city: "北京")

      get "/where-is-my-friends.json"

      suggestions = response.parsed_body.fetch("city_suggestions")
      expect(suggestions.pluck("city_key")).to contain_exactly("上海", "北京")
      expect(suggestions.count { |entry| entry["city_key"] == "上海" }).to eq(1)
    end

    it "exposes only the selected map provider browser key" do
      SiteSetting.where_is_my_friends_map_provider = "amap"
      SiteSetting.where_is_my_friends_amap_api_key = "amap-browser-key"
      SiteSetting.where_is_my_friends_baidu_api_key = "baidu-browser-key"
      sign_in(user)

      get "/where-is-my-friends.json"

      settings = response.parsed_body.fetch("settings")
      expect(settings).to include(
        "map_provider" => "amap",
        "amap_api_key" => "amap-browser-key"
      )
      expect(settings).not_to have_key("baidu_api_key")
    end
  end

  describe "POST /where-is-my-friends/locations.json" do
    before { sign_in(user) }

    it "saves city mode and returns coordinate-free metadata" do
      post "/where-is-my-friends/locations.json",
           params: {
             city: "上海市",
             region: "上海"
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include("state" => "ready")
      expect(response.parsed_body.fetch("location")).to include(
        "city" => "上海市",
        "region" => "上海",
        "discovery_mode" => "city"
      )
      expect(response.body).not_to include(
        "latitude",
        "longitude",
        "location_accuracy"
      )
    end

    it "rejects precise mode without coordinates" do
      post "/where-is-my-friends/locations.json",
           params: {
             city: "上海",
             discovery_mode: "gps"
           }

      expect(response.status).to eq(422)
      expect(UserLocation.find_by(user_id: user.id)).to be_nil
    end

    it "rejects precise modes when the administrator disables them" do
      SiteSetting.where_is_my_friends_enable_virtual_location = false

      post "/where-is-my-friends/locations.json",
           params: {
             city: "上海",
             discovery_mode: "gps",
             latitude: 31.2304,
             longitude: 121.4737
           }

      expect(response.status).to eq(422)
      expect(UserLocation.find_by(user_id: user.id)).to be_nil
    end
  end

  describe "GET /where-is-my-friends/locations/nearby.json" do
    before { sign_in(user) }

    it "uses the signed-in user's stored city, excludes self and expired users" do
      UserLocation.upsert_precise_location(
        user.id,
        city: "上海",
        discovery_mode: "map",
        latitude: 31.2304,
        longitude: 121.4737
      )
      nearby_user = Fabricate(:user)
      UserLocation.upsert_city_location(nearby_user.id, city: "上海市")
      outside_user = Fabricate(:user)
      UserLocation.upsert_city_location(outside_user.id, city: "北京")
      expired_user = Fabricate(:user)
      expired = UserLocation.upsert_city_location(expired_user.id, city: "上海")
      expired.update_column(:expires_at, 1.minute.ago)

      get "/where-is-my-friends/locations/nearby.json",
          params: {
            latitude: 39.9042,
            longitude: 116.4074
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["state"]).to eq("ready")
      expect(
        response.parsed_body.fetch("users").pluck("username")
      ).to contain_exactly(nearby_user.username)
    end

    it "returns distance bands and never location coordinates or arbitrary custom fields" do
      UserLocation.upsert_precise_location(
        user.id,
        city: "上海",
        discovery_mode: "map",
        latitude: 31.2304,
        longitude: 121.4737
      )
      nearby_user = Fabricate(:user)
      nearby_user.custom_fields["secret_token"] = "must-not-leak"
      nearby_user.save_custom_fields
      UserLocation.upsert_precise_location(
        nearby_user.id,
        city: "上海",
        discovery_mode: "map",
        latitude: 31.2304,
        longitude: 121.49
      )

      get "/where-is-my-friends/locations/nearby.json"

      result = response.parsed_body.fetch("users").first
      expect(result["distance_band"]).to eq("under_5")
      expect(result.keys).to contain_exactly(
        "id",
        "username",
        "name",
        "avatar_template",
        "city",
        "distance_band",
        "message_url"
      )
      expect(response.body).not_to include(
        "latitude",
        "longitude",
        "location_accuracy",
        "secret_token",
        "must-not-leak"
      )
    end

    it "returns explicit empty and setup states" do
      get "/where-is-my-friends/locations/nearby.json"
      expect(response.parsed_body["state"]).to eq("setup")

      UserLocation.upsert_city_location(user.id, city: "成都")
      get "/where-is-my-friends/locations/nearby.json"
      expect(response.parsed_body).to include("state" => "empty", "users" => [])
    end
  end

  describe "DELETE /where-is-my-friends/locations.json" do
    it "destroys the signed-in user's stored location" do
      sign_in(user)
      location = UserLocation.upsert_city_location(user.id, city: "上海")

      delete "/where-is-my-friends/locations.json"

      expect(response.status).to eq(200)
      expect(UserLocation.exists?(location.id)).to eq(false)
    end
  end
end

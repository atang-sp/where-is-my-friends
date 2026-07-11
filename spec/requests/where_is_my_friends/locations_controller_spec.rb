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
      expect(suggestions.find { |entry| entry["city_key"] == "上海" }).to include(
        "count" => 2
      )
    end

    it "merges seed cities that are not already active" do
      SiteSetting.where_is_my_friends_seed_cities = "深圳|上海|Tokyo"
      sign_in(user)
      UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海市")

      get "/where-is-my-friends.json"

      suggestions = response.parsed_body.fetch("city_suggestions")
      expect(suggestions.pluck("city_key")).to eq(%w[上海 深圳 tokyo])
      expect(suggestions.find { |entry| entry["city_key"] == "深圳" }).to include(
        "city" => "深圳",
        "count" => 0
      )
    end

    it "exposes aggregate privacy threshold in client settings" do
      SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 5
      sign_in(user)

      get "/where-is-my-friends.json"

      expect(response.parsed_body.fetch("settings")).to include(
        "aggregate_privacy_threshold" => 5
      )
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
      expect(result["is_recent"]).to eq(true)
      expect(result.keys).to contain_exactly(
        "id",
        "username",
        "name",
        "avatar_template",
        "city",
        "distance_band",
        "message_url",
        "is_recent",
        "bio_excerpt"
      )
      expect(response.body).not_to include(
        "latitude",
        "longitude",
        "location_accuracy",
        "secret_token",
        "must-not-leak"
      )
    end

    it "includes a truncated plain-text bio excerpt for nearby members" do
      UserLocation.upsert_city_location(user.id, city: "上海")
      nearby_user = Fabricate(:user)
      nearby_user.user_profile.update!(
        bio_raw: "Loves hiking around the city parks and weekend coffee."
      )
      UserLocation.upsert_city_location(nearby_user.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json"

      result = response.parsed_body.fetch("users").first
      expect(result["bio_excerpt"]).to eq(
        "Loves hiking around the city parks and weekend coffee."
      )
    end

    it "returns explicit empty and setup states" do
      get "/where-is-my-friends/locations/nearby.json"
      expect(response.parsed_body["state"]).to eq("setup")

      UserLocation.upsert_city_location(user.id, city: "成都")
      get "/where-is-my-friends/locations/nearby.json"
      expect(response.parsed_body).to include("state" => "empty", "users" => [])
    end

    it "includes members from nearby cities within the discovery radius" do
      UserLocation.upsert_city_location(
        user.id,
        city: "上海",
        discovery_radius_km: 100
      )
      same_city = Fabricate(:user)
      UserLocation.upsert_city_location(same_city.id, city: "上海")
      nearby_city = Fabricate(:user)
      UserLocation.upsert_city_location(nearby_city.id, city: "苏州")
      far_city = Fabricate(:user)
      UserLocation.upsert_city_location(far_city.id, city: "北京")

      get "/where-is-my-friends/locations/nearby.json"

      usernames = response.parsed_body.fetch("users").pluck("username")
      expect(usernames).to include(same_city.username, nearby_city.username)
      expect(usernames).not_to include(far_city.username)

      bands =
        response.parsed_body.fetch("users").index_by { |entry| entry["username"] }
      expect(bands[same_city.username]["distance_band"]).to eq("same_city")
      expect(bands[nearby_city.username]["distance_band"]).to eq("moderate")
    end

    it "respects a tighter discovery radius" do
      UserLocation.upsert_city_location(
        user.id,
        city: "上海",
        discovery_radius_km: 50
      )
      nearby_city = Fabricate(:user)
      UserLocation.upsert_city_location(nearby_city.id, city: "苏州")

      get "/where-is-my-friends/locations/nearby.json"

      expect(response.parsed_body).to include("state" => "empty", "users" => [])
    end
  end

  describe "discovery radius preference" do
    before { sign_in(user) }

    it "exposes radius options and persists a selected radius" do
      get "/where-is-my-friends.json"
      expect(response.parsed_body.fetch("settings")).to include(
        "default_discovery_radius_km" => 100,
        "discovery_radius_options_km" => [50, 100, 200]
      )

      post "/where-is-my-friends/locations.json",
           params: {
             city: "上海",
             discovery_radius_km: 200
           }

      expect(response.parsed_body.fetch("location")).to include(
        "discovery_radius_km" => 200
      )
      expect(UserLocation.find_by(user_id: user.id).discovery_radius_km).to eq(
        200
      )
    end

    it "updates radius without clearing a precise location" do
      UserLocation.upsert_precise_location(
        user.id,
        city: "上海",
        discovery_mode: "map",
        latitude: 31.2304,
        longitude: 121.4737,
        discovery_radius_km: 100
      )

      post "/where-is-my-friends/locations.json",
           params: {
             city: "上海",
             discovery_mode: "map",
             discovery_radius_km: 200
           }

      location = UserLocation.find_by(user_id: user.id)
      expect(response.status).to eq(200)
      expect(location).to have_attributes(
        discovery_mode: "map",
        discovery_radius_km: 200,
        latitude: 31.2304,
        longitude: 121.4737
      )
    end
  end

  describe "member joined notifications" do
    before { sign_in(user) }

    it "enqueues a city notification when a member newly joins a city" do
      existing = Fabricate(:user)
      UserLocation.upsert_city_location(existing.id, city: "上海")

      expect do
        post "/where-is-my-friends/locations.json", params: { city: "上海" }
      end.to change { Jobs::WhereIsMyFriendsNotifyCityMembers.jobs.size }.by(1)

      job = Jobs::WhereIsMyFriendsNotifyCityMembers.jobs.last
      expect(job["args"].first).to include(
        "joiner_id" => user.id,
        "city" => "上海",
        "city_key" => "上海"
      )
    end

    it "does not enqueue when the user refreshes the same city" do
      UserLocation.upsert_city_location(user.id, city: "上海")

      expect do
        post "/where-is-my-friends/locations.json", params: { city: "上海" }
      end.not_to change { Jobs::WhereIsMyFriendsNotifyCityMembers.jobs.size }
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

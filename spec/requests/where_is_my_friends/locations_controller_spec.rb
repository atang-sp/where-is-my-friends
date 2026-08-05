# frozen_string_literal: true
RSpec.describe WhereIsMyFriends::LocationsController do
  fab!(:user)

  before { SiteSetting.where_is_my_friends_enabled = true }

  def configure_practice_category(*area_names)
    category = Fabricate(:category, minimum_required_tags: 2)
    SiteSetting.where_is_my_friends_target_category_id = category.id
    china = Tag.find_or_create_by!(name: "中国")
    areas =
      area_names.to_h { |name| [name, Tag.find_or_create_by!(name: name)] }
    top_level_group = Fabricate(:tag_group, tags: [china], one_per_topic: true)
    province_group =
      Fabricate(
        :tag_group,
        parent_tag: china,
        tags: areas.values,
        one_per_topic: true
      )
    CategoryTagGroup.create!(category: category, tag_group: top_level_group)
    CategoryTagGroup.create!(category: category, tag_group: province_group)
    [category, { "中国" => china }.merge(areas)]
  end

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

    it "returns active, growing, and complete city directory counts" do
      sign_in(user)
      active_shanghai = Fabricate(:user, last_seen_at: 1.day.ago)
      inactive_shanghai = Fabricate(:user, last_seen_at: 100.days.ago)
      active_suzhou = Fabricate(:user, last_seen_at: 2.days.ago)
      active_beijing = Fabricate(:user, last_seen_at: 3.days.ago)

      [
        [active_shanghai, "上海", 2.days.ago],
        [inactive_shanghai, "上海市", 2.days.ago],
        [active_suzhou, "苏州", 1.day.ago],
        [active_beijing, "北京", 40.days.ago]
      ].each do |member, city, joined_at|
        location = UserLocation.upsert_city_location(member.id, city: city)
        location.update_columns(
          created_at: joined_at,
          updated_at: joined_at,
          city_joined_at: joined_at
        )
      end

      get "/where-is-my-friends.json"

      directory = response.parsed_body.fetch("city_directory")
      shanghai =
        directory.fetch("cities").find { |entry| entry["city_key"] == "上海" }
      expect(shanghai).to include(
        "city" => "上海",
        "recent_active_count" => 1,
        "joined_count" => 2
      )
      expect(directory.fetch("cities").pluck("city_key")).to contain_exactly(
        "上海",
        "苏州",
        "北京"
      )
      expect(directory.fetch("active").pluck("city_key")).to include(
        "上海",
        "苏州",
        "北京"
      )
      expect(directory.fetch("growing").pluck("city_key")).to include(
        "上海",
        "苏州"
      )
      expect(directory.fetch("growing").pluck("city_key")).not_to include("北京")
      expect(directory["activity_window_days"]).to eq(90)
    end

    it "exposes a coordinate-free canonical city catalogue" do
      sign_in(user)

      get "/where-is-my-friends.json"

      shanghai =
        response
          .parsed_body
          .fetch("city_catalogue")
          .find { |entry| entry["city_key"] == "上海" }
      expect(shanghai).to eq(
        "city" => "上海",
        "city_key" => "上海",
        "region" => "上海"
      )
      expect(response.body).not_to include(
        "lat",
        "lng",
        "latitude",
        "longitude"
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

  describe "GET /where-is-my-friends/cities/preview.json" do
    it "previews network density without joining and recommends the smallest useful radius" do
      sign_in(user)
      shanghai_member = Fabricate(:user, last_seen_at: 1.day.ago)
      UserLocation.upsert_city_location(shanghai_member.id, city: "上海")
      2.times do
        suzhou_member = Fabricate(:user, last_seen_at: 2.days.ago)
        UserLocation.upsert_city_location(suzhou_member.id, city: "苏州")
      end

      get "/where-is-my-friends/cities/preview.json", params: { city: "上海市" }

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("city")).to include(
        "city" => "上海",
        "city_key" => "上海",
        "canonical" => true,
        "recent_active_count" => 1,
        "joined_count" => 1
      )
      expect(
        response
          .parsed_body
          .fetch("radius_options")
          .map { |option| [option["radius_km"], option["recent_active_count"]] }
      ).to eq([[50, 1], [100, 3], [200, 3]])
      expect(response.parsed_body["recommended_radius_km"]).to eq(100)
      expect(response.parsed_body.fetch("nearby_cities").first).to include(
        "city" => "苏州",
        "recent_active_count" => 2,
        "joined_count" => 2
      )
      expect(UserLocation.find_by(user_id: user.id)).to be_nil
      expect(response.body).not_to include(
        "latitude",
        "longitude",
        "location_accuracy"
      )
    end

    it "returns existing target-category topics for the previewed activity area" do
      SiteSetting.tagging_enabled = true
      sign_in(user)
      category, tags = configure_practice_category("上海")
      local_topic =
        Fabricate(
          :topic,
          category: category,
          title: "Shanghai weekend picnic",
          tags: tags.values_at("中国", "上海")
        )

      get "/where-is-my-friends/cities/preview.json", params: { city: "上海" }

      expect(response.parsed_body.fetch("local_topics").first).to include(
        "id" => local_topic.id,
        "title" => "Shanghai weekend picnic",
        "url" => local_topic.relative_url,
        "activity_area" => "上海"
      )
      expect(response.parsed_body.fetch("local_topic_compose_url")).to eq(
        "/new-topic?category_id=#{category.id}&tags=%E4%B8%AD%E5%9B%BD,%E4%B8%8A%E6%B5%B7"
      )
    end

    it "falls back to the target category when a canonical city has no area tag" do
      SiteSetting.tagging_enabled = true
      sign_in(user)
      category, = configure_practice_category("上海")

      get "/where-is-my-friends/cities/preview.json",
          params: {
            city: "Singapore"
          }

      expect(response.parsed_body).to include(
        "local_topics" => [],
        "local_topic_compose_url" => "/new-topic?category_id=#{category.id}"
      )
    end

    it "marks unknown cities unverified without claiming radius matches" do
      sign_in(user)

      get "/where-is-my-friends/cities/preview.json",
          params: {
            city: "A Small Unmapped Place"
          }

      expect(response.parsed_body.fetch("city")).to include(
        "canonical" => false,
        "recent_active_count" => 0,
        "joined_count" => 0
      )
      expect(response.parsed_body).to include(
        "radius_options" => [],
        "recommended_radius_km" => nil,
        "nearby_cities" => [],
        "local_topics" => []
      )
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

    it "persists the two independent join notification choices" do
      post "/where-is-my-friends/locations.json",
           params: {
             city: "上海",
             notify_city: false,
             notify_nearby: true
           }

      expect(response.status).to eq(200)
      expect(user.user_option.reload).to have_attributes(
        where_is_my_friends_notify_city: false,
        where_is_my_friends_notify_nearby: true
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

    it "uses the signed-in user's stored city, excludes self and disabled users" do
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
      disabled_user = Fabricate(:user)
      disabled = UserLocation.upsert_city_location(disabled_user.id, city: "上海")
      disabled.update_column(:enabled, false)

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
        "online",
        "activity_status",
        "last_seen_at",
        "last_posted_at",
        "bio_excerpt",
        "custom_fields"
      )
      expect(result["custom_fields"]).to eq({})
      expect(response.body).not_to include(
        "latitude",
        "longitude",
        "location_accuracy",
        "secret_token",
        "must-not-leak"
      )
    end

    it "marks recently seen members online unless they hide presence" do
      UserLocation.upsert_city_location(user.id, city: "上海")
      visible_online = Fabricate(:user, last_seen_at: 2.minutes.ago)
      hidden_online = Fabricate(:user, last_seen_at: 1.minute.ago)
      hidden_online.user_option.update!(hide_presence: true)
      UserLocation.upsert_city_location(visible_online.id, city: "上海")
      UserLocation.upsert_city_location(hidden_online.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json"

      members =
        response
          .parsed_body
          .fetch("users")
          .index_by { |entry| entry.fetch("username") }
      expect(members.fetch(visible_online.username)).to include(
        "online" => true,
        "activity_status" => "online"
      )
      expect(members.fetch(hidden_online.username)).to include(
        "online" => false,
        "activity_status" => "recent",
        "last_seen_at" => nil
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
        response
          .parsed_body
          .fetch("users")
          .index_by { |entry| entry["username"] }
      expect(bands[same_city.username]["distance_band"]).to eq("same_city")
      expect(bands[nearby_city.username]["distance_band"]).to eq("moderate")
    end

    it "groups members by distance-ordered city and marks inactive profiles" do
      UserLocation.upsert_city_location(
        user.id,
        city: "上海",
        discovery_radius_km: 200
      )
      active_same_city = Fabricate(:user, last_seen_at: 1.day.ago)
      UserLocation.upsert_city_location(active_same_city.id, city: "上海")
      inactive_same_city = Fabricate(:user, last_seen_at: 100.days.ago)
      UserLocation.upsert_city_location(inactive_same_city.id, city: "上海市")
      active_nearby = Fabricate(:user, last_seen_at: 2.days.ago)
      UserLocation.upsert_city_location(active_nearby.id, city: "苏州")

      get "/where-is-my-friends/locations/nearby.json"

      groups = response.parsed_body.fetch("city_groups")
      expect(groups.pluck("city_key")).to eq(%w[上海 苏州])
      expect(groups.first).to include(
        "city" => "上海",
        "distance_band" => "same_city",
        "recent_active_count" => 1,
        "joined_count" => 2
      )
      expect(groups.first.fetch("users").pluck("username")).to eq(
        [active_same_city.username, inactive_same_city.username]
      )
      expect(groups.first.fetch("users").pluck("activity_status")).to eq(
        %w[recent inactive]
      )
      expect(groups.second).to include(
        "city" => "苏州",
        "recent_active_count" => 1,
        "joined_count" => 1
      )
      expect(groups.second["approximate_distance_km"]).to be_between(10, 200)
    end

    it "aggregates readable local topics across the selected city radius" do
      SiteSetting.tagging_enabled = true
      UserLocation.upsert_city_location(
        user.id,
        city: "上海",
        discovery_radius_km: 100
      )
      category, tags = configure_practice_category("上海", "江苏", "浙江")
      ambiguous_topic =
        Fabricate(
          :topic,
          category: category,
          title: "Ambiguous activity",
          tags: tags.values_at("中国", "上海", "江苏")
        )
      shanghai_topic =
        Fabricate(
          :topic,
          category: category,
          title: "Shanghai activity",
          tags: tags.values_at("中国", "上海")
        )
      jiangsu_topic =
        Fabricate(
          :topic,
          category: category,
          title: "Jiangsu activity",
          tags: tags.values_at("中国", "江苏")
        )
      zhejiang_topic =
        Fabricate(
          :topic,
          category: category,
          title: "Zhejiang activity",
          tags: tags.values_at("中国", "浙江")
        )
      Fabricate(
        :topic,
        category: Fabricate(:category),
        title: "Outside Zhejiang activity",
        tags: tags.values_at("中国", "浙江")
      )

      get "/where-is-my-friends/locations/nearby.json"

      topics = response.parsed_body.fetch("local_topics")
      expect(topics.pluck("id")).to contain_exactly(
        shanghai_topic.id,
        jiangsu_topic.id,
        zhejiang_topic.id
      )
      expect(topics.pluck("id")).not_to include(ambiguous_topic.id)
      expect(topics.pluck("activity_area")).to contain_exactly("上海", "江苏", "浙江")
      expect(response.body).not_to include("Outside Zhejiang activity")
    end

    it "expands a tighter discovery radius when it would otherwise be empty" do
      UserLocation.upsert_city_location(
        user.id,
        city: "上海",
        discovery_radius_km: 50
      )
      nearby_city = Fabricate(:user)
      UserLocation.upsert_city_location(nearby_city.id, city: "苏州")

      get "/where-is-my-friends/locations/nearby.json"

      expect(response.parsed_body).to include(
        "state" => "ready",
        "expanded_radius" => true,
        "original_radius_km" => 50,
        "expanded_radius_km" => 200
      )
      expect(
        response.parsed_body.fetch("users").pluck("username")
      ).to contain_exactly(nearby_city.username)
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

  describe "attribute filtering" do
    fab!(:gender_field) do
      field =
        UserField.create!(
          name: "性别",
          description: "Test gender field",
          field_type: "dropdown",
          editable: true
        )
      %w[男 女 其他].each { |v| field.user_field_options.create!(value: v) }
      field
    end

    fab!(:role_field) do
      field =
        UserField.create!(
          name: "属性",
          description: "Test role field",
          field_type: "dropdown",
          editable: true
        )
      %w[主动 被动 双].each { |v| field.user_field_options.create!(value: v) }
      field
    end

    before do
      sign_in(user)
      SiteSetting.where_is_my_friends_filterable_user_fields = "性别|属性"
      UserLocation.upsert_city_location(user.id, city: "上海")
    end

    it "exposes filterable fields in the index response" do
      get "/where-is-my-friends.json"

      fields = response.parsed_body.fetch("filterable_fields")
      expect(fields.length).to eq(2)

      gender = fields.find { |f| f["name"] == "性别" }
      expect(gender["key"]).to eq("user_field_#{gender_field.id}")
      expect(gender["options"]).to contain_exactly("男", "女", "其他")

      role = fields.find { |f| f["name"] == "属性" }
      expect(role["key"]).to eq("user_field_#{role_field.id}")
      expect(role["options"]).to contain_exactly("主动", "被动", "双")
    end

    it "returns empty filterable_fields when no fields are configured" do
      SiteSetting.where_is_my_friends_filterable_user_fields = ""
      get "/where-is-my-friends.json"

      expect(response.parsed_body.fetch("filterable_fields")).to eq([])
    end

    it "ignores non-dropdown user fields in the whitelist" do
      text_field =
        UserField.create!(
          name: "bio_extra",
          description: "Test text field",
          field_type: "text",
          editable: true
        )
      SiteSetting.where_is_my_friends_filterable_user_fields = "性别|bio_extra"

      get "/where-is-my-friends.json"

      fields = response.parsed_body.fetch("filterable_fields")
      expect(fields.map { |f| f["name"] }).to eq(["性别"])
    end

    it "filters nearby results by a single custom field" do
      male_user = Fabricate(:user)
      male_user.custom_fields["user_field_#{gender_field.id}"] = "男"
      male_user.save_custom_fields
      UserLocation.upsert_city_location(male_user.id, city: "上海")

      female_user = Fabricate(:user)
      female_user.custom_fields["user_field_#{gender_field.id}"] = "女"
      female_user.save_custom_fields
      UserLocation.upsert_city_location(female_user.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json",
          params: {
            filters: {
              "user_field_#{gender_field.id}" => "男"
            }
          }

      usernames = response.parsed_body.fetch("users").pluck("username")
      expect(usernames).to contain_exactly(male_user.username)
    end

    it "applies AND logic across multiple filter fields" do
      user_a = Fabricate(:user)
      user_a.custom_fields["user_field_#{gender_field.id}"] = "男"
      user_a.custom_fields["user_field_#{role_field.id}"] = "被动"
      user_a.save_custom_fields
      UserLocation.upsert_city_location(user_a.id, city: "上海")

      user_b = Fabricate(:user)
      user_b.custom_fields["user_field_#{gender_field.id}"] = "男"
      user_b.custom_fields["user_field_#{role_field.id}"] = "主动"
      user_b.save_custom_fields
      UserLocation.upsert_city_location(user_b.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json",
          params: {
            filters: {
              "user_field_#{gender_field.id}" => "男",
              "user_field_#{role_field.id}" => "被动"
            }
          }

      usernames = response.parsed_body.fetch("users").pluck("username")
      expect(usernames).to contain_exactly(user_a.username)
    end

    it "excludes users who have not filled in the filtered field" do
      filled_user = Fabricate(:user)
      filled_user.custom_fields["user_field_#{gender_field.id}"] = "男"
      filled_user.save_custom_fields
      UserLocation.upsert_city_location(filled_user.id, city: "上海")

      empty_user = Fabricate(:user)
      UserLocation.upsert_city_location(empty_user.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json",
          params: {
            filters: {
              "user_field_#{gender_field.id}" => "男"
            }
          }

      usernames = response.parsed_body.fetch("users").pluck("username")
      expect(usernames).to contain_exactly(filled_user.username)
    end

    it "rejects filter keys not in the whitelist" do
      secret_field =
        UserField.create!(
          name: "secret",
          description: "Test secret field",
          field_type: "dropdown",
          editable: true
        )
      secret_field.user_field_options.create!(value: "yes")

      other_user = Fabricate(:user)
      other_user.custom_fields["user_field_#{secret_field.id}"] = "yes"
      other_user.save_custom_fields
      UserLocation.upsert_city_location(other_user.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json",
          params: {
            filters: {
              "user_field_#{secret_field.id}" => "yes"
            }
          }

      usernames = response.parsed_body.fetch("users").pluck("username")
      expect(usernames).to include(other_user.username)
    end

    it "rejects filter values not in the field's options" do
      other_user = Fabricate(:user)
      other_user.custom_fields["user_field_#{gender_field.id}"] = "男"
      other_user.save_custom_fields
      UserLocation.upsert_city_location(other_user.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json",
          params: {
            filters: {
              "user_field_#{gender_field.id}" => "invalid_value"
            }
          }

      usernames = response.parsed_body.fetch("users").pluck("username")
      expect(usernames).to include(other_user.username)
    end

    it "serializes whitelisted custom field values on each user" do
      nearby_user = Fabricate(:user)
      nearby_user.custom_fields["user_field_#{gender_field.id}"] = "男"
      nearby_user.custom_fields["user_field_#{role_field.id}"] = "主动"
      nearby_user.custom_fields["secret_token"] = "must-not-leak"
      nearby_user.save_custom_fields
      UserLocation.upsert_city_location(nearby_user.id, city: "上海")

      get "/where-is-my-friends/locations/nearby.json"

      result = response.parsed_body.fetch("users").first
      expect(result["custom_fields"]).to eq("性别" => "男", "属性" => "主动")
      expect(response.body).not_to include("secret_token", "must-not-leak")
    end

    it "returns all users when no filters are applied" do
      3.times do
        u = Fabricate(:user)
        UserLocation.upsert_city_location(u.id, city: "上海")
      end

      get "/where-is-my-friends/locations/nearby.json"

      expect(response.parsed_body.fetch("users").length).to eq(3)
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

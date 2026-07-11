# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::EventsController do
  fab!(:user)

  before { SiteSetting.where_is_my_friends_enabled = true }

  describe "POST /where-is-my-friends/events.json" do
    it "requires login" do
      post "/where-is-my-friends/events.json",
           params: {
             event_name: "page_view"
           }

      expect(response.status).to eq(403)
    end

    it "records an allowlisted event without accepting location data" do
      sign_in(user)

      post "/where-is-my-friends/events.json",
           params: {
             event_name: "results_viewed",
             location_mode: "city",
             result_count: 7,
             city: "上海",
             latitude: 31.2304
           }

      expect(response.status).to eq(200)
      event = WhereIsMyFriendsEvent.last
      expect(event).to have_attributes(
        user_id: user.id,
        event_name: "results_viewed",
        location_mode: "city",
        result_bucket: "five_to_nineteen"
      )
      expect(event.attributes).not_to include("city", "latitude")
    end

    it "rejects unknown event names" do
      sign_in(user)

      post "/where-is-my-friends/events.json",
           params: {
             event_name: "coordinate_copied"
           }

      expect(response.status).to eq(422)
      expect(WhereIsMyFriendsEvent.count).to eq(0)
    end
  end

  describe "GET /where-is-my-friends/debug-stats.json" do
    it "allows only administrators and returns aggregate funnel metrics" do
      sign_in(user)
      get "/where-is-my-friends/debug-stats.json"
      expect(response.status).to eq(403)

      admin = Fabricate(:admin)
      sign_in(admin)
      WhereIsMyFriendsEvent.create!(user: admin, event_name: "page_view")

      get "/where-is-my-friends/debug-stats.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("funnel")).to include(
        "unique_page_visitors" => 1
      )
    end
  end

  describe "GET /where-is-my-friends.json" do
    it "suppresses small participant counts" do
      SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3
      sign_in(user)
      UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海")

      get "/where-is-my-friends.json"

      expect(response.parsed_body["active_participants"]).to eq(
        "suppressed" => true
      )
    end

    it "shows participant counts at or above the privacy threshold" do
      SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3
      sign_in(user)
      3.times do
        UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海")
      end

      get "/where-is-my-friends.json"

      expect(response.parsed_body["active_participants"]).to eq(
        "suppressed" => false,
        "count" => 3
      )
    end
  end
end

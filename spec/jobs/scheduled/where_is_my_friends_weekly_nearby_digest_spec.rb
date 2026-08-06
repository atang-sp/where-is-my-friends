# frozen_string_literal: true

RSpec.describe Jobs::WhereIsMyFriendsWeeklyNearbyDigest do
  fab!(:recipient, :user)
  subject(:job) { described_class.new }

  before do
    SiteSetting.where_is_my_friends_enabled = true
    UserLocation.upsert_city_location(
      recipient.id,
      city: "上海",
      discovery_radius_km: 100
    )
  end

  it "summarizes only recent joins in other cities inside the selected radius" do
    same_city = Fabricate(:user)
    far_city = Fabricate(:user)
    UserLocation.upsert_city_location(same_city.id, city: "上海")
    3.times do
      nearby_city = Fabricate(:user)
      UserLocation.upsert_city_location(nearby_city.id, city: "苏州")
    end
    UserLocation.upsert_city_location(far_city.id, city: "北京")

    expect { job.execute({}) }.to change { recipient.notifications.count }.by(1)

    data = JSON.parse(recipient.notifications.last.data)
    expect(data).to include(
      "message" => "where_is_my_friends.notification.nearby_weekly",
      "where_is_my_friends" => true,
      "notification_source" => "nearby_weekly"
    )
    expect(data["topic_title"]).to eq(
      I18n.t(
        "where_is_my_friends.notification.weekly_nearby_digest",
        count: 3,
        locale: recipient.effective_locale
      )
    )
  end

  it "does not expose a nearby count below the privacy threshold" do
    nearby_city = Fabricate(:user)
    UserLocation.upsert_city_location(nearby_city.id, city: "苏州")

    job.execute({})

    data = JSON.parse(recipient.notifications.last.data)
    expect(data["topic_title"]).to eq(
      I18n.t(
        "where_is_my_friends.notification.weekly_nearby_digest_suppressed",
        locale: recipient.effective_locale
      )
    )
  end

  it "skips members who disabled nearby weekly notifications" do
    recipient.user_option.update!(where_is_my_friends_notify_nearby: false)
    nearby_city = Fabricate(:user)
    UserLocation.upsert_city_location(nearby_city.id, city: "苏州")

    expect { job.execute({}) }.not_to change { recipient.notifications.count }
  end

  it "ignores joins older than the weekly window" do
    nearby_city = Fabricate(:user)
    location = UserLocation.upsert_city_location(nearby_city.id, city: "苏州")
    location.update_column(:city_joined_at, 8.days.ago)

    expect { job.execute({}) }.not_to change { recipient.notifications.count }
  end
end

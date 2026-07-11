# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::MemberJoinedNotifier do
  fab!(:joiner)
  fab!(:recipient)

  before do
    SiteSetting.where_is_my_friends_enabled = true
    UserLocation.upsert_city_location(recipient.id, city: "上海")
  end

  it "notifies active same-city members" do
    expect {
      described_class.notify!(joiner: joiner, city: "上海", city_key: "上海")
    }.to change { recipient.notifications.count }.by(1)

    notification = recipient.notifications.last
    data = JSON.parse(notification.data)
    expect(notification.notification_type).to eq(Notification.types[:custom])
    expect(data["message"]).to eq(
      "where_is_my_friends.notification.member_joined"
    )
    expect(data["display_username"]).to eq(joiner.username)
    expect(data["city"]).to eq("上海")
  end

  it "skips recipients who disabled city notifications" do
    recipient.user_option.update!(where_is_my_friends_notify_city: false)

    expect {
      described_class.notify!(joiner: joiner, city: "上海", city_key: "上海")
    }.not_to change { recipient.notifications.count }
  end

  it "caps notifications at three per recipient per day" do
    3.times do
      described_class.notify!(joiner: joiner, city: "上海", city_key: "上海")
    end

    expect {
      described_class.notify!(joiner: joiner, city: "上海", city_key: "上海")
    }.not_to change { recipient.notifications.count }
  end
end

# frozen_string_literal: true

RSpec.describe Jobs::PruneWhereIsMyFriendsData do
  it "deletes expired locations and old events while keeping current data" do
    current = UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海")
    expired = UserLocation.upsert_city_location(Fabricate(:user).id, city: "北京")
    expired.update_column(:expires_at, 1.minute.ago)
    event_user = Fabricate(:user)
    current_event =
      WhereIsMyFriendsEvent.create!(user: event_user, event_name: "page_view")
    old_event =
      WhereIsMyFriendsEvent.create!(
        user: event_user,
        event_name: "page_view",
        created_at: 91.days.ago
      )

    described_class.new.execute({})

    expect(UserLocation.exists?(current.id)).to eq(true)
    expect(UserLocation.exists?(expired.id)).to eq(false)
    expect(WhereIsMyFriendsEvent.exists?(current_event.id)).to eq(true)
    expect(WhereIsMyFriendsEvent.exists?(old_event.id)).to eq(false)
  end
end

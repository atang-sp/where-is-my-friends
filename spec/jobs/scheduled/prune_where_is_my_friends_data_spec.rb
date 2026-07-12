# frozen_string_literal: true

RSpec.describe Jobs::PruneWhereIsMyFriendsData do
  it "deletes old events while keeping recent ones and all locations" do
    location = UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海")
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

    expect(UserLocation.exists?(location.id)).to eq(true)
    expect(WhereIsMyFriendsEvent.exists?(current_event.id)).to eq(true)
    expect(WhereIsMyFriendsEvent.exists?(old_event.id)).to eq(false)
  end
end

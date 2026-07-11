# frozen_string_literal: true

RSpec.describe Jobs::PruneWhereIsMyFriendsData do
  it "deletes expired locations and keeps current locations" do
    current = UserLocation.upsert_city_location(Fabricate(:user).id, city: "上海")
    expired = UserLocation.upsert_city_location(Fabricate(:user).id, city: "北京")
    expired.update_column(:expires_at, 1.minute.ago)

    described_class.new.execute({})

    expect(UserLocation.exists?(current.id)).to eq(true)
    expect(UserLocation.exists?(expired.id)).to eq(false)
  end
end

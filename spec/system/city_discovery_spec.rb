# frozen_string_literal: true

require_relative "support/production_closure_helpers"

RSpec.describe "Local Friends city discovery",
               time: WhereIsMyFriendsProductionClosureHelpers::AS_OF do
  fab!(:viewer) do
    Fabricate(
      :user,
      last_seen_at: WhereIsMyFriendsProductionClosureHelpers::AS_OF - 1.hour
    )
  end
  fab!(:nearby_member) do
    Fabricate(
      :user,
      last_seen_at: WhereIsMyFriendsProductionClosureHelpers::AS_OF - 2.hours
    )
  end

  before { configure_production_closure_features }

  it "saves a city, shows real results, and returns to setup after removal" do
    UserLocation.upsert_city_location(nearby_member.id, city: "上海")
    sign_in(viewer)

    visit "/where-is-my-friends"

    expect(page).to have_css(
      "[data-test-participant-proof]",
      text: "Forum members have joined local discovery"
    )
    expect(page).to have_no_css(
      "[data-test-participant-proof]",
      text: /1 member/i
    )

    find("[data-test-city-input]").fill_in(with: "上海")
    find("[data-test-preview-city]").click
    expect(page).to have_css("[data-test-city-network-preview]")
    find("[data-test-join-city]").click

    expect(page).to have_css(
      "[data-test-user-card='#{nearby_member.username}']"
    )
    expect(page).to have_css("[data-test-location-mode='city']")
    expect(UserLocation.find_by(user_id: viewer.id)).to have_attributes(
      city_key: "上海",
      discovery_mode: "city"
    )

    find("[data-test-location-settings-toggle]").click
    find("[data-test-remove-location]").click

    expect(page).to have_css("[data-test-city-input]")
    expect(page).to have_no_css("[data-test-location-mode]")
    expect(UserLocation.find_by(user_id: viewer.id)).to be_nil
  end
end

# frozen_string_literal: true

require_relative "support/production_closure_helpers"

RSpec.describe WhereIsMyFriends::NextAction,
               time: WhereIsMyFriendsProductionClosureHelpers::AS_OF do
  fab!(:viewer) do
    Fabricate(
      :user,
      last_seen_at: WhereIsMyFriendsProductionClosureHelpers::AS_OF - 1.hour
    )
  end
  fab!(:candidate) do
    Fabricate(
      :user,
      last_seen_at: WhereIsMyFriendsProductionClosureHelpers::AS_OF - 2.hours
    )
  end

  before do
    configure_production_closure_features
    SiteSetting.where_is_my_friends_first_connection_enabled = true
    @network =
      prepare_recommendation_network(viewer: viewer, candidate: candidate)
  end

  it "takes a member with completed interests from one homepage action to a visible topic" do
    sign_in(viewer)
    visit "/latest"

    card = find("[data-test-first-connection-card][data-state='topic']")
    expect(card).to have_text("Start with a discussion that's easy to join")
    expect(page).to have_no_css("[data-test-community-discovery]")
    expect(page).to have_no_css("[data-test-local-friends-callout]")

    card.find("[data-test-first-connection-primary]").click

    expect(page).to have_current_path(@network.fetch(:topic).relative_url)
    expect(page).to have_text(@network.fetch(:topic).title)
  end
end

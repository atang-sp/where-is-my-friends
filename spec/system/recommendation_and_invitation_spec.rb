# frozen_string_literal: true

require_relative "support/production_closure_helpers"

RSpec.describe "Community recommendations and practice invitations",
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
    prepare_recommendation_network(viewer: viewer, candidate: candidate)
  end

  it "loads only the selected recommendation group and persists dismissals" do
    sign_in(viewer)
    recommendation_requests = track_recommendation_requests
    visit "/latest"

    expect(page).to have_css("[data-test-community-discovery]")
    expect(page).to have_no_css("[data-test-community-content]")
    expect(recommendation_requests).to be_empty

    find("[data-test-community-toggle]").click
    expect(page).to have_css("[data-test-community-topic]")
    expect(page).to have_no_css("[data-test-community-person]")
    expect(recommendation_requests.length).to eq(1)

    find("[data-test-community-group='people']").click
    member = find("[data-test-community-person='#{candidate.username}']")
    expect(page).to have_no_css("[data-test-community-topic]")
    expect(recommendation_requests.length).to eq(2)

    member.find("[data-test-community-dismiss]").click

    expect(page).to have_no_css(
      "[data-test-community-person='#{candidate.username}']"
    )
    expect(
      WhereIsMyFriendsRecommendationDismissal.exists?(
        user_id: viewer.id,
        target_type: "user",
        target_id: candidate.id
      )
    ).to eq(true)
  end

  it "hides an ineligible invitation entry and sends through the real API when enabled" do
    SiteSetting.where_is_my_friends_practice_invitations_enabled = false
    sign_in(viewer)
    visit "/where-is-my-friends/interests"

    expect(page).to have_css(
      "[data-test-recommended-user='#{candidate.username}']"
    )
    expect(page).to have_no_css("[data-test-invite-user='#{candidate.id}']")

    SiteSetting.where_is_my_friends_practice_invitations_enabled = true
    page.refresh
    find("[data-test-invite-user='#{candidate.id}']").click

    expect(page).to have_css("[data-test-practice-invitation-form]")
    find("[data-test-practice-invitation-note]").fill_in(
      with: "Bring one small kata."
    )
    find("[data-test-send-practice-invitation]").click

    invitation =
      WhereIsMyFriendsPracticeInvitation.find_by!(
        sender: viewer,
        recipient: candidate
      )
    find(".interest-onboarding__outgoing-invitations summary").click
    expect(page).to have_css(
      "[data-test-outgoing-invitation='#{invitation.id}']",
      text: candidate.username
    )
    expect(invitation).to have_attributes(
      status: "pending",
      source: "native",
      note: "Bring one small kata.",
      pm_topic_id: nil
    )
  end
end

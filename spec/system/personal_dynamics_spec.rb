# frozen_string_literal: true

require_relative "support/production_closure_helpers"

RSpec.describe "Personal dynamics",
               time: WhereIsMyFriendsProductionClosureHelpers::AS_OF do
  fab!(:member) do
    Fabricate(
      :user,
      last_seen_at: WhereIsMyFriendsProductionClosureHelpers::AS_OF - 1.hour
    )
  end

  before do
    configure_production_closure_features
    configure_dynamics_category
    member.change_trust_level!(TrustLevel[1])
  end

  it "rejects media, publishes text outside Latest, and stays private to members" do
    sign_in(member)
    visit "/u/#{member.username}/activity/dynamics"

    expect(page).to have_css("[data-test-personal-dynamics-publisher]")
    expect(page).to have_no_css(
      "[data-test-personal-dynamics-publisher] input[type='file']"
    )

    find("[data-test-personal-dynamics-input]").fill_in(
      with: "Unsafe image payload ![photo](upload://blocked.png)"
    )
    find("[data-test-personal-dynamics-publish]").click
    expect(page).to have_css("[data-test-personal-dynamics-error]")
    expect(
      TopicCustomField.where(name: WhereIsMyFriends::DynamicFeed::FIELD)
    ).to be_empty

    raw = "Planning a small text-only community practice this weekend."
    find("[data-test-personal-dynamics-input]").fill_in(with: raw)
    find("[data-test-personal-dynamics-publish]").click

    expect(page).to have_css("[data-test-personal-dynamic]", text: raw)
    dynamic_topic_id =
      TopicCustomField.where(name: WhereIsMyFriends::DynamicFeed::FIELD).pick(
        :topic_id
      )
    topic = Topic.find_by(id: dynamic_topic_id, user_id: member.id)
    expect(topic).to be_present

    visit "/latest"
    expect(page).to have_no_text(raw)

    Capybara.reset_session!
    visit topic.relative_url
    expect(page).to have_css("h1", text: /page doesn.t exist or is private/i)
  end
end

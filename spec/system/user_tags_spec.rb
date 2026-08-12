# frozen_string_literal: true

require_relative "support/production_closure_helpers"

RSpec.describe "Local Friends impression tags" do
  fab!(:viewer) { Fabricate(:user, last_seen_at: 1.hour.ago) }
  fab!(:member) { Fabricate(:user, last_seen_at: 2.hours.ago) }

  before do
    configure_production_closure_features
    SiteSetting.where_is_my_friends_user_tags_enabled = true
    SiteSetting.where_is_my_friends_user_tag_max_length = 20
    UserLocation.upsert_city_location(member.id, city: "上海")
    UserLocation.upsert_city_location(viewer.id, city: "上海")
  end

  it "proposes, approves, and shows an impression tag on the member card" do
    sign_in(viewer)

    visit "/where-is-my-friends"

    expect(page).to have_css("[data-test-user-card='#{member.username}']")
    find("[data-test-user-tag-propose='#{member.username}']").click
    find("[data-test-user-tag-input]").fill_in(with: "热心肠")
    find("[data-test-user-tag-propose-submit]").click

    expect(
      WhereIsMyFriendsUserTag.find_by(
        proposer: viewer,
        target_user: member,
        label: "热心肠"
      )
    ).to be_present

    tag =
      WhereIsMyFriendsUserTag.find_by!(
        proposer: viewer,
        target_user: member,
        label: "热心肠"
      )
    expect(tag).to be_pending

    sign_in(member)
    visit "/where-is-my-friends/tags"

    expect(page).to have_css("[data-test-user-tag-pending-item='热心肠']")
    find("[data-test-user-tag-approve='热心肠']").click
    expect(page).to have_css("[data-test-user-tag-managed-item='热心肠']")
    expect(tag.reload).to be_approved

    sign_in(viewer)
    visit "/where-is-my-friends"

    expect(page).to have_css("[data-test-user-tag='热心肠']")
  end
end

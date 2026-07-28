# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LegacyPracticeBookmarksController do
  fab!(:user)
  fab!(:target, :user)
  fab!(:other_user, :user)

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    sign_in(user)
  end

  it "shows only the current member's private legacy bookmarks" do
    own = create_bookmark(user: user, target: target)
    create_bookmark(user: other_user, target: user)

    get "/where-is-my-friends/legacy-practice-bookmarks.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("bookmarks").pluck("id")).to eq([own.id])
    expect(response.parsed_body.dig("bookmarks", 0, "target")).to include(
      "id" => target.id,
      "username" => target.username
    )
  end

  it "reconfirms or dismisses a bookmark without sending an invitation or notification" do
    reconfirmed = create_bookmark(user: user, target: target)
    dismissed = create_bookmark(user: user, target: other_user)
    notification_count = Notification.count

    put "/where-is-my-friends/legacy-practice-bookmarks/#{reconfirmed.id}/reconfirm.json"
    expect(response.status).to eq(200)
    expect(reconfirmed.reload).to have_attributes(
      state: "reconfirmed",
      confirmed_at: be_present
    )

    put "/where-is-my-friends/legacy-practice-bookmarks/#{dismissed.id}/dismiss.json"
    expect(response.status).to eq(200)
    expect(dismissed.reload).to have_attributes(
      state: "dismissed",
      dismissed_at: be_present
    )

    expect(WhereIsMyFriendsPracticeInvitation.count).to eq(0)
    expect(Notification.count).to eq(notification_count)
  end

  it "does not let another member act on a private bookmark" do
    bookmark = create_bookmark(user: other_user, target: target)

    put "/where-is-my-friends/legacy-practice-bookmarks/#{bookmark.id}/reconfirm.json"

    expect(response.status).to eq(404)
    expect(bookmark.reload.state).to eq("needs_reconfirmation")
  end

  private

  def create_bookmark(user:, target:)
    WhereIsMyFriendsLegacyPracticeBookmark.create!(
      user: user,
      target_user: target,
      state: "needs_reconfirmation",
      source_created_at: 10.days.ago,
      mutual_history: false
    )
  end
end

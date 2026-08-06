# frozen_string_literal: true

RSpec.describe Jobs::WhereIsMyFriendsProfileInvite do
  subject(:job) { described_class.new }

  fab!(:recipient, :user)

  before do
    SiteSetting.where_is_my_friends_enabled = true
    recipient.user_profile.update!(location: "上海")
  end

  it "uses generic copy when the nearby count is below the privacy threshold" do
    nearby_user = Fabricate(:user)
    UserLocation.upsert_city_location(nearby_user.id, city: "上海")

    expect { job.execute({}) }.to change { Post.count }.by(1)

    expect(Post.last.raw).to include(
      I18n.t(
        "where_is_my_friends.notification.profile_location_invite_suppressed",
        city: "上海",
        locale: recipient.effective_locale
      )
    )
    expect(Post.last.raw).not_to include("1 forum member")
  end

  it "does not fabricate a member count when nobody has joined" do
    expect { job.execute({}) }.to change { Post.count }.by(1)

    expect(Post.last.raw).to include(
      I18n.t(
        "where_is_my_friends.notification.profile_location_invite_empty",
        city: "上海",
        locale: recipient.effective_locale
      )
    )
    expect(Post.last.raw).not_to include("1 forum member")
  end
end

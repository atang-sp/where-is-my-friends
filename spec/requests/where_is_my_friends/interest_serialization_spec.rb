# frozen_string_literal: true
RSpec.describe "Where Is My Friends interest serialization" do
  fab!(:viewer, :user)
  fab!(:member, :user)
  fab!(:ruby_tag) { Fabricate(:tag, name: "ruby") }
  fab!(:private_tag) { Fabricate(:tag, name: "private-hobby") }

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    SiteSetting.hide_new_user_profiles = false
    viewer.change_trust_level!(TrustLevel[1])
    member.change_trust_level!(TrustLevel[1])
    sign_in(viewer)
  end

  it "exposes onboarding state only to the current member" do
    get "/session/current.json"

    expect(
      response.parsed_body.dig(
        "current_user",
        "where_is_my_friends_interest_onboarding_state"
      )
    ).to eq("pending")

    WhereIsMyFriendsInterestProfile.create!(
      user: viewer,
      personalization_enabled: false,
      dismissed_at: Time.current
    )
    get "/session/current.json"

    expect(
      response.parsed_body.dig(
        "current_user",
        "where_is_my_friends_interest_onboarding_state"
      )
    ).to eq("dismissed")
  end

  it "shows only explicitly public interests on member cards" do
    viewer_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: viewer,
        purpose: "connect",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    viewer_profile.interests.create!(tag: ruby_tag, position: 0)
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: member,
        purpose: "connect",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: true,
        completed_at: Time.current
      )
    profile.interests.create!(tag: ruby_tag, position: 0)

    get "/u/#{member.username}/card.json"

    expect(
      response.parsed_body.dig("user", "where_is_my_friends_public_interests")
    ).to eq([{ "id" => ruby_tag.id, "name" => "ruby" }])
    expect(
      response.parsed_body.dig(
        "user",
        "where_is_my_friends_practice_invitation_interests"
      )
    ).to eq([{ "id" => ruby_tag.id, "name" => "ruby" }])
  end

  it "never serializes private interests or purpose without explicit consent" do
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: member,
        purpose: "ask",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: false,
        completed_at: Time.current
      )
    profile.interests.create!(tag: private_tag, position: 0)

    get "/u/#{member.username}/card.json"

    user_json = response.parsed_body.fetch("user")
    expect(user_json["where_is_my_friends_public_interests"]).to eq([])
    expect(
      user_json["where_is_my_friends_practice_invitation_interests"]
    ).to eq([])
    expect(user_json).not_to include(
      "where_is_my_friends_interests",
      "where_is_my_friends_purpose"
    )
  end

  it "does not expose a restricted tag even when profile display is enabled" do
    full = TagGroupPermission.permission_types[:full]
    restricted_group =
      Fabricate(:tag_group, name: "Staff interests", tags: [private_tag])
    restricted_group.permissions = [[Group::AUTO_GROUPS[:staff], full]]
    restricted_group.save!
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: member,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: true,
        completed_at: Time.current
      )
    profile.interests.create!(tag: private_tag, position: 0)

    get "/u/#{member.username}/card.json"

    expect(
      response.parsed_body.dig("user", "where_is_my_friends_public_interests")
    ).to eq([])
  end

  it "stops exposing public interests when interest recommendations are disabled" do
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: member,
        purpose: "connect",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: true,
        completed_at: Time.current
      )
    profile.interests.create!(tag: ruby_tag, position: 0)
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = false

    get "/u/#{member.username}/card.json"

    expect(
      response.parsed_body.dig("user", "where_is_my_friends_public_interests")
    ).to eq([])
  end

  it "stops exposing invitation interests when practice invitations are disabled" do
    viewer_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: viewer,
        purpose: "connect",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    viewer_profile.interests.create!(tag: ruby_tag, position: 0)
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: member,
        purpose: "connect",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: true,
        completed_at: Time.current
      )
    profile.interests.create!(tag: ruby_tag, position: 0)
    SiteSetting.where_is_my_friends_practice_invitations_enabled = false

    get "/u/#{member.username}/card.json"

    expect(
      response.parsed_body.dig(
        "user",
        "where_is_my_friends_practice_invitation_interests"
      )
    ).to eq([])
  end
end

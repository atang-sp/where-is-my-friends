# frozen_string_literal: true
RSpec.describe WhereIsMyFriends::PracticeInvitationsController do
  fab!(:sender, :user)
  fab!(:recipient, :user)
  fab!(:other_user, :user)
  fab!(:ruby_tag) { Fabricate(:tag, name: "ruby") }
  fab!(:design_tag) { Fabricate(:tag, name: "design") }

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    SiteSetting.where_is_my_friends_practice_invitations_enabled = true
    SiteSetting.where_is_my_friends_practice_invitation_min_trust_level = 1
    SiteSetting.where_is_my_friends_practice_invitation_daily_limit = 5
    SiteSetting.tagging_enabled = true
    SiteSetting.hide_new_user_profiles = false

    sender.change_trust_level!(TrustLevel[1])
    recipient.change_trust_level!(TrustLevel[1])
    other_user.change_trust_level!(TrustLevel[1])
    sender.user_option.update!(
      where_is_my_friends_accept_practice_invitations: true
    )
    recipient.user_option.update!(
      where_is_my_friends_accept_practice_invitations: true
    )
    other_user.user_option.update!(
      where_is_my_friends_accept_practice_invitations: true
    )

    create_interest_profile(sender, ruby_tag)
    create_interest_profile(recipient, ruby_tag, public: true)
    create_interest_profile(other_user, ruby_tag, public: true)
    sign_in(sender)
  end

  it "creates one private, one-to-one invitation with optional scheduling context" do
    proposed_at = 2.days.from_now.change(sec: 0)

    expect do
      post "/where-is-my-friends/practice-invitations.json",
           params: {
             recipient_id: recipient.id,
             tag_id: ruby_tag.id,
             proposed_at: proposed_at.iso8601,
             note: "Bring one small kata."
           }
    end.to change { WhereIsMyFriendsPracticeInvitation.count }.by(1)

    expect(response.status).to eq(200)
    invitation = WhereIsMyFriendsPracticeInvitation.last
    expect(invitation).to have_attributes(
      sender: sender,
      recipient: recipient,
      tag: ruby_tag,
      status: "pending",
      note: "Bring one small kata.",
      proposed_at: proposed_at,
      pm_topic_id: nil
    )
    expect(response.parsed_body.dig("invitation", "preset_message")).to include(
      "ruby"
    )
    expect(
      Notification.exists?(
        user: recipient,
        notification_type: Notification.types[:custom]
      )
    ).to eq(true)
    expect(Topic.where(archetype: Archetype.private_message)).to be_empty
  end

  it "lets only the recipient accept and creates a PM with exactly two participants" do
    invitation = create_invitation
    sign_in(recipient)

    put "/where-is-my-friends/practice-invitations/#{invitation.id}/accept.json"

    expect(response.status).to eq(200)
    expect(invitation.reload).to have_attributes(
      status: "accepted",
      responded_at: be_present,
      pm_topic_id: be_present
    )
    topic = Topic.find(invitation.pm_topic_id)
    expect(topic.archetype).to eq(Archetype.private_message)
    expect(topic.topic_allowed_users.pluck(:user_id)).to contain_exactly(
      sender.id,
      recipient.id
    )
    expect(topic.first_post.raw).to include("ruby")

    sign_in(other_user)
    put "/where-is-my-friends/practice-invitations/#{invitation.id}/accept.json"
    expect(response.status).to eq(404)
  end

  it "saves recognized safety items and serializes them in responses" do
    post "/where-is-my-friends/practice-invitations.json",
         params: {
           recipient_id: recipient.id,
           tag_id: ruby_tag.id,
           safety_items: %w[ssc_consensus pure_practice unrecognized_flag]
         }

    expect(response.status).to eq(200)
    invitation = WhereIsMyFriendsPracticeInvitation.last
    expect(invitation.safety_items).to contain_exactly(
      "ssc_consensus",
      "pure_practice"
    )
    expect(
      response.parsed_body.dig("invitation", "safety_items")
    ).to contain_exactly("ssc_consensus", "pure_practice")
  end

  it "embeds the structured safety agreement protocol into the accepted PM" do
    invitation =
      create_invitation(
        safety_items: %w[ssc_consensus pure_practice safeword_mechanism]
      )
    sign_in(recipient)

    put "/where-is-my-friends/practice-invitations/#{invitation.id}/accept.json"

    expect(response.status).to eq(200)
    topic = Topic.find(invitation.reload.pm_topic_id)
    expect(topic.first_post.raw).to include("双方安全与实践共识")
    expect(topic.first_post.raw).to include("SSC")
    expect(topic.first_post.raw).to include("纯粹 SP 交流")
    expect(topic.first_post.raw).to include("安全词")
  end

  it "rechecks communication blocks before accepting an invitation" do
    invitation = create_invitation
    MutedUser.create!(user: sender, muted_user: recipient)
    sign_in(recipient)

    put "/where-is-my-friends/practice-invitations/#{invitation.id}/accept.json"

    expect(response.status).to eq(422)
    expect(invitation.reload).to be_pending
    expect(Topic.where(archetype: Archetype.private_message)).to be_empty
  end

  it "supports decline and ignore without creating a PM" do
    declined = create_invitation(recipient: recipient)
    ignored = create_invitation(recipient: other_user)

    sign_in(recipient)
    put "/where-is-my-friends/practice-invitations/#{declined.id}/decline.json"
    expect(response.status).to eq(200)
    expect(declined.reload.status).to eq("declined")

    sign_in(other_user)
    put "/where-is-my-friends/practice-invitations/#{ignored.id}/ignore.json"
    expect(response.status).to eq(200)
    expect(ignored.reload.status).to eq("ignored")
    expect(Topic.where(archetype: Archetype.private_message)).to be_empty
  end

  it "lists only invitations involving the current member" do
    incoming = create_invitation(sender: other_user, recipient: sender)
    outgoing = create_invitation(sender: sender, recipient: recipient)
    create_invitation(sender: recipient, recipient: other_user)

    get "/where-is-my-friends/practice-invitations.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("incoming").pluck("id")).to eq(
      [incoming.id]
    )
    expect(response.parsed_body.fetch("outgoing").pluck("id")).to eq(
      [outgoing.id]
    )
  end

  it "keeps the interest label as history after an administrator deletes the tag" do
    post_invitation
    invitation = WhereIsMyFriendsPracticeInvitation.last

    ruby_tag.destroy!
    get "/where-is-my-friends/practice-invitations.json"

    expect(response.status).to eq(200)
    expect(invitation.reload).to have_attributes(
      tag_id: nil,
      interest_name: "ruby"
    )
    expect(response.parsed_body.dig("outgoing", 0, "interest")).to eq(
      "id" => nil,
      "name" => "ruby"
    )
  end

  it "rejects low-trust, opted-out, blocked, invalid-interest, and duplicate invites" do
    sender.change_trust_level!(TrustLevel[0])
    post_invitation
    expect(response.status).to eq(403)

    sender.change_trust_level!(TrustLevel[1])
    recipient.user_option.update!(
      where_is_my_friends_accept_practice_invitations: false
    )
    post_invitation
    expect(response.status).to eq(422)

    recipient.user_option.update!(
      where_is_my_friends_accept_practice_invitations: true
    )
    MutedUser.create!(user: recipient, muted_user: sender)
    post_invitation
    expect(response.status).to eq(422)
    MutedUser.delete_all

    post_invitation(tag: design_tag)
    expect(response.status).to eq(422)

    post_invitation
    expect(response.status).to eq(200)
    sign_in(recipient)
    post_invitation(recipient: sender)
    expect(response.status).to eq(422)
  end

  it "honors the recipient private-message allowlist before creating an invitation" do
    recipient.user_option.update!(enable_allowed_pm_users: true)

    post_invitation

    expect(response.status).to eq(422)
    expect(WhereIsMyFriendsPracticeInvitation.count).to eq(0)

    AllowedPmUser.create!(user: recipient, allowed_pm_user: sender)
    post_invitation

    expect(response.status).to eq(200)
  end

  it "enforces the configured daily invitation limit" do
    SiteSetting.where_is_my_friends_practice_invitation_daily_limit = 1

    post_invitation(recipient: recipient)
    expect(response.status).to eq(200)
    post_invitation(recipient: other_user)
    expect(response.status).to eq(429)
  end

  it "reports common public interests for the profile entry point" do
    get "/where-is-my-friends/practice-invitations/availability.json",
        params: {
          username: recipient.username
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "recipient_id" => recipient.id,
      "username" => recipient.username,
      "interests" => [{ "id" => ruby_tag.id, "name" => "ruby" }]
    )
  end

  it "returns no member details when the profile target is unavailable" do
    recipient.user_option.update!(
      where_is_my_friends_accept_practice_invitations: false
    )

    get "/where-is-my-friends/practice-invitations/availability.json",
        params: {
          username: recipient.username
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq("available" => false, "interests" => [])
  end

  it "marks only the exact invitation notification as read" do
    invitation = create_invitation
    exact =
      Notification.create!(
        user: recipient,
        notification_type: Notification.types[:custom],
        data: {
          message:
            "where_is_my_friends.practice_invitations.notification_message",
          practice_invitation_id: invitation.id
        }.to_json
      )
    prefix_collision =
      Notification.create!(
        user: recipient,
        notification_type: Notification.types[:custom],
        data: {
          message:
            "where_is_my_friends.practice_invitations.notification_message",
          practice_invitation_id: "#{invitation.id}0".to_i
        }.to_json
      )
    sign_in(recipient)

    put "/where-is-my-friends/practice-invitations/#{invitation.id}/decline.json"

    expect(response.status).to eq(200)
    expect(exact.reload).to be_read
    expect(prefix_collision.reload).not_to be_read
  end

  private

  def create_interest_profile(user, tag, public: false)
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: user,
        purpose: "connect",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: public,
        completed_at: Time.current
      )
    profile.interests.create!(tag: tag, position: 0)
    profile
  end

  def create_invitation(
    sender: self.sender,
    recipient: self.recipient,
    safety_items: []
  )
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: sender,
      recipient: recipient,
      tag: ruby_tag,
      status: "pending",
      safety_items: safety_items
    )
  end

  def post_invitation(recipient: self.recipient, tag: ruby_tag)
    post "/where-is-my-friends/practice-invitations.json",
         params: {
           recipient_id: recipient.id,
           tag_id: tag.id
         }
  end
end

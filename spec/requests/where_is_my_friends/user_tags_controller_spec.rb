# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::UserTagsController do
  fab!(:proposer) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:target) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:third) { Fabricate(:user, trust_level: TrustLevel[1]) }

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_user_tags_enabled = true
    SiteSetting.where_is_my_friends_user_tag_max_length = 20
    sign_in(proposer) unless RSpec.current_example.metadata[:anonymous]
  end

  def proposed_tag
    WhereIsMyFriendsUserTag.find_by(
      proposer_id: proposer.id,
      target_user_id: target.id
    )
  end

  describe "POST create" do
    it "proposes a tag and notifies the target" do
      post "/where-is-my-friends/user-tags.json",
           params: {
             username: target.username,
             label: "热心肠"
           }

      expect(response.status).to eq(200)
      tag = proposed_tag
      expect(tag).to be_present
      expect(tag).to be_pending
      notification = Notification.find_by(user: target)
      expect(notification).to be_present
      expect(
        WhereIsMyFriendsEvent.exists?(event_name: "user_tag_proposed")
      ).to be(true)
    end

    it "rejects a tag on yourself" do
      post "/where-is-my-friends/user-tags.json",
           params: {
             username: proposer.username,
             label: "热心肠"
           }

      expect(response.status).to eq(403)
    end

    it "rejects an over-length label" do
      post "/where-is-my-friends/user-tags.json",
           params: {
             username: target.username,
             label: "热" * 21
           }

      expect(response.status).to eq(422)
    end

    it "rejects when the target opted out" do
      target.user_option.update!(where_is_my_friends_accept_user_tags: false)
      post "/where-is-my-friends/user-tags.json",
           params: {
             username: target.username,
             label: "热心肠"
           }

      expect(response.status).to eq(403)
    end

    it "rejects duplicate pending labels from the same proposer" do
      WhereIsMyFriendsUserTag.create!(
        proposer: proposer,
        target_user: target,
        label: "热心肠"
      )
      post "/where-is-my-friends/user-tags.json",
           params: {
             username: target.username,
             label: "热心肠"
           }

      expect(response.status).to eq(422)
    end

    it "enforces the daily proposal limit" do
      limit = SiteSetting.where_is_my_friends_user_tag_daily_proposal_limit
      limit.times do |i|
        WhereIsMyFriendsUserTag.create!(
          proposer: proposer,
          target_user: Fabricate(:user, trust_level: TrustLevel[1]),
          label: "标签#{i}"
        )
      end

      post "/where-is-my-friends/user-tags.json",
           params: {
             username: target.username,
             label: "热心肠"
           }

      expect(response.status).to eq(429)
    end

    it "blocks proposals toward a muted relationship" do
      MutedUser.create!(user: proposer, muted_user: target)
      post "/where-is-my-friends/user-tags.json",
           params: {
             username: target.username,
             label: "热心肠"
           }

      expect(response.status).to eq(403)
    end

    it "fails closed when the feature is disabled" do
      SiteSetting.where_is_my_friends_user_tags_enabled = false
      post "/where-is-my-friends/user-tags.json",
           params: {
             username: target.username,
             label: "热心肠"
           }

      expect(response.status).to eq(404)
    end
  end

  describe "GET index" do
    it "returns only approved tags with endorsement state" do
      WhereIsMyFriendsUserTag.create!(
        proposer: target,
        target_user: proposer,
        label: "还没批准"
      )
      approved =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: proposer,
          label: "热心肠"
        ).tap(&:approve!)
      WhereIsMyFriendsTagEndorsement.create!(user: third, tag: approved)

      get "/where-is-my-friends/user-tags.json",
          params: {
            username: proposer.username
          }

      expect(response.status).to eq(200)
      tags = response.parsed_body["user_tags"]
      expect(tags.length).to eq(1)
      expect(tags.first["label"]).to eq("热心肠")
      expect(tags.first["endorser_count"]).to eq(1)
      expect(tags.first["endorsed_by_me"]).to be(false)
    end

    it "shows endorsed_by_me when the viewer endorsed" do
      approved =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: third,
          label: "热心肠"
        ).tap(&:approve!)
      WhereIsMyFriendsTagEndorsement.create!(user: proposer, tag: approved)

      get "/where-is-my-friends/user-tags.json",
          params: {
            username: third.username
          }

      expect(response.parsed_body["user_tags"].first["endorsed_by_me"]).to be(
        true
      )
    end

    it "never leaks pending tags proposed about the viewer to others" do
      WhereIsMyFriendsUserTag.create!(
        proposer: target,
        target_user: proposer,
        label: "待批准秘密标签"
      )

      get "/where-is-my-friends/user-tags.json",
          params: {
            username: proposer.username
          }

      labels = response.parsed_body["user_tags"].map { |t| t["label"] }
      expect(labels).not_to include("待批准秘密标签")
    end

    it "returns an empty list for a blocked relationship" do
      WhereIsMyFriendsUserTag.create!(
        proposer: proposer,
        target_user: third,
        label: "热心肠"
      ).tap(&:approve!)
      MutedUser.create!(user: proposer, muted_user: third)

      get "/where-is-my-friends/user-tags.json",
          params: {
            username: third.username
          }

      expect(response.parsed_body["user_tags"]).to eq([])
    end
  end

  describe "GET mine" do
    it "lists pending tags with the proposer identity" do
      tag =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: proposer,
          label: "热心肠"
        )

      get "/where-is-my-friends/user-tags/mine.json"

      expect(response.status).to eq(200)
      pending = response.parsed_body["pending"]
      expect(pending.length).to eq(1)
      expect(pending.first["label"]).to eq("热心肠")
      expect(pending.first["proposer"]["username"]).to eq(target.username)
      expect(response.parsed_body["accepting_user_tags"]).to be(true)
    end
  end

  describe "PUT approve / reject / remove" do
    it "approves a pending tag addressed to me" do
      tag =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: proposer,
          label: "热心肠"
        )

      put "/where-is-my-friends/user-tags/#{tag.id}/approve.json"

      expect(response.status).to eq(200)
      expect(tag.reload.status).to eq("approved")
      expect(
        WhereIsMyFriendsEvent.exists?(event_name: "user_tag_approved")
      ).to be(true)
    end

    it "rejects a pending tag addressed to me" do
      tag =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: proposer,
          label: "热心肠"
        )

      put "/where-is-my-friends/user-tags/#{tag.id}/reject.json"

      expect(response.status).to eq(200)
      expect(tag.reload.status).to eq("rejected")
    end

    it "removes an approved tag addressed to me" do
      tag =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: proposer,
          label: "热心肠"
        ).tap(&:approve!)

      put "/where-is-my-friends/user-tags/#{tag.id}/remove.json"

      expect(response.status).to eq(200)
      expect(tag.reload.status).to eq("removed")
    end

    it "forbids a non-recipient from approving" do
      tag =
        WhereIsMyFriendsUserTag.create!(
          proposer: proposer,
          target_user: target,
          label: "热心肠"
        )

      put "/where-is-my-friends/user-tags/#{tag.id}/approve.json"

      expect(response.status).to eq(422)
      expect(tag.reload.status).to eq("pending")
    end

    it "forbids re-processing an already handled tag" do
      tag =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: proposer,
          label: "热心肠"
        ).tap(&:approve!)

      put "/where-is-my-friends/user-tags/#{tag.id}/approve.json"

      expect(response.status).to eq(422)
    end
  end

  describe "POST / DELETE endorse" do
    fab!(:approved_tag) do
      WhereIsMyFriendsUserTag.create!(
        proposer: target,
        target_user: third,
        label: "热心肠"
      ).tap(&:approve!)
    end

    it "endorses an approved tag" do
      post "/where-is-my-friends/user-tags/#{approved_tag.id}/endorse.json"

      expect(response.status).to eq(200)
      expect(
        WhereIsMyFriendsTagEndorsement.exists?(
          tag: approved_tag,
          user: proposer
        )
      ).to be(true)
      expect(
        WhereIsMyFriendsEvent.exists?(event_name: "user_tag_endorsed")
      ).to be(true)
    end

    it "refuses to endorse a pending tag" do
      pending_tag =
        WhereIsMyFriendsUserTag.create!(
          proposer: target,
          target_user: proposer,
          label: "还没批准"
        )
      post "/where-is-my-friends/user-tags/#{pending_tag.id}/endorse.json"

      expect(response.status).to eq(422)
    end

    it "unendorses a previously endorsed tag" do
      WhereIsMyFriendsTagEndorsement.create!(user: proposer, tag: approved_tag)

      delete "/where-is-my-friends/user-tags/#{approved_tag.id}/endorse.json"

      expect(response.status).to eq(200)
      expect(
        WhereIsMyFriendsTagEndorsement.exists?(
          tag: approved_tag,
          user: proposer
        )
      ).to be(false)
    end
  end

  describe "authentication" do
    it "requires login", :anonymous do
      get "/where-is-my-friends/user-tags.json",
          params: {
            username: target.username
          }
      expect(response.status).to eq(403)
    end
  end
end

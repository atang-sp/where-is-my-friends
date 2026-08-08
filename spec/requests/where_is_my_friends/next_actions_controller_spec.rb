# frozen_string_literal: true

module WhereIsMyFriends
  module NextActionSpecHelpers
    def complete_interest_profile
      profile =
        WhereIsMyFriendsInterestProfile.create!(
          user: user,
          purpose: "learn",
          personalization_enabled: true,
          recommendable: true,
          completed_at: Time.current
        )
      [
        interest,
        design_interest,
        community_interest
      ].each_with_index do |tag, index|
        profile.interests.create!(tag: tag, position: index)
      end
      profile
    end

    def create_accepted_conversations(count)
      count.times do |index|
        recipient = Fabricate(:user)
        accepted_at = (index + 1).hours.ago
        first_post =
          Fabricate(
            :private_message_post,
            user: recipient,
            recipient: user,
            post_number: 1,
            created_at: accepted_at
          )
        WhereIsMyFriendsPracticeInvitation.create!(
          sender: user,
          recipient: recipient,
          interest_name: "shared-interest",
          status: "accepted",
          responded_at: accepted_at,
          pm_topic: first_post.topic
        )
      end
    end

    def next_action_query_count
      queries =
        ActiveRecord::Base.uncached do
          track_sql_queries do
            WhereIsMyFriends::NextAction.new(
              user: user,
              guardian: Guardian.new(user),
              as_of: Time.current
            ).call
          end
        end
      queries.grep(
        /where_is_my_friends_practice_invitations|FROM "topics"|FROM "posts"/
      ).length
    end
  end
end

RSpec.describe WhereIsMyFriends::NextActionsController do
  include WhereIsMyFriends::NextActionSpecHelpers

  fab!(:user)
  fab!(:sender, :user)
  fab!(:outsider, :user)
  fab!(:interest) { Fabricate(:tag, name: "ruby") }
  fab!(:design_interest) { Fabricate(:tag, name: "design") }
  fab!(:community_interest) { Fabricate(:tag, name: "community") }

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_first_connection_enabled = true
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    SiteSetting.where_is_my_friends_practice_invitations_enabled = true
    SiteSetting.where_is_my_friends_interest_tags = "ruby|design|community"
    SiteSetting.tagging_enabled = true
    SiteSetting.hide_new_user_profiles = false
    user.change_trust_level!(TrustLevel[0])
    sender.change_trust_level!(TrustLevel[1])
    sender.update!(last_seen_at: 1.hour.ago)
    sign_in(user) unless RSpec.current_example.metadata[:anonymous]
  end

  it "fails closed for anonymous users and disabled feature switches",
     :anonymous do
    get "/where-is-my-friends/next-action.json"
    expect(response.status).to eq(403)

    sign_in(user)
    SiteSetting.where_is_my_friends_enabled = false
    get "/where-is-my-friends/next-action.json"
    expect(response.status).to eq(404)

    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_first_connection_enabled = false
    get "/where-is-my-friends/next-action.json"
    expect(response.status).to eq(404)
  end

  it "returns an explicit empty domain result when the action surface is unavailable" do
    SiteSetting.where_is_my_friends_enabled = false

    result =
      WhereIsMyFriends::NextAction.new(
        user: user,
        guardian: Guardian.new(user),
        as_of: Time.current
      ).call

    expect(result).to eq(
      state: "empty",
      algorithm_version: "first_connection_v1"
    )
  end

  it "skips invitation and recommendation actions when their settings are off" do
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: sender,
      recipient: user,
      tag: interest,
      interest_name: interest.name
    )
    SiteSetting.where_is_my_friends_practice_invitations_enabled = false

    get "/where-is-my-friends/next-action.json"
    expect(response.parsed_body.fetch("state")).to eq("onboarding")

    SiteSetting.where_is_my_friends_interest_onboarding_enabled = false
    get "/where-is-my-friends/next-action.json"
    expect(response.parsed_body.fetch("state")).to eq("local_discovery")
  end

  it "guides a member with pending interests to the existing onboarding flow" do
    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "state" => "onboarding",
      "title_key" => "where_is_my_friends.first_connection.onboarding.title",
      "description_key" =>
        "where_is_my_friends.first_connection.onboarding.description",
      "primary_action" => {
        "kind" => "open_onboarding",
        "label_key" => "where_is_my_friends.first_connection.onboarding.cta",
        "url" => "/where-is-my-friends/interests"
      },
      "algorithm_version" => "first_connection_v1"
    )
  end

  it "prioritizes the current member's pending incoming invitation without exposing it" do
    invitation =
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: sender,
        recipient: user,
        tag: interest,
        interest_name: interest.name,
        note: "Private invitation note"
      )

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "state" => "incoming_invitation",
      "title_key" =>
        "where_is_my_friends.first_connection.incoming_invitation.title",
      "description_key" =>
        "where_is_my_friends.first_connection.incoming_invitation.description",
      "primary_action" => {
        "kind" => "open_invitation",
        "label_key" =>
          "where_is_my_friends.first_connection.incoming_invitation.cta",
        "url" => "/where-is-my-friends/interests"
      },
      "algorithm_version" => "first_connection_v1"
    )
    expect(response.body).not_to include(
      invitation.id.to_s,
      invitation.note,
      sender.username,
      interest.name
    )
  end

  it "prompts the original sender to continue an accessible recently accepted PM" do
    accepted_at = 1.day.ago
    first_post =
      Fabricate(
        :private_message_post,
        user: sender,
        recipient: user,
        post_number: 1,
        created_at: accepted_at
      )
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: user,
      recipient: sender,
      tag: interest,
      interest_name: interest.name,
      status: "accepted",
      responded_at: accepted_at,
      pm_topic: first_post.topic
    )

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "state" => "continue_conversation",
      "title_key" =>
        "where_is_my_friends.first_connection.continue_conversation.title",
      "description_key" =>
        "where_is_my_friends.first_connection.continue_conversation.description",
      "primary_action" => {
        "kind" => "open_conversation",
        "label_key" =>
          "where_is_my_friends.first_connection.continue_conversation.cta",
        "url" => "/t/#{first_post.topic_id}"
      },
      "algorithm_version" => "first_connection_v1"
    )
    expect(response.body).not_to include(first_post.raw, sender.username)
  end

  it "stops prompting after the original sender replies in the accepted PM" do
    accepted_at = 1.day.ago
    first_post =
      Fabricate(
        :private_message_post,
        user: sender,
        recipient: user,
        post_number: 1,
        created_at: accepted_at
      )
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: user,
      recipient: sender,
      tag: interest,
      interest_name: interest.name,
      status: "accepted",
      responded_at: accepted_at,
      pm_topic: first_post.topic
    )
    Fabricate(
      :post,
      topic: first_post.topic,
      user: user,
      post_number: 2,
      created_at: accepted_at + 1.hour
    )

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("state")).to eq("onboarding")
  end

  it "skips an accepted PM that the current member can no longer access" do
    accepted_at = 1.day.ago
    first_post =
      Fabricate(
        :private_message_post,
        user: sender,
        recipient: outsider,
        post_number: 1,
        created_at: accepted_at
      )
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: user,
      recipient: sender,
      tag: interest,
      interest_name: interest.name,
      status: "accepted",
      responded_at: accepted_at,
      pm_topic: first_post.topic
    )
    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("state")).to eq("onboarding")
  end

  it "offers an unjoined waiting discussion when the member has no recent public interaction" do
    complete_interest_profile
    topic =
      Fabricate(
        :topic,
        user: sender,
        title: "A fresh Ruby question waiting for a first reply",
        tags: [interest],
        created_at: 2.hours.ago,
        bumped_at: 2.hours.ago
      )
    topic.update_columns(posts_count: 1, highest_post_number: 1)

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "state" => "topic",
      "title_key" => "where_is_my_friends.first_connection.topic.title",
      "description_key" =>
        "where_is_my_friends.first_connection.topic.description",
      "primary_action" => {
        "kind" => "open_topic",
        "label_key" => "where_is_my_friends.first_connection.topic.cta",
        "url" => "/t/#{topic.slug}/#{topic.id}"
      },
      "secondary_action" => {
        "kind" => "open_recommendations",
        "label_key" => "where_is_my_friends.first_connection.more",
        "url" => "/where-is-my-friends/interests"
      },
      "recommendation_group" => "topics",
      "algorithm_version" => "first_connection_v1"
    )
    expect(response.body).not_to include(
      "matching_interests",
      "reason_interests",
      "invitation_interests"
    )
  end

  it "selects awaiting-response before higher-ranked unread recommendations" do
    complete_interest_profile
    4.times do |index|
      unread =
        Fabricate(
          :topic,
          user: sender,
          title: "Popular matched discussion #{index}",
          tags: [interest, design_interest, community_interest],
          created_at: 5.days.ago,
          bumped_at: index.minutes.ago,
          like_count: 100 - index
        )
      3.times { Fabricate(:post, topic: unread, user: sender) }
      unread.update_columns(posts_count: 4, highest_post_number: 4)
    end
    waiting =
      Fabricate(
        :topic,
        user: sender,
        title: "A small Ruby question still waiting for a reply",
        tags: [interest],
        created_at: 2.hours.ago,
        bumped_at: 2.hours.ago
      )
    waiting.update_columns(posts_count: 1, highest_post_number: 1)

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "state" => "topic",
      "primary_action" => include("url" => "/t/#{waiting.slug}/#{waiting.id}")
    )
  end

  it "offers a recommended member through a public topic after recent public interaction" do
    complete_interest_profile
    candidate_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: sender,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    candidate_profile.interests.create!(tag: interest, position: 0)
    candidate_topic =
      Fabricate(
        :topic,
        user: sender,
        title: "Ruby practices from the community",
        tags: [interest],
        created_at: 5.days.ago,
        bumped_at: 1.day.ago
      )
    Fabricate(
      :post,
      topic: candidate_topic,
      user: sender,
      post_number: 1,
      created_at: 5.days.ago
    )
    public_topic = Fabricate(:topic, user: outsider, created_at: 2.days.ago)
    Fabricate(
      :post,
      topic: public_topic,
      user: user,
      post_number: 2,
      created_at: 1.day.ago
    )

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "state" => "person",
      "title_key" => "where_is_my_friends.first_connection.person.title",
      "description_key" =>
        "where_is_my_friends.first_connection.person.description",
      "primary_action" => {
        "kind" => "open_person_topic",
        "label_key" => "where_is_my_friends.first_connection.person.topic_cta",
        "url" => "/t/#{candidate_topic.slug}/#{candidate_topic.id}"
      },
      "secondary_action" => {
        "kind" => "open_recommendations",
        "label_key" => "where_is_my_friends.first_connection.more_people",
        "url" => "/where-is-my-friends/interests"
      },
      "recommendation_group" => "people",
      "algorithm_version" => "first_connection_v1"
    )
    expect(response.body).not_to include(
      sender.username,
      "reason_interests",
      "invitation_interests"
    )
  end

  it "does not count private messages or read-restricted posts as public interaction" do
    complete_interest_profile
    candidate_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: sender,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    candidate_profile.interests.create!(tag: interest, position: 0)
    candidate_topic =
      Fabricate(
        :topic,
        user: sender,
        title: "A public Ruby topic for the next action",
        tags: [interest],
        created_at: 5.days.ago
      )
    Fabricate(:post, topic: candidate_topic, user: sender, post_number: 1)
    Fabricate(
      :private_message_post,
      user: user,
      recipient: outsider,
      created_at: 1.day.ago
    )
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    private_category = Fabricate(:private_category, group: members)
    private_topic =
      Fabricate(:topic, user: outsider, category: private_category)
    Fabricate(
      :post,
      topic: private_topic,
      user: user,
      post_number: 2,
      created_at: 1.day.ago
    )

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "state" => "topic",
      "primary_action" =>
        include("url" => "/t/#{candidate_topic.slug}/#{candidate_topic.id}"),
      "recommendation_group" => "topics"
    )
  end

  it "uses the recommended member's profile when no representative topic exists" do
    complete_interest_profile
    candidate_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: sender,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    candidate_profile.interests.create!(tag: interest, position: 0)
    public_topic = Fabricate(:topic, user: outsider, created_at: 2.days.ago)
    Fabricate(
      :post,
      topic: public_topic,
      user: user,
      post_number: 2,
      created_at: 1.day.ago
    )

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "state" => "person",
      "primary_action" => {
        "kind" => "open_person_profile",
        "label_key" =>
          "where_is_my_friends.first_connection.person.profile_cta",
        "url" => "/u/#{sender.username}"
      },
      "recommendation_group" => "people"
    )
  end

  it "does not surface ignored, reverse-muted, or profile-hidden members" do
    complete_interest_profile
    muted = Fabricate(:user, last_seen_at: 1.hour.ago)
    hidden = Fabricate(:user, last_seen_at: 1.hour.ago)
    [sender, muted, hidden].each do |candidate|
      candidate.change_trust_level!(TrustLevel[1])
      profile =
        WhereIsMyFriendsInterestProfile.create!(
          user: candidate,
          purpose: "share",
          personalization_enabled: true,
          recommendable: true,
          completed_at: Time.current
        )
      profile.interests.create!(tag: interest, position: 0)
    end
    IgnoredUser.create!(
      user: user,
      ignored_user: sender,
      expiring_at: 1.year.from_now
    )
    MutedUser.create!(user: muted, muted_user: user)
    SiteSetting.allow_users_to_hide_profile = true
    hidden.user_option.update!(hide_profile: true)
    public_topic = Fabricate(:topic, user: outsider, created_at: 2.days.ago)
    Fabricate(
      :post,
      topic: public_topic,
      user: user,
      post_number: 2,
      created_at: 1.day.ago
    )
    SiteSetting.where_is_my_friends_dynamics_enabled = false

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("state")).to eq("local_discovery")
    expect(response.body).not_to include(
      sender.username,
      muted.username,
      hidden.username
    )
  end

  it "falls back to a visible recent dynamic when recommendations are empty" do
    complete_interest_profile
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_enabled = true
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    dynamic =
      Fabricate(
        :topic,
        user: sender,
        category: category,
        title: "A private member dynamic"
      )
    first_post =
      Fabricate(
        :post,
        topic: dynamic,
        user: sender,
        post_number: 1,
        raw: "Private dynamic body that must not reach the card"
      )
    dynamic.custom_fields[WhereIsMyFriends::DynamicFeed::FIELD] = true
    dynamic.save_custom_fields
    dynamic.update_columns(posts_count: 1, highest_post_number: 1)

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "state" => "dynamic",
      "title_key" => "where_is_my_friends.first_connection.dynamic.title",
      "description_key" =>
        "where_is_my_friends.first_connection.dynamic.description",
      "primary_action" => {
        "kind" => "open_dynamic",
        "label_key" => "where_is_my_friends.first_connection.dynamic.cta",
        "url" => "/t/#{dynamic.slug}/#{dynamic.id}"
      },
      "recommendation_group" => "dynamics",
      "algorithm_version" => "first_connection_v1"
    )
    expect(response.body).not_to include(first_post.raw, sender.username)
  end

  it "falls back to the existing city-first discovery flow" do
    complete_interest_profile
    SiteSetting.where_is_my_friends_dynamics_enabled = false

    get "/where-is-my-friends/next-action.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "state" => "local_discovery",
      "title_key" =>
        "where_is_my_friends.first_connection.local_discovery.title",
      "description_key" =>
        "where_is_my_friends.first_connection.local_discovery.description",
      "primary_action" => {
        "kind" => "open_local_discovery",
        "label_key" =>
          "where_is_my_friends.first_connection.local_discovery.cta",
        "url" => "/where-is-my-friends"
      },
      "algorithm_version" => "first_connection_v1"
    )
  end

  it "falls back to the existing recommendation panel when local discovery is unavailable" do
    WhereIsMyFriendsInterestProfile.create!(
      user: user,
      personalization_enabled: false,
      dismissed_at: Time.current
    )
    SiteSetting.where_is_my_friends_dynamics_enabled = false
    service =
      WhereIsMyFriends::NextAction.new(
        user: user,
        guardian: Guardian.new(user),
        as_of: Time.current
      )
    allow(service).to receive(:local_discovery_available?).and_return(false)

    expect(service.call).to eq(
      state: "recommendations",
      title_key: "where_is_my_friends.first_connection.recommendations.title",
      description_key:
        "where_is_my_friends.first_connection.recommendations.description",
      primary_action: {
        kind: "open_recommendations",
        label_key: "where_is_my_friends.first_connection.recommendations.cta",
        url: "/where-is-my-friends/interests"
      },
      algorithm_version: "first_connection_v1"
    )
  end

  it "returns explicit empty when every candidate action is unavailable" do
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = false
    SiteSetting.where_is_my_friends_dynamics_enabled = false
    service =
      WhereIsMyFriends::NextAction.new(
        user: user,
        guardian: Guardian.new(user),
        as_of: Time.current
      )
    allow(service).to receive(:local_discovery_available?).and_return(false)

    expect(service.call).to eq(
      state: "empty",
      algorithm_version: "first_connection_v1"
    )
  end

  it "keeps accepted-PM follow-up queries bounded as candidates grow" do
    create_accepted_conversations(1)
    next_action_query_count
    small_count = next_action_query_count

    create_accepted_conversations(9)
    next_action_query_count
    large_count = next_action_query_count

    expect(large_count).to eq(small_count)
    expect(large_count).to be <= 4
  end
end

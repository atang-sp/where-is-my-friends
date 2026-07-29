# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::RecommendationsController do
  fab!(:user)
  fab!(:author) { Fabricate(:user, last_seen_at: 1.day.ago) }
  fab!(:ruby_tag) { Fabricate(:tag, name: "ruby") }
  fab!(:design_tag) { Fabricate(:tag, name: "design") }
  fab!(:community_tag) { Fabricate(:tag, name: "community") }

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    SiteSetting.where_is_my_friends_interest_tags = "ruby|design|community"
    SiteSetting.tagging_enabled = true
    user.change_trust_level!(TrustLevel[2])
    author.change_trust_level!(TrustLevel[1])
    sign_in(user) unless RSpec.current_example.metadata[:anonymous]
  end

  it "saves three visible interests and immediately recommends matching topics" do
    topic =
      Fabricate(
        :topic,
        user: author,
        title: "A practical Ruby guide",
        tags: [ruby_tag]
      )

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "learn",
          recommendable: true,
          show_interests_publicly: false
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include(
      "state" => "complete",
      "profile" =>
        include(
          "purpose" => "learn",
          "recommendable" => true,
          "show_interests_publicly" => false
        )
    )
    expect(
      response.parsed_body.dig("profile", "interests").pluck("id")
    ).to contain_exactly(ruby_tag.id, design_tag.id, community_tag.id)
    expect(
      response.parsed_body.fetch("recommended_topics").pluck("id")
    ).to include(topic.id)
    expect(response.body).not_to include("notification_level")
    expect(
      WhereIsMyFriendsEvent.exists?(
        user: user,
        event_name: "interest_onboarding_completed"
      )
    ).to eq(true)
  end

  it "returns a grouped curated catalogue instead of deriving interests from recent topics" do
    %w[纯实践 惩戒管教 游戏互动].each { |name| Tag.find_by!(name: name) }
    recent_tag = Fabricate(:tag, name: "偶然出现的话题标签")
    Fabricate(
      :topic,
      user: author,
      title: "A recent topic should not define the interest catalogue",
      tags: [recent_tag]
    )
    SiteSetting.where_is_my_friends_interest_tags = ""

    get "/where-is-my-friends/recommendations.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("catalogue_groups")).to include(
      include(
        "key" => "interaction_style",
        "name" => "互动类型",
        "description" => be_present
      )
    )
    expect(response.parsed_body.fetch("catalogue")).to include(
      include(
        "name" => "纯实践",
        "group_key" => "interaction_style",
        "group_name" => "互动类型"
      ),
      include(
        "name" => "惩戒管教",
        "group_key" => "interaction_style",
        "group_name" => "互动类型"
      )
    )
    expect(
      response.parsed_body.fetch("catalogue").pluck("name")
    ).not_to include(recent_tag.name)
    expect(response.parsed_body.fetch("selection_limits")).to eq(
      "minimum" => 3,
      "maximum" => 12
    )
  end

  it "recommends related tagged topics with the selected curated interest as the reason" do
    interaction_tag = Tag.find_by!(name: "游戏互动")
    beginner_tag = Tag.find_by!(name: "新手入门")
    safety_tag = Tag.find_by!(name: "安全与边界")
    legacy_game_tag = Fabricate(:tag, name: "sp飞行棋")
    topic =
      Fabricate(
        :topic,
        user: author,
        title: "SP 飞行棋玩法与创意交流讨论",
        tags: [legacy_game_tag]
      )
    SiteSetting.where_is_my_friends_interest_tags = ""

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [interaction_tag.id, beginner_tag.id, safety_tag.id],
          purpose: "connect",
          recommendable: true
        }

    expect(response.status).to eq(200)
    recommendation =
      response
        .parsed_body
        .fetch("recommended_topics")
        .find { |entry| entry["id"] == topic.id }
    expect(recommendation).to be_present
    expect(recommendation.fetch("matching_interests")).to include(
      include("id" => interaction_tag.id, "name" => "游戏互动")
    )
  end

  it "recommends opted-in members from exact and related private selections without requiring posts" do
    pure_practice_tag = Tag.find_by!(name: "纯实践")
    discipline_tag = Tag.find_by!(name: "惩戒管教")
    light_tag = Tag.find_by!(name: "轻度")
    safety_tag = Tag.find_by!(name: "安全与边界")
    candidate = Fabricate(:user, last_seen_at: 1.day.ago)
    candidate.change_trust_level!(TrustLevel[1])
    candidate_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: candidate,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: false,
        completed_at: Time.current
      )
    [discipline_tag, light_tag, safety_tag].each_with_index do |tag, position|
      candidate_profile.interests.create!(tag: tag, position: position)
    end
    SiteSetting.where_is_my_friends_interest_tags = "纯实践|惩戒管教|轻度|安全与边界"

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [pure_practice_tag.id, light_tag.id, safety_tag.id],
          purpose: "learn",
          recommendable: true,
          show_interests_publicly: false
        }

    expect(response.status).to eq(200)
    recommendation =
      response
        .parsed_body
        .fetch("recommended_users")
        .find { |entry| entry["id"] == candidate.id }
    expect(recommendation).to be_present
    expect(recommendation).to include("match_strength" => "strong")
    expect(recommendation.fetch("reason_interests")).to include(
      include("id" => light_tag.id, "name" => "轻度"),
      include("id" => safety_tag.id, "name" => "安全与边界")
    )
    expect(recommendation.keys).not_to include(
      "purpose",
      "private_interests",
      "show_interests_publicly"
    )
    expect(recommendation.fetch("representative_topics")).to eq([])

    sign_in(candidate)
    get "/where-is-my-friends/recommendations.json"

    expect(
      response.parsed_body.fetch("recommended_users").pluck("id")
    ).to include(user.id)
  end

  it "recommends opted-in contributors without exposing private preferences or ignored users" do
    visible_topic =
      Fabricate(
        :topic,
        user: author,
        title: "Ruby patterns in practice",
        tags: [ruby_tag]
      )
    Fabricate(:post, topic: visible_topic, user: author)
    author_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: author,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: false,
        completed_at: Time.current
      )
    author_profile.interests.create!(tag: design_tag, position: 0)

    ignored = Fabricate(:user, last_seen_at: 1.day.ago)
    ignored_topic =
      Fabricate(
        :topic,
        user: ignored,
        title: "Ignored Ruby author",
        tags: [ruby_tag]
      )
    Fabricate(:post, topic: ignored_topic, user: ignored)
    ignored_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: ignored,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    ignored_profile.interests.create!(tag: ruby_tag, position: 0)
    IgnoredUser.create!(
      user: user,
      ignored_user: ignored,
      expiring_at: 1.year.from_now
    )

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "learn",
          recommendable: true,
          show_interests_publicly: false
        }

    people = response.parsed_body.fetch("recommended_users")
    topics = response.parsed_body.fetch("recommended_topics")
    expect(people.pluck("username")).to include(author.username)
    expect(people.pluck("username")).not_to include(ignored.username)
    expect(topics.pluck("id")).not_to include(ignored_topic.id)

    recommendation =
      people.find { |entry| entry["username"] == author.username }
    expect(recommendation).to include(
      "reason_interests" => [{ "id" => ruby_tag.id, "name" => "ruby" }],
      "invitation_interests" => [{ "id" => ruby_tag.id, "name" => "ruby" }]
    )
    expect(
      recommendation.fetch("representative_topics").pluck("id")
    ).to include(visible_topic.id)
    expect(recommendation.keys).not_to include(
      "purpose",
      "private_interests",
      "show_interests_publicly"
    )
  end

  it "keeps opted-out contributors recommendable without offering an invitation" do
    visible_topic =
      Fabricate(
        :topic,
        user: author,
        title: "Ruby patterns without invitations",
        tags: [ruby_tag]
      )
    Fabricate(:post, topic: visible_topic, user: author)
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: author,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    profile.interests.create!(tag: ruby_tag, position: 0)
    author.user_option.update!(
      where_is_my_friends_accept_practice_invitations: false
    )

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "learn",
          recommendable: true
        }

    recommendation =
      response
        .parsed_body
        .fetch("recommended_users")
        .find { |entry| entry["username"] == author.username }
    expect(recommendation).to be_present
    expect(recommendation.fetch("reason_interests")).to eq(
      [{ "id" => ruby_tag.id, "name" => "ruby" }]
    )
    expect(recommendation.fetch("invitation_interests")).to eq([])
  end

  it "filters restricted and muted tags from the catalogue, profile, and topics" do
    restricted_tag = Fabricate(:tag, name: "staff-plans")
    restricted_group =
      Fabricate(:tag_group, name: "Staff plans", tags: [restricted_tag])
    restricted_group.permissions = [
      [Group::AUTO_GROUPS[:staff], TagGroupPermission.permission_types[:full]]
    ]
    restricted_group.save!
    Fabricate(
      :topic,
      user: author,
      title: "A public topic carrying a restricted tag",
      tags: [restricted_tag]
    )

    SiteSetting.where_is_my_friends_interest_tags = ""
    get "/where-is-my-friends/recommendations.json"

    expect(response.status).to eq(200)
    expect(
      response.parsed_body.fetch("catalogue").pluck("name")
    ).not_to include(restricted_tag.name)

    profile = WhereIsMyFriendsInterestProfile.find_by!(user: user)
    profile.update!(
      purpose: "learn",
      personalization_enabled: true,
      recommendable: true,
      completed_at: Time.current
    )
    [ruby_tag, design_tag, community_tag].each_with_index do |tag, position|
      profile.interests.create!(tag: tag, position: position)
    end
    muted_topic =
      Fabricate(
        :topic,
        user: author,
        title: "Muted Ruby topic",
        tags: [ruby_tag]
      )
    TagUser.create!(
      user: user,
      tag: ruby_tag,
      notification_level: TagUser.notification_levels[:muted]
    )
    SiteSetting.where_is_my_friends_interest_tags = "ruby|design|community"

    get "/where-is-my-friends/recommendations.json"

    expect(response.status).to eq(200)
    expect(
      response.parsed_body.fetch("catalogue").pluck("name")
    ).not_to include(ruby_tag.name)
    expect(
      response.parsed_body.dig("profile", "interests").pluck("name")
    ).not_to include(ruby_tag.name)
    expect(
      response.parsed_body.fetch("recommended_topics").pluck("id")
    ).not_to include(muted_topic.id)
  end

  it "never uses a hidden post as evidence for a profile-similarity recommendation" do
    hidden_author = Fabricate(:user, last_seen_at: 1.day.ago)
    hidden_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: hidden_author,
        purpose: "share",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    hidden_profile.interests.create!(tag: ruby_tag, position: 0)
    hidden_topic =
      Fabricate(
        :topic,
        user: hidden_author,
        title: "Hidden Ruby contribution",
        tags: [ruby_tag]
      )
    Fabricate(:post, topic: hidden_topic, user: hidden_author, hidden: true)

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "learn"
        }

    expect(response.status).to eq(200)
    recommendation =
      response
        .parsed_body
        .fetch("recommended_users")
        .find { |entry| entry["username"] == hidden_author.username }
    expect(recommendation).to be_present
    expect(recommendation.fetch("representative_topics")).to eq([])
  end

  it "lets a member skip onboarding without changing tag notification preferences" do
    expect do
      post "/where-is-my-friends/recommendations/skip.json"
    end.not_to change { TagUser.where(user_id: user.id).count }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include("state" => "dismissed")
    expect(
      WhereIsMyFriendsInterestProfile.find_by(user_id: user.id)
    ).to have_attributes(personalization_enabled: false, completed_at: nil)
    expect(
      WhereIsMyFriendsEvent.exists?(
        user: user,
        event_name: "interest_onboarding_skipped"
      )
    ).to eq(true)
  end

  it "dismisses only a recommendation the member can currently see" do
    topic =
      Fabricate(
        :topic,
        user: author,
        title: "Ruby topic to dismiss",
        tags: [ruby_tag]
      )
    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "learn"
        }

    post "/where-is-my-friends/recommendations/dismiss.json",
         params: {
           target_type: "topic",
           target_id: topic.id
         }

    expect(response.status).to eq(200)
    expect(
      response.parsed_body.fetch("recommended_topics").pluck("id")
    ).not_to include(topic.id)
    expect(
      WhereIsMyFriendsRecommendationDismissal.find_by(user: user)
    ).to have_attributes(target_type: "topic", target_id: topic.id)
    expect(
      WhereIsMyFriendsEvent.exists?(
        user: user,
        event_name: "recommendation_dismissed"
      )
    ).to eq(true)

    post "/where-is-my-friends/recommendations/dismiss.json",
         params: {
           target_type: "topic",
           target_id: Fabricate(:topic).id
         }
    expect(response.status).to eq(422)
  end

  it "clears personalization data without deleting forum content or preferences" do
    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "connect",
          recommendable: true,
          show_interests_publicly: true
        }
    profile = WhereIsMyFriendsInterestProfile.find_by!(user: user)
    profile.dismissals.create!(
      target_type: "topic",
      target_id: Fabricate(:topic).id
    )

    expect do
      delete "/where-is-my-friends/recommendations/profile.json"
    end.not_to change { user.reload.user_option.attributes }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to include("state" => "dismissed")
    expect(profile.reload).to have_attributes(
      purpose: nil,
      personalization_enabled: false,
      recommendable: false,
      show_interests_publicly: false,
      completed_at: nil
    )
    expect(profile.interests).to be_empty
    expect(profile.dismissals).to be_empty
    expect(
      WhereIsMyFriendsEvent.exists?(
        user: user,
        event_name: "personalization_disabled"
      )
    ).to eq(true)
  end

  it "rejects invalid, hidden, or incomplete preference submissions" do
    hidden_tag = Fabricate(:tag, name: "not-in-catalogue")
    too_many_interest_ids =
      Tag
        .where(name: WhereIsMyFriends::InterestCatalogue.names)
        .limit(13)
        .pluck(:id)

    [
      { interest_ids: [ruby_tag.id, design_tag.id], purpose: "learn" },
      { interest_ids: too_many_interest_ids, purpose: "learn" },
      {
        interest_ids: [ruby_tag.id, design_tag.id, hidden_tag.id],
        purpose: "learn"
      },
      {
        interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
        purpose: "invalid"
      }
    ].each do |invalid_params|
      put "/where-is-my-friends/recommendations/profile.json",
          params: invalid_params
      expect(response.status).to eq(422)
    end
  end

  it "requires login and honors both feature switches", :anonymous do
    get "/where-is-my-friends/recommendations.json"
    expect(response.status).to eq(403)

    sign_in(user)
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = false
    get "/where-is-my-friends/recommendations.json"
    expect(response.status).to eq(404)

    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    SiteSetting.where_is_my_friends_enabled = false
    get "/where-is-my-friends/recommendations.json"
    expect(response.status).to eq(404)
  end

  it "does not leak topics or contributors from inaccessible categories" do
    SiteSetting.hide_new_user_profiles = false
    private_topic =
      Fabricate(
        :topic,
        user: author,
        category: Fabricate(:private_category, group: Fabricate(:group)),
        title: "Private Ruby planning",
        tags: [ruby_tag]
      )
    Fabricate(:post, topic: private_topic, user: author)
    public_topic =
      Fabricate(
        :topic,
        user: author,
        title: "Public Ruby planning",
        tags: [ruby_tag]
      )
    author_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: author,
        purpose: "help",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    author_profile.interests.create!(tag: ruby_tag, position: 0)
    hidden_contributor = Fabricate(:user, last_seen_at: 1.day.ago)
    hidden_contributor.change_trust_level!(TrustLevel[1])
    hidden_profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: hidden_contributor,
        purpose: "help",
        personalization_enabled: true,
        recommendable: true,
        completed_at: Time.current
      )
    hidden_profile.interests.create!(tag: ruby_tag, position: 0)
    Fabricate(
      :topic,
      user: hidden_contributor,
      title: "A visible but unrelated contribution"
    )
    hidden_post =
      Fabricate(:post, topic: public_topic, user: hidden_contributor)
    hidden_post.update_columns(hidden: true)

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "ask"
        }

    body = response.parsed_body
    expect(body.fetch("recommended_topics").pluck("id")).to include(
      public_topic.id
    )
    expect(body.fetch("recommended_topics").pluck("id")).not_to include(
      private_topic.id
    )
    representative_ids =
      body
        .fetch("recommended_users")
        .flat_map { |entry| entry.fetch("representative_topics").pluck("id") }
    expect(representative_ids).not_to include(private_topic.id)
    hidden_recommendation =
      body
        .fetch("recommended_users")
        .find { |entry| entry["id"] == hidden_contributor.id }
    expect(hidden_recommendation).to be_present
    expect(hidden_recommendation.fetch("representative_topics")).to eq([])
    expect(response.body).not_to include("Private Ruby planning")
  end

  it "respects reverse mutes and caps recommendations" do
    authors =
      Array.new(8) do |index|
        candidate =
          Fabricate(
            :user,
            username: "candidate#{index}",
            last_seen_at: index.days.ago
          )
        candidate.change_trust_level!(TrustLevel[1])
        candidate_profile =
          WhereIsMyFriendsInterestProfile.create!(
            user: candidate,
            purpose: "share",
            personalization_enabled: true,
            recommendable: true,
            completed_at: Time.current
          )
        candidate_profile.interests.create!(tag: ruby_tag, position: 0)
        candidate
      end
    MutedUser.create!(user: authors.first, muted_user: user)

    10.times do |index|
      candidate = authors[index % authors.length]
      topic =
        Fabricate(
          :topic,
          user: candidate,
          title: "Ruby recommendation #{index}",
          tags: [ruby_tag]
        )
      Fabricate(:post, topic: topic, user: candidate)
    end

    put "/where-is-my-friends/recommendations/profile.json",
        params: {
          interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
          purpose: "learn"
        }

    body = response.parsed_body
    expect(body.fetch("recommended_topics").length).to eq(5)
    expect(body.fetch("recommended_users").length).to eq(6)
    expect(body.fetch("recommended_users").pluck("id")).not_to include(
      authors.first.id
    )
  end
end

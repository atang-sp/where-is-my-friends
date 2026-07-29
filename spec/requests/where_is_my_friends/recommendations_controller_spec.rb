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

  describe "#index" do
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
          "name" =>
            I18n.t(
              "where_is_my_friends.interest_catalogue.groups.interaction_style.name"
            ),
          "description" => be_present
        )
      )
      expect(response.parsed_body.fetch("catalogue")).to include(
        include(
          "name" => "纯实践",
          "group_key" => "interaction_style",
          "group_name" =>
            I18n.t(
              "where_is_my_friends.interest_catalogue.groups.interaction_style.name"
            )
        ),
        include(
          "name" => "惩戒管教",
          "group_key" => "interaction_style",
          "group_name" =>
            I18n.t(
              "where_is_my_friends.interest_catalogue.groups.interaction_style.name"
            )
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

    it "returns two filter-only interest entrances with an algorithm version" do
      ruby_topic =
        Fabricate(
          :topic,
          user: author,
          title: "A fresh Ruby question",
          tags: [ruby_tag]
        )
      design_topic =
        Fabricate(
          :topic,
          user: author,
          title: "A fresh design discussion",
          tags: [design_tag]
        )

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
            purpose: "learn",
            recommendable: true
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("algorithm_version")).to eq(
        "participation_v1"
      )
      entrances = response.parsed_body.fetch("recommended_interests")
      expect(entrances.length).to eq(2)
      expect(entrances).to include(
        include(
          "id" => ruby_tag.id,
          "name" => ruby_tag.name,
          "url" => ruby_tag.url,
          "candidate_source" => "interest",
          "topic_count" => 1,
          "new_topic_count" => 1,
          "active_member_count" => nil,
          "active_member_count_suppressed" => true
        ),
        include(
          "id" => design_tag.id,
          "name" => design_tag.name,
          "url" => design_tag.url,
          "candidate_source" => "interest",
          "topic_count" => 1,
          "new_topic_count" => 1,
          "active_member_count" => nil,
          "active_member_count_suppressed" => true
        )
      )
      expect(entrances.pluck("url")).to all(start_with("/tag/"))
      expect(entrances.pluck("id")).to contain_exactly(
        ruby_topic.tags.first.id,
        design_topic.tags.first.id
      )
    end
  end

  describe "#update_profile" do
    it "offers an adjacent interest as an explainable exploration entrance" do
      interaction_tag = Tag.find_by!(name: "游戏互动")
      creation_tag = Tag.find_by!(name: "游戏创作")
      beginner_tag = Tag.find_by!(name: "新手入门")
      safety_tag = Tag.find_by!(name: "安全与边界")
      Fabricate(
        :topic,
        user: author,
        title: "分享一次完整的游戏互动经验与复盘",
        tags: [interaction_tag]
      )
      Fabricate(
        :topic,
        user: author,
        title: "一起设计新的棋盘玩法与创作流程",
        tags: [creation_tag]
      )
      SiteSetting.where_is_my_friends_interest_tags = ""

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [interaction_tag.id, beginner_tag.id, safety_tag.id],
            purpose: "browse",
            recommendable: true
          }

      exploration =
        response
          .parsed_body
          .fetch("recommended_interests")
          .find { |entry| entry["id"] == creation_tag.id }
      expect(exploration).to include(
        "candidate_source" => "exploration",
        "reason_interest" => {
          "id" => interaction_tag.id,
          "name" => interaction_tag.name
        },
        "url" => creation_tag.url
      )
    end

    it "reserves a recommendation slot for a fresh discussion awaiting replies" do
      5.times do |index|
        crowded_topic =
          Fabricate(
            :topic,
            user: author,
            title: "Popular fully matched discussion #{index}",
            tags: [ruby_tag, design_tag, community_tag],
            created_at: 5.days.ago,
            bumped_at: index.minutes.ago,
            like_count: 100 - index
          )
        3.times { Fabricate(:post, topic: crowded_topic, user: author) }
        crowded_topic.update_columns(posts_count: 4, highest_post_number: 4)
      end
      waiting_topic =
        Fabricate(
          :topic,
          user: author,
          title: "A fresh Ruby question waiting for help",
          tags: [ruby_tag],
          created_at: 2.hours.ago,
          bumped_at: 2.hours.ago
        )
      waiting_topic.update_columns(posts_count: 1, highest_post_number: 1)

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
            purpose: "help",
            recommendable: true
          }

      expect(response.status).to eq(200)
      topics = response.parsed_body.fetch("recommended_topics")
      expect(topics.length).to eq(5)
      waiting_recommendation =
        topics.find { |entry| entry["id"] == waiting_topic.id }
      expect(waiting_recommendation).to include(
        "participation_state" => "awaiting_response",
        "candidate_source" => "interest",
        "rank_bucket" =>
          satisfy { |value| %w[one_to_two three_to_five].include?(value) }
      )
    end

    it "keeps distinct waiting-response and adjacent-exploration slots" do
      interaction_tag = Tag.find_by!(name: "游戏互动")
      creation_tag = Tag.find_by!(name: "游戏创作")
      beginner_tag = Tag.find_by!(name: "新手入门")
      safety_tag = Tag.find_by!(name: "安全与边界")
      5.times do |index|
        topic =
          Fabricate(
            :topic,
            user: author,
            title: "分享一段完整的互动讨论与经验记录 #{index}",
            tags: [interaction_tag],
            created_at: 5.days.ago,
            bumped_at: index.minutes.ago
          )
        topic.update_columns(posts_count: 3, highest_post_number: 3)
      end
      waiting_topic =
        Fabricate(
          :topic,
          user: author,
          title: "这是一个互动求助并且正在等待第一个回复",
          tags: [interaction_tag],
          created_at: 2.hours.ago,
          bumped_at: 2.hours.ago
        )
      waiting_topic.update_columns(posts_count: 1, highest_post_number: 1)
      exploration_topic =
        Fabricate(
          :topic,
          user: author,
          title: "尝试创作一套完整而且有趣的全新内容",
          tags: [creation_tag],
          created_at: 5.days.ago,
          bumped_at: 1.day.ago
        )
      exploration_topic.update_columns(posts_count: 3, highest_post_number: 3)
      SiteSetting.where_is_my_friends_interest_tags = ""

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [interaction_tag.id, beginner_tag.id, safety_tag.id],
            purpose: "help",
            recommendable: true
          }

      topics = response.parsed_body.fetch("recommended_topics")
      expect(topics.length).to eq(5)
      expect(topics.fetch(3)).to include(
        "id" => waiting_topic.id,
        "participation_state" => "awaiting_response"
      )
      expect(topics.fetch(4)).to include(
        "id" => exploration_topic.id,
        "candidate_source" => "exploration"
      )
    end

    it "marks unread and participated topics with author activity signals" do
      unread_topic =
        Fabricate(
          :topic,
          user: author,
          title: "Unread Ruby discussion",
          tags: [ruby_tag],
          created_at: 5.days.ago
        )
      2.times do |index|
        Fabricate(
          :post,
          topic: unread_topic,
          user: author,
          post_number: index + 2
        )
      end
      unread_topic.update_columns(posts_count: 3, highest_post_number: 3)

      participated_topic =
        Fabricate(
          :topic,
          user: author,
          title: "Ruby discussion I joined",
          tags: [ruby_tag],
          created_at: 5.days.ago
        )
      Fabricate(:post, topic: participated_topic, user: user, post_number: 2)
      participated_topic.update_columns(posts_count: 2, highest_post_number: 2)

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
            purpose: "help",
            recommendable: true
          }

      topics = response.parsed_body.fetch("recommended_topics")
      unread = topics.find { |entry| entry["id"] == unread_topic.id }
      participated =
        topics.find { |entry| entry["id"] == participated_topic.id }
      expect(unread).to include(
        "participation_state" => "unread",
        "unread" => true,
        "viewer_replied" => false,
        "author_active" => true,
        "reply_count" => 2
      )
      expect(participated).to include(
        "participation_state" => "participated",
        "unread" => false,
        "viewer_replied" => true,
        "author_active" => true,
        "reply_count" => 1
      )
    end

    it "ranks an unread participatory topic above a popular topic already replied to" do
      unread_topic =
        Fabricate(
          :topic,
          user: author,
          title: "Open Ruby question for newcomers",
          tags: [ruby_tag],
          created_at: 1.day.ago,
          bumped_at: 1.day.ago,
          like_count: 0
        )
      unread_topic.update_columns(posts_count: 3, highest_post_number: 3)

      participated_topic =
        Fabricate(
          :topic,
          user: author,
          title: "Popular Ruby thread I already joined",
          tags: [ruby_tag],
          created_at: 1.day.ago,
          bumped_at: 1.minute.ago,
          like_count: 500
        )
      Fabricate(:post, topic: participated_topic, user: user, post_number: 2)
      participated_topic.update_columns(posts_count: 2, highest_post_number: 2)

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
            purpose: "help",
            recommendable: true
          }

      topics = response.parsed_body.fetch("recommended_topics")
      expect(topics.first).to include(
        "id" => unread_topic.id,
        "participation_state" => "unread"
      )
      expect(
        topics.find { |entry| entry["id"] == participated_topic.id }
      ).to include("participation_state" => "participated")
    end

    it "penalizes an unread topic that the viewer has already spent substantial time reading" do
      repeatedly_viewed =
        Fabricate(
          :topic,
          user: author,
          title: "Ruby discussion repeatedly revisited",
          tags: [ruby_tag],
          created_at: 5.days.ago,
          bumped_at: 1.minute.ago
        )
      repeatedly_viewed.update_columns(posts_count: 3, highest_post_number: 3)
      TopicUser.create!(
        user: user,
        topic: repeatedly_viewed,
        first_visited_at: 2.days.ago,
        last_visited_at: 1.hour.ago,
        last_read_post_number: 1,
        total_msecs_viewed: 10.minutes.in_milliseconds
      )
      lightly_seen =
        Fabricate(
          :topic,
          user: author,
          title: "Ruby discussion not repeatedly viewed",
          tags: [ruby_tag],
          created_at: 5.days.ago,
          bumped_at: 1.day.ago
        )
      lightly_seen.update_columns(posts_count: 3, highest_post_number: 3)

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
            purpose: "help",
            recommendable: true
          }

      topic_ids = response.parsed_body.fetch("recommended_topics").pluck("id")
      expect(topic_ids.index(lightly_seen.id)).to be <
        topic_ids.index(repeatedly_viewed.id)
    end

    it "rotates a bounded pool of eligible discussions when refreshed" do
      10.times do |index|
        topic =
          Fabricate(
            :topic,
            user: author,
            title: "Eligible Ruby discussion #{index}",
            tags: [ruby_tag],
            created_at: 5.days.ago,
            bumped_at: index.minutes.ago
          )
        topic.update_columns(posts_count: 3, highest_post_number: 3)
      end

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
            purpose: "help",
            recommendable: true
          }
      initial_ids = response.parsed_body.fetch("recommended_topics").pluck("id")

      get "/where-is-my-friends/recommendations.json",
          params: {
            refresh: "next"
          }
      refreshed_ids =
        response.parsed_body.fetch("recommended_topics").pluck("id")

      expect(refreshed_ids).not_to eq(initial_ids)
      expect(refreshed_ids.length).to eq(5)
      eligible_ids =
        Topic.joins(:tags).where(tags: { id: ruby_tag.id }).pluck(:id)
      expect(refreshed_ids - eligible_ids).to be_empty
    end

    it "penalizes a single author from concentrating the top recommendations" do
      other_author = Fabricate(:user, last_seen_at: 1.day.ago)
      concentrated_topics =
        3.times.map do |index|
          Fabricate(
            :topic,
            user: author,
            title: "Ruby discussion by the same author #{index}",
            tags: [ruby_tag],
            created_at: 5.days.ago,
            bumped_at: index.minutes.ago
          )
        end
      diverse_topic =
        Fabricate(
          :topic,
          user: other_author,
          title: "Ruby discussion from another active member",
          tags: [ruby_tag],
          created_at: 5.days.ago,
          bumped_at: 10.minutes.ago
        )

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [ruby_tag.id, design_tag.id, community_tag.id],
            purpose: "connect",
            recommendable: true
          }

      topic_ids = response.parsed_body.fetch("recommended_topics").pluck("id")
      expect(topic_ids.index(diverse_topic.id)).to be <
        topic_ids.index(concentrated_topics.last.id)
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

    it "retrieves an older topic through a related catalogue tag" do
      pure_practice_tag = Tag.find_by!(name: "纯实践")
      light_tag = Tag.find_by!(name: "轻度")
      safety_tag = Tag.find_by!(name: "安全与边界")
      discipline_tag = Tag.find_by!(name: "惩戒管教")
      old_topic =
        Fabricate(
          :topic,
          user: author,
          title: "An archived neighboring preference discussion",
          tags: [discipline_tag],
          created_at: 1.year.ago,
          bumped_at: 1.year.ago
        )
      101.times do |index|
        Fabricate(
          :topic,
          title: "Unrelated recent catalogue filler topic #{index}",
          created_at: index.seconds.ago,
          bumped_at: index.seconds.ago
        )
      end
      SiteSetting.where_is_my_friends_interest_tags = ""

      put "/where-is-my-friends/recommendations/profile.json",
          params: {
            interest_ids: [pure_practice_tag.id, light_tag.id, safety_tag.id],
            purpose: "browse",
            recommendable: true
          }

      expect(response.status).to eq(200)
      recommendation =
        response
          .parsed_body
          .fetch("recommended_topics")
          .find { |entry| entry["id"] == old_topic.id }
      expect(recommendation).to be_present
      expect(recommendation.fetch("matching_interests")).to include(
        include("id" => pure_practice_tag.id, "name" => "纯实践")
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
      expect(recommendation).to include(
        "candidate_source" => "interest",
        "rank" => 1,
        "rank_bucket" => "one_to_two"
      )
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
           target_id: topic.id,
           surface: "homepage",
           candidate_source: "interest",
           rank: 2,
           algorithm_version: "participation_v1"
         }

    expect(response.status).to eq(200)
    expect(
      response.parsed_body.fetch("recommended_topics").pluck("id")
    ).not_to include(topic.id)
    expect(
      WhereIsMyFriendsRecommendationDismissal.find_by(user: user)
    ).to have_attributes(target_type: "topic", target_id: topic.id)
    expect(
      WhereIsMyFriendsEvent.find_by!(
        user: user,
        event_name: "recommendation_dismissed"
      )
    ).to have_attributes(
      surface: "homepage",
      candidate_source: "interest",
      rank_bucket: "one_to_two",
      algorithm_version: "participation_v1"
    )

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

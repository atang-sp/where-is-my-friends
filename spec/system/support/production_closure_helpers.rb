# frozen_string_literal: true

module WhereIsMyFriendsProductionClosureHelpers
  AS_OF = Time.utc(2030, 1, 15, 12).freeze

  def configure_production_closure_features
    SiteSetting.default_locale = "en"
    SiteSetting.hide_new_user_profiles = false
    SiteSetting.tagging_enabled = true
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_first_connection_enabled = false
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    SiteSetting.where_is_my_friends_dynamics_enabled = true
    SiteSetting.where_is_my_friends_dynamics_homepage_enabled = true
    SiteSetting.where_is_my_friends_dynamics_feed_enabled = true
    SiteSetting.where_is_my_friends_practice_invitations_enabled = true
    SiteSetting.where_is_my_friends_practice_invitation_min_trust_level = 1
    SiteSetting.where_is_my_friends_practice_invitation_daily_limit = 5
    SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3
  end

  def prepare_recommendation_network(viewer:, candidate:)
    tag = Tag.find_or_create_by!(name: "ruby")
    SiteSetting.where_is_my_friends_interest_tags = tag.name

    [viewer, candidate].each do |user|
      user.change_trust_level!(TrustLevel[1])
      user.update!(last_seen_at: AS_OF)
      user.user_option.update!(
        hide_profile: false,
        where_is_my_friends_accept_practice_invitations: true
      )
    end

    create_interest_profile(user: viewer, tag: tag)
    create_interest_profile(user: candidate, tag: tag, public: true)

    topic =
      Fabricate(
        :topic,
        user: candidate,
        title: "Practical Ruby patterns for community projects",
        tags: [tag],
        created_at: AS_OF - 1.day
      )
    Fabricate(
      :post,
      topic: topic,
      user: candidate,
      raw: "A public discussion used by the production-closure system gate.",
      created_at: AS_OF - 1.day
    )

    { tag: tag, topic: topic }
  end

  def create_interest_profile(user:, tag:, public: false)
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: user,
        purpose: "connect",
        personalization_enabled: true,
        recommendable: true,
        show_interests_publicly: public,
        completed_at: AS_OF
      )
    profile.interests.create!(tag: tag, position: 0)
    profile
  end

  def configure_dynamics_category
    members = Group.find(Group::AUTO_GROUPS.fetch(:trust_level_0))
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    muted_ids = SiteSetting.default_categories_muted.split("|").map(&:to_i)
    SiteSetting.default_categories_muted = (muted_ids | [category.id]).join("|")
    category
  end

  def track_recommendation_requests
    requests = []
    callback =
      lambda do |request|
        if request.url.include?("/where-is-my-friends/recommendations.json")
          requests << request.url
        end
      end
    page.driver.with_playwright_page do |playwright_page|
      playwright_page.on("request", callback)
    end
    requests
  end
end

RSpec.configure do |config|
  config.include WhereIsMyFriendsProductionClosureHelpers, type: :system
end

# frozen_string_literal: true

unless Rails.env.development?
  raise "Local Friends E2E setup is development-only"
end

password = "LocalFriendsTest123!"
users = {
  admin: {
    admin: true,
    location: nil
  },
  shanghai_one: {
    location: {
      city: "上海",
      region: "上海"
    }
  },
  shanghai_two: {
    location: {
      city: "上海市",
      region: "上海"
    }
  },
  empty_city: {
    location: {
      city: "乌鲁木齐",
      region: "新疆"
    }
  }
}.freeze

SiteSetting.where_is_my_friends_enabled = true
SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
SiteSetting.where_is_my_friends_interest_tags = "ruby|design|community"
SiteSetting.where_is_my_friends_enable_virtual_location = true
SiteSetting.where_is_my_friends_map_provider = "openstreetmap"
SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3
SiteSetting.tagging_enabled = true
SiteSetting.default_locale = "en"
SiteSetting.login_required = false
SiteSetting.tagging_enabled = true

client_ips = [
  "127.0.0.1",
  ENV.fetch("LOCAL_FRIENDS_E2E_CLIENT_IP", "172.17.0.1")
]
client_ips.uniq.each do |client_ip|
  %w[login-hr login-min].each do |limit|
    Discourse.redis.del("l-rate-limit3:::#{limit}-#{client_ip}")
  end
end

seeded_users = {}

users.each do |username, attributes|
  username = username.to_s
  user = User.find_by_username(username)
  user ||=
    User.new(
      username: username,
      email: "local-friends-#{username}@example.test",
      name: username.tr("_", " ").titleize
    )

  user.password = password unless user.persisted? &&
    user.confirm_password?(password)
  user.active = true
  user.approved = true
  user.admin = attributes[:admin] || false
  user.moderator = attributes[:admin] || false
  user.locale = "en"
  user.save!
  user.activate unless user.email_confirmed?
  user.change_trust_level!(attributes[:admin] ? TrustLevel[4] : TrustLevel[1])
  user.update!(last_seen_at: Time.current)
  seeded_users[username.to_sym] = user

  UserLocation.where(user_id: user.id).delete_all
  WhereIsMyFriendsEvent.where(user_id: user.id).delete_all
  WhereIsMyFriendsRecommendationDismissal.where(user_id: user.id).delete_all
  WhereIsMyFriendsUserInterest.where(user_id: user.id).delete_all
  WhereIsMyFriendsInterestProfile.where(user_id: user.id).delete_all

  if (location = attributes[:location])
    UserLocation.upsert_city_location(user.id, **location)
  end
end

interest_tags =
  %w[ruby design community].to_h do |name|
    [name, Tag.find_or_create_by!(name: name)]
  end

candidate = seeded_users.fetch(:shanghai_one)
candidate_profile =
  WhereIsMyFriendsInterestProfile.create!(
    user: candidate,
    purpose: "share",
    personalization_enabled: true,
    recommendable: true,
    show_interests_publicly: false,
    completed_at: Time.current
  )
candidate_profile.interests.create!(
  tag: interest_tags.fetch("ruby"),
  position: 0
)

interest_topic_title = "Practical Ruby patterns for community projects"
Topic.where(title: interest_topic_title).find_each(&:destroy!)
interest_category =
  Category.find_by(slug: "local-friends-e2e") ||
    Category.create!(
      name: "Local Friends E2E",
      slug: "local-friends-e2e",
      color: "0088CC",
      text_color: "FFFFFF",
      read_restricted: false
    )
first_post =
  PostCreator.create!(
    candidate,
    title: interest_topic_title,
    raw:
      "A public, practical thread used to verify interest-based community discovery.",
    category: interest_category.id,
    tags: ["ruby"],
    skip_validations: true
  )
PostCreator.create!(
  candidate,
  topic_id: first_post.topic_id,
  raw: "I can share a few examples and help people apply these patterns.",
  skip_validations: true
)

local_topic_title = "Shanghai weekend picnic"
local_topic_category =
  Category.find_by(name: "Local Friends E2E") ||
    Category.create!(
      name: "Local Friends E2E",
      slug: "local-friends-e2e",
      user: Discourse.system_user
    )
local_topic =
  Topic.find_by(title: local_topic_title) ||
    PostCreator.create!(
      Discourse.system_user,
      title: local_topic_title,
      raw: "A public thread for planning a weekend picnic in Shanghai.",
      category: local_topic_category.id,
      tags: [WhereIsMyFriends::LocalTopics.tag_name_for("上海")]
    ).topic
DiscourseTagging.add_or_create_tags_by_name(
  local_topic,
  [WhereIsMyFriends::LocalTopics.tag_name_for("上海")]
)

puts "Seeded Local Friends E2E users (password: #{password})"

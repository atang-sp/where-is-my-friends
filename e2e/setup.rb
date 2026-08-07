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
    trust_level: TrustLevel[2],
    location: {
      city: "上海市",
      region: "上海"
    }
  },
  empty_city: {
    location: {
      city: "杭州",
      region: "浙江"
    }
  },
  city_entry: {
    location: nil
  },
  dynamics_one: {
    location: nil,
    trust_level: TrustLevel[2]
  },
  dynamics_two: {
    location: nil,
    trust_level: TrustLevel[2]
  }
}.freeze

SiteSetting.where_is_my_friends_enabled = true
SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
SiteSetting.where_is_my_friends_dynamics_enabled = true
SiteSetting.where_is_my_friends_dynamics_homepage_enabled = true
SiteSetting.where_is_my_friends_dynamics_member_preview_enabled = true
SiteSetting.where_is_my_friends_interest_tags = "ruby|design|community"
SiteSetting.where_is_my_friends_enable_virtual_location = true
SiteSetting.where_is_my_friends_map_provider = "openstreetmap"
SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3
SiteSetting.tagging_enabled = true
SiteSetting.default_locale = "en"
SiteSetting.login_required = false
SiteSetting.tagging_enabled = true
SiteSetting.max_logins_per_ip_per_minute = 50
SiteSetting.max_logins_per_ip_per_hour = 100

WhereIsMyFriendsAiProviderProfile.where(
  name: "E2E generation gateway"
).delete_all

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
  user.change_trust_level!(
    (
      if attributes[:admin]
        TrustLevel[4]
      else
        attributes.fetch(:trust_level, TrustLevel[1])
      end
    )
  )
  user.update!(last_seen_at: Time.current)
  user.user_option.update!(hide_profile: false)
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

dynamics_category =
  Category.find_by(slug: "personal-dynamics-e2e") ||
    Category.create!(
      user: seeded_users.fetch(:admin),
      name: "Personal Dynamics E2E",
      slug: "personal-dynamics-e2e",
      color: "7057FF",
      text_color: "FFFFFF",
      read_restricted: true
    )
dynamics_category.update!(read_restricted: true)
dynamics_category.set_permissions(
  Group.find(Group::AUTO_GROUPS.fetch(:trust_level_0)) => :full
)
dynamics_category.save!
SiteSetting.where_is_my_friends_dynamics_category_id = dynamics_category.id
muted_category_ids = SiteSetting.default_categories_muted.split("|").map(&:to_i)
SiteSetting.default_categories_muted =
  (muted_category_ids | [dynamics_category.id]).join("|")

Topic
  .joins(
    "INNER JOIN topic_custom_fields ON topic_custom_fields.topic_id = topics.id"
  )
  .where(
    user_id: seeded_users.values_at(:dynamics_one, :dynamics_two).map(&:id)
  )
  .where(topic_custom_fields: { name: WhereIsMyFriends::DynamicFeed::FIELD })
  .find_each(&:destroy!)

WhereIsMyFriendsInterestProfile.create!(
  user: seeded_users.fetch(:city_entry),
  purpose: nil,
  personalization_enabled: false,
  recommendable: false,
  show_interests_publicly: false,
  dismissed_at: Time.current
)

interest_tags =
  %w[ruby design community 上海].to_h do |name|
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

%i[dynamics_one dynamics_two].each do |username|
  profile =
    WhereIsMyFriendsInterestProfile.create!(
      user: seeded_users.fetch(username),
      purpose: "connect",
      personalization_enabled: true,
      recommendable: true,
      show_interests_publicly: false,
      completed_at: Time.current
    )
  profile.interests.create!(tag: interest_tags.fetch("上海"), position: 0)
end

interest_topic_title = "Practical Ruby patterns for community projects"
Topic.where(title: interest_topic_title).find_each(&:destroy!)
interest_category =
  Category.find_by(slug: "local-friends-e2e") ||
    Category.create!(
      user: seeded_users.fetch(:admin),
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
  Category.find_by(name: "Practice Friends E2E") ||
    Category.create!(
      name: "Practice Friends E2E",
      slug: "practice-friends-e2e",
      user: Discourse.system_user,
      minimum_required_tags: 2
    )
local_topic_category.update!(minimum_required_tags: 2)
SiteSetting.where_is_my_friends_target_category_id = local_topic_category.id

area_tags =
  %w[中国 上海 江苏 浙江].to_h { |name| [name, Tag.find_or_create_by!(name: name)] }
top_level_group =
  TagGroup.find_or_initialize_by(name: "Practice Friends E2E top-level areas")
top_level_group.one_per_topic = true
top_level_group.save!
top_level_group.tag_ids = [area_tags.fetch("中国").id]
province_group =
  TagGroup.find_or_initialize_by(name: "Practice Friends E2E provinces")
province_group.one_per_topic = true
province_group.parent_tag = area_tags.fetch("中国")
province_group.save!
province_group.tag_ids = area_tags.values_at("上海", "江苏", "浙江").map(&:id)
[top_level_group, province_group].each do |tag_group|
  CategoryTagGroup.find_or_create_by!(
    category: local_topic_category,
    tag_group: tag_group
  )
end

Topic.where(title: local_topic_title).find_each(&:destroy!)
PostCreator.create!(
  Discourse.system_user,
  title: local_topic_title,
  raw: "A public thread for planning a weekend picnic in Shanghai.",
  category: local_topic_category.id,
  tags: %w[中国 上海]
)

puts "Seeded Local Friends E2E users (password: #{password})"

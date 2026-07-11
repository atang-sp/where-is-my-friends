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
      city: "杭州",
      region: "浙江"
    }
  }
}.freeze

SiteSetting.where_is_my_friends_enabled = true
SiteSetting.where_is_my_friends_enable_virtual_location = true
SiteSetting.where_is_my_friends_map_provider = "openstreetmap"
SiteSetting.where_is_my_friends_location_ttl_days = 30
SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3
SiteSetting.default_locale = "en"
SiteSetting.login_required = false

%w[login-hr-127.0.0.1 login-min-127.0.0.1].each do |key|
  Discourse.redis.del("l-rate-limit3:::#{key}")
end

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

  UserLocation.where(user_id: user.id).delete_all
  WhereIsMyFriendsEvent.where(user_id: user.id).delete_all

  if (location = attributes[:location])
    UserLocation.upsert_city_location(user.id, **location)
  end
end

puts "Seeded Local Friends E2E users (password: #{password})"

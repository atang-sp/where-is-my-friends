# frozen_string_literal: true

desc "Send a one-time notification to users with a Discourse profile location who haven't joined local discovery"
task "where_is_my_friends:notify_profile_location_users" => :environment do
  MESSAGE_KEY = "where_is_my_friends.notification.title"
  TITLE_KEY = "where_is_my_friends.notification.title"

  users =
    User
      .real
      .joins(:user_profile)
      .where.not(user_profiles: { location: [nil, ""] })
      .where.not(id: UserLocation.select(:user_id))

  total = users.count
  sent = 0

  puts "Found #{total} users with profile location but not in local discovery"

  users.find_each do |user|
    profile_city = user.user_profile.location.to_s.strip
    next if profile_city.blank?

    city_key = UserLocation.normalize_city(profile_city)
    nearby_count =
      UserLocation.active_for_discovery.where(city_key: city_key).count

    Notification.create!(
      notification_type: Notification.types[:custom],
      user_id: user.id,
      data: {
        message: MESSAGE_KEY,
        title: TITLE_KEY,
        topic_title:
          I18n.t(
            "where_is_my_friends.notification.profile_location_invite",
            city: profile_city,
            count: [nearby_count, 1].max,
            locale: user.effective_locale
          ),
      }.to_json
    )
    sent += 1
  end

  puts "Sent #{sent} notifications out of #{total} eligible users"
end

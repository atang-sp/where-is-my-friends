# frozen_string_literal: true

desc "Send a one-time notification to users with a Discourse profile location who haven't joined local discovery"
task "where_is_my_friends:notify_profile_location_users" => :environment do
  message_key = "where_is_my_friends.notification.title"
  title_key = "where_is_my_friends.notification.title"

  users =
    User
      .real
      .activated
      .not_staged
      .not_suspended
      .not_silenced
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
      UserLocation.discoverable.where(city_key: city_key).count
    invite_key =
      if nearby_count.zero?
        "where_is_my_friends.notification.profile_location_invite_empty"
      elsif WhereIsMyFriends::AggregatePrivacy.suppressed?(nearby_count)
        "where_is_my_friends.notification.profile_location_invite_suppressed"
      else
        "where_is_my_friends.notification.profile_location_invite"
      end

    Notification.create!(
      notification_type: Notification.types[:custom],
      user_id: user.id,
      data: {
        message: message_key,
        title: title_key,
        topic_title:
          I18n.t(
            invite_key,
            city: profile_city,
            count: nearby_count,
            locale: user.effective_locale
          )
      }.to_json
    )
    sent += 1
  end

  puts "Sent #{sent} notifications out of #{total} eligible users"
end

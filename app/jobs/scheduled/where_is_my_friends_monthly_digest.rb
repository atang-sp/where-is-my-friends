# frozen_string_literal: true

module Jobs
  class WhereIsMyFriendsMonthlyDigest < ::Jobs::Scheduled
    every 1.month

    MESSAGE_KEY = "where_is_my_friends.notification.title"
    TITLE_KEY = "where_is_my_friends.notification.title"

    def execute(_args)
      return unless SiteSetting.where_is_my_friends_enabled

      UserLocation
        .active_for_discovery
        .includes(:user)
        .find_each do |location|
          next unless location.user&.user_option&.where_is_my_friends_notify_city

          radius = location.effective_discovery_radius_km
          nearby_keys =
            WhereIsMyFriends::CityCentroidLookup.instance.city_keys_within_radius(
              location.city_key,
              radius
            )

          new_nearby_count =
            UserLocation
              .active_for_discovery
              .where(city_key: nearby_keys)
              .where.not(user_id: location.user_id)
              .where("user_locations.created_at > ?", 30.days.ago)
              .count

          next if new_nearby_count == 0

          Notification.create!(
            notification_type: Notification.types[:custom],
            user_id: location.user_id,
            data: {
              message: MESSAGE_KEY,
              title: TITLE_KEY,
              topic_title:
                I18n.t(
                  "where_is_my_friends.notification.monthly_digest",
                  count: new_nearby_count,
                  locale: location.user.effective_locale
                ),
            }.to_json
          )
        end
    end
  end
end

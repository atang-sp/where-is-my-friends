# frozen_string_literal: true

module Jobs
  class WhereIsMyFriendsWeeklyNearbyDigest < ::Jobs::Scheduled
    every 1.week

    MESSAGE_KEY = "where_is_my_friends.notification.nearby_weekly"
    TITLE_KEY = "where_is_my_friends.notification.title"

    def execute(_args)
      return unless SiteSetting.where_is_my_friends_enabled

      UserLocation
        .discoverable
        .includes(user: :user_option)
        .find_each do |location|
          unless location.user&.user_option&.where_is_my_friends_notify_nearby
            next
          end

          new_nearby_count = new_nearby_count_for(location)
          next if new_nearby_count.zero?

          Notification.create!(
            notification_type: Notification.types[:custom],
            user_id: location.user_id,
            data: {
              message: MESSAGE_KEY,
              title: TITLE_KEY,
              topic_title:
                I18n.t(
                  weekly_digest_key(new_nearby_count),
                  count: new_nearby_count,
                  locale: location.user.effective_locale
                ),
              where_is_my_friends: true,
              notification_source: "nearby_weekly"
            }.to_json
          )
        end
    end

    private

    def new_nearby_count_for(location)
      nearby_keys =
        WhereIsMyFriends::CityCentroidLookup.instance.city_keys_within_radius(
          location.city_key,
          location.effective_discovery_radius_km
        ) - [location.city_key]
      return 0 if nearby_keys.empty?

      UserLocation
        .discoverable
        .where(city_key: nearby_keys)
        .where.not(user_id: location.user_id)
        .where("user_locations.city_joined_at > ?", 7.days.ago)
        .count
    end

    def weekly_digest_key(count)
      if WhereIsMyFriends::AggregatePrivacy.suppressed?(count)
        "where_is_my_friends.notification.weekly_nearby_digest_suppressed"
      else
        "where_is_my_friends.notification.weekly_nearby_digest"
      end
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  class MemberJoinedNotifier
    MESSAGE_KEY = "where_is_my_friends.notification.member_joined"
    TITLE_KEY = "where_is_my_friends.notification.title"
    DAILY_LIMIT = 3

    def self.notify!(joiner:, city:, city_key:)
      new(joiner: joiner, city: city, city_key: city_key).notify!
    end

    def initialize(joiner:, city:, city_key:)
      @joiner = joiner
      @city = city
      @city_key = city_key
    end

    def notify!
      return if @joiner.blank? || @city_key.blank?

      recipients.find_each { |user| notify_user(user) }
    end

    private

    def recipients
      User
        .joins(:user_option)
        .joins(
          "INNER JOIN user_locations ON user_locations.user_id = users.id"
        )
        .merge(UserLocation.active_for_discovery)
        .where(user_locations: { city_key: @city_key })
        .where.not(users: { id: @joiner.id })
        .where(user_options: { where_is_my_friends_notify_city: true })
    end

    def notify_user(user)
      return if daily_count(user) >= DAILY_LIMIT

      Notification.create!(
        notification_type: Notification.types[:custom],
        user_id: user.id,
        data: {
          message: MESSAGE_KEY,
          title: TITLE_KEY,
          display_username: @joiner.username,
          topic_title:
            I18n.t(
              "where_is_my_friends.notification.member_joined_description",
              city: @city,
              locale: user.effective_locale
            ),
          city: @city
        }.to_json
      )
    rescue StandardError
      # Notifications must never block location setup.
    end

    def daily_count(user)
      Notification
        .where(
          user_id: user.id,
          notification_type: Notification.types[:custom]
        )
        .where("created_at > ?", 1.day.ago)
        .where("data::jsonb->>'message' = ?", MESSAGE_KEY)
        .count
    end
  end
end

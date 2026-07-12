# frozen_string_literal: true

module Jobs
  class WhereIsMyFriendsProfileInvite < ::Jobs::Scheduled
    every 1.day

    CUSTOM_FIELD_KEY = "where_is_my_friends_invite_sent"

    def execute(_args)
      return unless SiteSetting.where_is_my_friends_enabled

      candidates.find_each { |user| invite_user(user) }
    end

    private

    def candidates
      User
        .joins(:user_profile)
        .where.not(user_profiles: { location: [nil, ""] })
        .where(active: true)
        .where(
          "users.id NOT IN (SELECT user_id FROM user_locations)"
        )
        .where(
          "users.id NOT IN (SELECT user_id FROM user_custom_fields WHERE name = ?)",
          CUSTOM_FIELD_KEY
        )
        .limit(50)
    end

    def invite_user(user)
      city = user.user_profile.location.strip
      nearby_count = UserLocation
        .active_for_discovery
        .where(city_key: UserLocation.normalize_city(city))
        .count

      body = I18n.t(
        "where_is_my_friends.notification.profile_location_invite",
        city: city,
        count: [nearby_count, 1].max,
        locale: user.effective_locale
      )

      url = "/where-is-my-friends?auto_city=#{CGI.escape(city)}"

      PostCreator.create!(
        Discourse.system_user,
        archetype: Archetype.private_message,
        target_usernames: user.username,
        title: I18n.t(
          "where_is_my_friends.invite_pm_title",
          locale: user.effective_locale
        ),
        raw: "#{body}\n\n[#{I18n.t("where_is_my_friends.invite_pm_cta", locale: user.effective_locale)}](#{url})"
      )

      UserCustomField.create!(
        user_id: user.id,
        name: CUSTOM_FIELD_KEY,
        value: Time.current.iso8601
      )
    rescue StandardError
      # Individual failures must not abort the batch.
    end
  end
end

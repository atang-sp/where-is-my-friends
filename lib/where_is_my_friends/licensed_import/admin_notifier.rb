# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class AdminNotifier
      MESSAGE_KEY = "where_is_my_friends.notification.licensed_import_halted"
      TITLE_KEY = "where_is_my_friends.notification.title"

      def notify(code)
        return unless acquire_daily_notice(code)

        User
          .where(admin: true, active: true)
          .find_each do |admin|
            Notification.create!(
              notification_type: Notification.types[:custom],
              user_id: admin.id,
              data: {
                message: MESSAGE_KEY,
                title: TITLE_KEY,
                topic_title:
                  I18n.t(
                    "where_is_my_friends.notification.licensed_import_reason",
                    reason:
                      I18n.t(
                        "where_is_my_friends.licensed_import.reasons.#{code}",
                        locale: admin.effective_locale,
                        default: code.to_s.humanize
                      ),
                    locale: admin.effective_locale
                  ),
                where_is_my_friends: true,
                notification_source: "licensed_import"
              }.to_json
            )
          end
      end

      private

      def acquire_daily_notice(code)
        Discourse.redis.set(
          "wimf:licensed_import:notice:#{code}",
          "1",
          nx: true,
          ex: 1.day.to_i
        )
      end
    end
  end
end

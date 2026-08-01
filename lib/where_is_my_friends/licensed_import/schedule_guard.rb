# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class ScheduleGuard
      ZONE = "Asia/Shanghai"

      def due?(now: Time.zone.now)
        return false unless SiteSetting.licensed_import_enabled

        beijing_now = now.in_time_zone(ZONE)
        unless beijing_now.hour == SiteSetting.licensed_import_publish_hour.to_i
          return false
        end
        return false if beijing_now.min.nonzero?
        if completed_today(beijing_now) >=
             SiteSetting.licensed_import_max_per_day.to_i
          return false
        end

        last_completed = completed.order(created_at: :desc).pick(:created_at)
        return true if last_completed.blank?

        interval = [
          SiteSetting.licensed_import_interval_hours.to_i,
          20
        ].max.hours
        now >= last_completed + interval
      end

      private

      def completed
        WhereIsMyFriendsLicensedImport.where(status: %w[preview published])
      end

      def completed_today(beijing_now)
        completed.where(
          created_at:
            beijing_now.beginning_of_day.utc..beijing_now.end_of_day.utc
        ).count
      end
    end
  end
end

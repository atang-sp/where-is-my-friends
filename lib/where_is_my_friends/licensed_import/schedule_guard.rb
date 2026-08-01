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

        publication_allowed?(now: now)
      end

      def publication_allowed?(now: Time.zone.now, excluding_record_id: nil)
        beijing_now = now.in_time_zone(ZONE)
        scope = completed
        scope = scope.where.not(id: excluding_record_id) if excluding_record_id
        if completed_today(scope, beijing_now) >=
             SiteSetting.licensed_import_max_per_day.to_i
          return false
        end

        last_completed = last_completed_at(scope)
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

      def completed_today(scope, beijing_now)
        range = beijing_now.beginning_of_day.utc..beijing_now.end_of_day.utc
        previews = scope.where(status: "preview", created_at: range).count
        published = scope.where(status: "published", published_at: range).count
        legacy_published =
          scope.where(
            status: "published",
            published_at: nil,
            created_at: range
          ).count
        previews + published + legacy_published
      end

      def last_completed_at(scope)
        preview_at = scope.where(status: "preview").maximum(:created_at)
        published_at =
          scope.where(status: "published").maximum(
            Arel.sql("COALESCE(published_at, created_at)")
          )
        [preview_at, published_at].compact.max
      end
    end
  end
end

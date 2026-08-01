# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class IncidentResponder
      REASONS = %w[
        copyright_complaint
        serious_safety_miss
        attribution_error
      ].freeze

      def initialize(publisher: Publisher.new, notifier: AdminNotifier.new)
        @publisher = publisher
        @notifier = notifier
      end

      def halt!(source_type:, source_question_id:, reason:)
        raise ArgumentError if REASONS.exclude?(reason)

        records =
          WhereIsMyFriendsLicensedImport.where(
            source_type: source_type,
            source_question_id: source_question_id,
            status: %w[preview published]
          )
        raise ActiveRecord::RecordNotFound if records.empty?

        SiteSetting.licensed_import_enabled = false
        records.find_each do |record|
          @publisher.hide!(record) if record.topic_id
          record.update!(status: "hidden", failure_code: reason)
        end
        @notifier.notify(reason)
        true
      end
    end
  end
end

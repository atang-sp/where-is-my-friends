# frozen_string_literal: true

module Jobs
  class WhereIsMyFriendsLicensedImportSourceSync < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      return unless SiteSetting.where_is_my_friends_enabled

      WhereIsMyFriends::LicensedImport::SourceSynchronizer.new.call
    rescue StandardError
      WhereIsMyFriends::LicensedImport::AdminNotifier.new.notify(
        "source_sync_failure"
      )
    end
  end
end

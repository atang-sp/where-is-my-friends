# frozen_string_literal: true

module Jobs
  class WhereIsMyFriendsLicensedImport < ::Jobs::Scheduled
    every 1.hour

    HALTING_FAILURES = %w[missing_api_key monthly_token_budget_exhausted].freeze
    DRY_RUN_PREVIEW_LIMIT = 3

    def execute(_args)
      return unless SiteSetting.where_is_my_friends_enabled
      return unless SiteSetting.licensed_import_enabled
      return unless WhereIsMyFriends::LicensedImport::ScheduleGuard.new.due?

      notifier = WhereIsMyFriends::LicensedImport::AdminNotifier.new
      guard =
        WhereIsMyFriends::LicensedImport::EngagementGuard.new(
          notifier: notifier
        )
      return unless guard.allow_publication?

      WhereIsMyFriends::LicensedImport::SourceSynchronizer.new.call
      outcome = WhereIsMyFriends::LicensedImport::Pipeline.new.run
      handle_outcome(outcome, notifier)
    rescue StandardError
      SiteSetting.licensed_import_enabled = false
      WhereIsMyFriends::LicensedImport::AdminNotifier.new.notify(
        "unexpected_failure"
      )
    end

    private

    def handle_outcome(outcome, notifier)
      if HALTING_FAILURES.include?(outcome.failure_code)
        SiteSetting.licensed_import_enabled = false
        notifier.notify(outcome.failure_code)
      elsif outcome.status == "preview" &&
            WhereIsMyFriendsLicensedImport.where(status: "preview").count >=
              DRY_RUN_PREVIEW_LIMIT
        SiteSetting.licensed_import_enabled = false
        notifier.notify("dry_run_ready_for_review")
      end
    end
  end
end

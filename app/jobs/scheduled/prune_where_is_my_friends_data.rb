# frozen_string_literal: true

module Jobs
  class PruneWhereIsMyFriendsData < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      UserLocation.where("expires_at <= ?", Time.current).delete_all

      if defined?(WhereIsMyFriendsEvent)
        WhereIsMyFriendsEvent.where("created_at < ?", 90.days.ago).delete_all
      end
    end
  end
end

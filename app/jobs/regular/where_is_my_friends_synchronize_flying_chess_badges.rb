# frozen_string_literal: true

module Jobs
  class WhereIsMyFriendsSynchronizeFlyingChessBadges < ::Jobs::Base
    def execute(_args = {})
      WhereIsMyFriendsFlyingChessProfile.find_each do |profile|
        profile.synchronize_first_takeoff_badge!
      end
    end
  end
end

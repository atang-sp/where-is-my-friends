# frozen_string_literal: true

module Jobs
  class WhereIsMyFriendsNotifyCityMembers < ::Jobs::Base
    def execute(args)
      joiner = User.find_by(id: args[:joiner_id])
      return if joiner.blank?

      WhereIsMyFriends::MemberJoinedNotifier.notify!(
        joiner: joiner,
        city: args[:city],
        city_key: args[:city_key]
      )
    end
  end
end

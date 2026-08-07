# frozen_string_literal: true

module WhereIsMyFriends
  module FlyingChess
    FIRST_TAKEOFF_BADGE_NAME = "飞行棋·初次起飞"

    def self.achievements_enabled?
      SiteSetting.where_is_my_friends_enabled &&
        SiteSetting.where_is_my_friends_flying_chess_achievements_enabled
    end
  end
end

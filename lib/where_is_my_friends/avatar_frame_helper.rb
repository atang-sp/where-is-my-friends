# frozen_string_literal: true

module WhereIsMyFriends
  class CurrentContext < ActiveSupport::CurrentAttributes
    attribute :level_cache, :role_cache

    def self.level_map
      self.level_cache ||= {}
    end

    def self.role_map
      self.role_cache ||= {}
    end
  end

  module AvatarFrameHelper
    class << self
      def community_level_for(user)
        return nil unless user
        user_id = user.is_a?(Hash) ? user[:id] : user.try(:id)
        return nil unless user_id
        return nil unless defined?(::DiscourseCommunityLevels::GamificationScoreProvider) &&
                          defined?(::DiscourseCommunityLevels::SerializerHelpers) &&
                          DiscourseCommunityLevels::SerializerHelpers.enabled?

        CurrentContext.level_map[user_id] ||= begin
          scores = ::DiscourseCommunityLevels::GamificationScoreProvider.scores_for([user_id])
          ::DiscourseCommunityLevels::SerializerHelpers.public_level_payload(scores[user_id].to_i)
        end
      rescue StandardError
        nil
      end

      def role_key_for(user)
        return nil unless user
        user_id = user.is_a?(Hash) ? user[:id] : user.try(:id)
        return nil unless user_id

        CurrentContext.role_map[user_id] ||= begin
          val = UserCustomField.where(user_id: user_id, name: "user_field_1").pick(:value)
          UserLocationSerializer.map_role_value(val)
        end
      rescue StandardError
        nil
      end
    end
  end
end

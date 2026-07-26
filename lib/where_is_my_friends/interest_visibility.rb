# frozen_string_literal: true

module WhereIsMyFriends
  class InterestVisibility
    def self.onboarding_state(user)
      WhereIsMyFriendsInterestProfile.find_by(user_id: user.id)&.state ||
        "pending"
    end

    def self.public_interests(user, guardian:)
      return [] unless SiteSetting.where_is_my_friends_enabled
      unless SiteSetting.where_is_my_friends_interest_onboarding_enabled
        return []
      end

      profile =
        WhereIsMyFriendsInterestProfile.find_by(
          user_id: user.id,
          personalization_enabled: true,
          show_interests_publicly: true
        )
      return [] if profile&.completed_at.blank?

      visible_tags =
        DiscourseTagging
          .visible_tags(guardian)
          .where(id: profile.interests.select(:tag_id))
          .index_by(&:id)

      profile.interests.filter_map do |interest|
        tag = visible_tags[interest.tag_id]
        { id: tag.id, name: tag.name } if tag
      end
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  class UserTagVisibility
    def self.feature_enabled?
      SiteSetting.where_is_my_friends_enabled &&
        SiteSetting.where_is_my_friends_user_tags_enabled
    end

    def self.public_tags_for(target_user, viewer:)
      return [] unless feature_enabled?
      return [] unless viewer.is_a?(User)

      member_selection =
        ViewerAwareMemberSelection.new(
          viewer: viewer,
          guardian: Guardian.new(viewer)
        )
      return [] unless member_selection.visible?(target_user)
      return [] if blocked_relationship?(viewer, target_user)

      max_displayed =
        SiteSetting.where_is_my_friends_user_tag_max_displayed.to_i.clamp(1, 20)
      tags =
        WhereIsMyFriendsUserTag
          .approved
          .where(target_user_id: target_user.id)
          .left_joins(:endorsements)
          .group("where_is_my_friends_user_tags.id")
          .order(
            Arel.sql(
              "COUNT(where_is_my_friends_tag_endorsements.id) DESC, " \
                "where_is_my_friends_user_tags.id ASC"
            )
          )
          .limit(max_displayed)
          .to_a

      counts =
        WhereIsMyFriendsTagEndorsement
          .where(tag_id: tags.map(&:id))
          .group(:tag_id)
          .count
      endorsed_by_me =
        WhereIsMyFriendsTagEndorsement
          .where(tag_id: tags.map(&:id), user_id: viewer.id)
          .pluck(:tag_id)
          .to_set

      tags.map do |tag|
        {
          id: tag.id,
          label: tag.label,
          endorser_count: counts.fetch(tag.id, 0),
          endorsed_by_me: endorsed_by_me.include?(tag.id)
        }
      end
    end

    def self.serialize_tag(tag, viewer)
      {
        id: tag.id,
        label: tag.label,
        endorser_count: tag.endorsements.count,
        endorsed_by_me: tag.endorsements.where(user_id: viewer.id).exists?
      }
    end

    def self.blocked_relationship?(viewer, target)
      ids = [viewer.id, target.id]
      pair_sql =
        "(user_id = :viewer AND muted_user_id = :target) OR " \
          "(user_id = :target AND muted_user_id = :viewer)"
      if MutedUser.where(pair_sql, viewer: ids.first, target: ids.last).exists?
        return true
      end

      ignored_pair_sql =
        "(user_id = :viewer AND ignored_user_id = :target) OR " \
          "(user_id = :target AND ignored_user_id = :viewer)"
      IgnoredUser
        .where(ignored_pair_sql, viewer: ids.first, target: ids.last)
        .where("expiring_at > ?", Time.current)
        .exists?
    end
  end
end

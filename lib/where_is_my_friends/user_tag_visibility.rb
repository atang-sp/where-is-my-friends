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

    def self.bulk_public_tags_for(target_users, viewer:)
      return {} unless feature_enabled?
      return {} unless viewer.is_a?(User)
      return {} if target_users.empty?

      member_selection = ViewerAwareMemberSelection.new(viewer: viewer, guardian: Guardian.new(viewer))
      visible_users = target_users.select { |u| member_selection.visible?(u) && !blocked_relationship?(viewer, u) }
      return {} if visible_users.empty?

      max_displayed = SiteSetting.where_is_my_friends_user_tag_max_displayed.to_i.clamp(1, 20)
      
      # For bulk fetch, we fetch top N for each user using window functions or ruby-side limiting
      # Using Ruby-side grouping for simplicity since N is small
      all_tags = WhereIsMyFriendsUserTag
        .approved
        .where(target_user_id: visible_users.map(&:id))
        .left_joins(:endorsements)
        .select("where_is_my_friends_user_tags.*, COUNT(where_is_my_friends_tag_endorsements.id) AS endorsement_count")
        .group("where_is_my_friends_user_tags.id")
        .to_a

      tags_by_user = all_tags.group_by(&:target_user_id)
      top_tags_by_user = tags_by_user.transform_values do |tags|
        tags.sort_by { |t| [-t.endorsement_count, t.id] }.first(max_displayed)
      end

      tag_ids = top_tags_by_user.values.flatten.map(&:id)
      return {} if tag_ids.empty?

      counts = WhereIsMyFriendsTagEndorsement.where(tag_id: tag_ids).group(:tag_id).count
      endorsed_by_me = WhereIsMyFriendsTagEndorsement.where(tag_id: tag_ids, user_id: viewer.id).pluck(:tag_id).to_set

      visible_users.each_with_object({}) do |user, hash|
        user_tags = top_tags_by_user.fetch(user.id, [])
        hash[user.id] = user_tags.map do |tag|
          {
            id: tag.id,
            label: tag.label,
            endorser_count: counts.fetch(tag.id, 0),
            endorsed_by_me: endorsed_by_me.include?(tag.id)
          }
        end
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

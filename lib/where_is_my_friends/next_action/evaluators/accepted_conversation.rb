# frozen_string_literal: true

require_relative "base"

module WhereIsMyFriends
  class NextAction
    module Evaluators
      class AcceptedConversation < Base
        FOLLOW_UP_WINDOW = 7.days
        MAX_ACCEPTED_INVITATIONS = 10

        def evaluate
          topic_id = accepted_conversation_topic_id
          return unless topic_id

          action(
            :continue_conversation,
            primary_kind: :open_conversation,
            primary_url: "/t/#{topic_id}"
          )
        end

        def accepted_conversation_topic_id
          return unless invitation_actions_enabled?

          invitations =
            WhereIsMyFriendsPracticeInvitation
              .select(:id, :pm_topic_id, :responded_at)
              .where(
                sender_id: user.id,
                status: "accepted",
                responded_at: (as_of - FOLLOW_UP_WINDOW)..as_of
              )
              .where.not(pm_topic_id: nil)
              .order(responded_at: :desc, id: :desc)
              .limit(MAX_ACCEPTED_INVITATIONS)
              .to_a
          return if invitations.empty?

          visible_topic_ids =
            Topic
              .where(
                id: invitations.map(&:pm_topic_id),
                archetype: Archetype.private_message,
                visible: true,
                deleted_at: nil
              )
              .private_messages_for_user(user)
              .pluck(:id)
              .to_set
          replied_invitation_ids = sender_reply_invitation_ids(invitations)

          invitations
            .find do |invitation|
              visible_topic_ids.include?(invitation.pm_topic_id) &&
                replied_invitation_ids.exclude?(invitation.id)
            end
            &.pm_topic_id
        end

        private

        def sender_reply_invitation_ids(invitations)
          invitation_table = WhereIsMyFriendsPracticeInvitation.table_name
          Post
            .joins(
              "INNER JOIN #{invitation_table} ON " \
                "#{invitation_table}.pm_topic_id = posts.topic_id"
            )
            .where(invitation_table => { id: invitations.map(&:id) })
            .where(
              user_id: user.id,
              post_type: Post.types[:regular],
              deleted_at: nil,
              hidden: false,
              post_number: 2..
            )
            .where("posts.created_at > #{invitation_table}.responded_at")
            .where("posts.created_at <= ?", as_of)
            .distinct
            .pluck(Arel.sql("#{invitation_table}.id"))
            .to_set
        end
      end
    end
  end
end

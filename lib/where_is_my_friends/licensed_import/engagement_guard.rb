# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class EngagementGuard
      MATURE_AFTER = 7.days
      CONSECUTIVE_LIMIT = 7
      REVIEW_WINDOW = 30.days
      MIN_REPLY_RATE = 0.5

      def initialize(notifier: AdminNotifier.new)
        @notifier = notifier
      end

      def allow_publication?
        code = no_reply_code || thirty_day_code
        return pause!(code) if code

        true
      end

      def stats(now: Time.zone.now)
        recent =
          published
            .where.not(topic_id: nil)
            .where(published_at: (now - REVIEW_WINDOW)..(now - MATURE_AFTER))
            .to_a
        replied = human_reply_topic_ids(recent)
        current_originals =
          human_original_topics_between(now - REVIEW_WINDOW, now)
        previous_originals =
          human_original_topics_between(
            now - (2 * REVIEW_WINDOW),
            now - REVIEW_WINDOW
          )
        {
          published_count: recent.length,
          human_replied_count: replied.length,
          seven_day_human_reply_rate:
            (
              if recent.empty?
                0.0
              else
                (replied.length.to_f / recent.length).round(4)
              end
            ),
          current_human_original_topics: current_originals,
          previous_human_original_topics: previous_originals
        }
      end

      private

      def no_reply_code
        records =
          published
            .where("published_at <= ?", MATURE_AFTER.ago)
            .order(published_at: :desc)
            .limit(CONSECUTIVE_LIMIT)
            .to_a
        return unless records.length == CONSECUTIVE_LIMIT
        return if human_reply_topic_ids(records).any?

        "seven_without_human_reply"
      end

      def thirty_day_code
        first_published = published.minimum(:published_at)
        return if first_published.blank? || first_published > REVIEW_WINDOW.ago

        values = stats
        return if values.fetch(:published_count) < CONSECUTIVE_LIMIT
        if values.fetch(:seven_day_human_reply_rate) < MIN_REPLY_RATE
          return "thirty_day_reply_rate_below_half"
        end
        if values.fetch(:previous_human_original_topics).positive? &&
             values.fetch(:current_human_original_topics) <
               values.fetch(:previous_human_original_topics)
          return "human_original_topics_declined"
        end

        nil
      end

      def published
        WhereIsMyFriendsLicensedImport.published.where.not(published_at: nil)
      end

      def human_reply_topic_ids(records)
        records.filter_map do |record|
          next if record.topic_id.blank? || record.published_at.blank?

          replies =
            Post
              .where(
                topic_id: record.topic_id,
                post_type: Post.types[:regular],
                post_number: 2..,
                created_at:
                  record.published_at..(record.published_at + MATURE_AFTER)
              )
              .where(deleted_at: nil, hidden: false)
              .where.not(user_id: Discourse.system_user.id)
          record.topic_id if replies.exists?
        end
      end

      def human_original_topics_between(start_at, end_at)
        imported_ids =
          WhereIsMyFriendsLicensedImport
            .where.not(topic_id: nil)
            .select(:topic_id)
        Topic
          .where(created_at: start_at...end_at)
          .where(archetype: Archetype.default, visible: true, deleted_at: nil)
          .where.not(user_id: Discourse.system_user.id)
          .where.not(id: imported_ids)
          .count
      end

      def pause!(code)
        SiteSetting.licensed_import_enabled = false
        @notifier.notify(code)
        false
      end
    end
  end
end

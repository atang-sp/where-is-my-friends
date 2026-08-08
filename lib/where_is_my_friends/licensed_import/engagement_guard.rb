# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class EngagementGuard
      MATURE_AFTER = 7.days
      REVIEW_WINDOW = 30.days
      MIN_REPLY_RATE = 0.5

      def initialize(
        notifier: AdminNotifier.new,
        mature_sample_size: SourceCatalog.candidate_capacity
      )
        @notifier = notifier
        @mature_sample_size = Integer(mature_sample_size)
        raise ArgumentError if @mature_sample_size < 1
      end

      def allow_publication?(as_of: Time.zone.now)
        code = no_reply_code(as_of:) || thirty_day_code(as_of:)
        return pause!(code) if code

        true
      end

      def stats(as_of: Time.zone.now)
        recent =
          published
            .where.not(topic_id: nil)
            .where("published_at <= ?", as_of - MATURE_AFTER)
            .order(published_at: :asc, id: :asc)
            .limit(@mature_sample_size)
            .to_a
        replied = human_reply_topic_ids(recent)
        current_originals =
          human_original_topics_between(as_of - REVIEW_WINDOW, as_of)
        previous_originals =
          human_original_topics_between(
            as_of - (2 * REVIEW_WINDOW),
            as_of - REVIEW_WINDOW
          )
        {
          published_count: recent.length,
          mature_sample_requirement: @mature_sample_size,
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

      def no_reply_code(as_of:)
        records =
          published
            .where("published_at <= ?", as_of - MATURE_AFTER)
            .order(published_at: :desc)
            .limit(@mature_sample_size)
            .to_a
        return unless records.length == @mature_sample_size
        return if human_reply_topic_ids(records).any?

        "pilot_without_human_reply"
      end

      def thirty_day_code(as_of:)
        first_published = published.minimum(:published_at)
        if first_published.blank? || first_published > as_of - REVIEW_WINDOW
          return
        end

        values = stats(as_of:)
        if values.fetch(:published_count) < @mature_sample_size
          return "thirty_day_insufficient_mature_sample"
        end
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
        WhereIsMyFriendsLicensedImport
          .published
          .where.not(published_at: nil)
          .where(
            source_type: SourceCatalog.candidate_source_type,
            source_question_id: SourceCatalog.candidate_source_ids
          )
      end

      def human_reply_topic_ids(records)
        published_at_by_topic_id =
          records
            .filter_map do |record|
              if record.topic_id.present? && record.published_at.present?
                [record.topic_id, record.published_at]
              end
            end
            .to_h
        return [] if published_at_by_topic_id.empty?

        Post
          .where(
            topic_id: published_at_by_topic_id.keys,
            post_type: Post.types[:regular],
            post_number: 2..
          )
          .where(deleted_at: nil, hidden: false)
          .where.not(user_id: Discourse.system_user.id)
          .pluck(:topic_id, :created_at)
          .filter_map do |topic_id, created_at|
            published_at = published_at_by_topic_id.fetch(topic_id)
            if created_at.between?(published_at, published_at + MATURE_AFTER)
              topic_id
            end
          end
          .uniq
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

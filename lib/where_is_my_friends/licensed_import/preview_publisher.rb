# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class PreviewPublisher
      class InvalidPreview < StandardError
      end
      class PublicationNotDue < StandardError
      end
      class RepeatedTheme < StandardError
      end

      def initialize(publisher: Publisher.new, source: SourceCatalog.new)
        @publisher = publisher
        @source_verifier = SourceVerifier.new(source: source)
      end

      def call(record_id)
        PublicationLock.synchronize { publish(record_id) }
      end

      private

      def publish(record_id)
        record = WhereIsMyFriendsLicensedImport.find(record_id)
        post = nil
        record.with_lock do
          if record.status == "published"
            post = published_post(record)
            next
          end
          validate_preview!(record)

          post = existing_post(record)
          unless post
            @publisher.validate_configuration!
            ensure_publication_due!(record)
            ensure_theme_rotation!(record)
            @source_verifier.verify!(record)
            post =
              @publisher.publish!(
                title: record.translated_title,
                raw: record.translated_body,
                tags:
                  PublicationTags.for(
                    record.theme,
                    source_type: record.source_type
                  ),
                source_type: record.source_type,
                source_question_id: record.source_question_id
              )
          end
          mark_published!(record, post)
        end
        post
      end

      def validate_preview!(record)
        metadata = [
          record.source_answer_id,
          record.source_question_url,
          record.source_answer_url,
          record.question_author,
          record.answer_author,
          record.question_license,
          record.answer_license,
          record.scheduled_for_date
        ]
        valid_license =
          [record.question_license, record.answer_license].all? do |license|
            license.to_s.match?(Pipeline::LICENSE_PATTERN)
          end
        valid_body =
          record.translated_body.to_s.include?(translate("post.disclosure")) &&
            record.translated_body.to_s.include?(
              translate("post.attribution_heading")
            ) &&
            [
              record.source_question_url,
              record.source_answer_url,
              escaped_author(record.question_author),
              escaped_author(record.answer_author),
              record.question_license,
              record.answer_license
            ].all? { |value| record.translated_body.to_s.include?(value.to_s) }
        valid_urls =
          [record.source_question_url, record.source_answer_url].all? do |url|
            https_url?(url)
          end
        unless record.status == "preview" && metadata.all?(&:present?) &&
                 valid_license && valid_urls &&
                 AiGateway::THEMES.include?(record.theme) &&
                 record.token_count.positive? && record.failure_code.blank? &&
                 record.translated_title.to_s.start_with?(
                   "#{translate("title_prefix")} "
                 ) && valid_body && valid_gfdl_body?(record)
          raise InvalidPreview
        end
      end

      def valid_gfdl_body?(record)
        return true unless record.source_type == "spanking_art"

        body = record.translated_body.to_s
        [
          PostFormatter::GFDL_NOTICE,
          PostFormatter::GFDL_TEXT,
          "## #{translate("post.gfdl_history_heading")}",
          "Copyright ©"
        ].all? { |required| body.include?(required) }
      end

      def existing_post(record)
        topic_id =
          TopicCustomField
            .where(
              name: "where_is_my_friends_licensed_import_source_key",
              value: "#{record.source_type}:#{record.source_question_id}"
            )
            .order(id: :desc)
            .pick(:topic_id)
        topic = Topic.find_by(id: topic_id, deleted_at: nil, visible: true)
        topic&.first_post
      end

      def published_post(record)
        post = Post.find_by(id: record.first_post_id, deleted_at: nil)
        raise InvalidPreview if post.blank?

        post
      end

      def ensure_publication_due!(record)
        allowed =
          ScheduleGuard.new.publication_allowed?(excluding_record_id: record.id)
        raise PublicationNotDue unless allowed
      end

      def ensure_theme_rotation!(record)
        previous_theme =
          WhereIsMyFriendsLicensedImport
            .published
            .where.not(id: record.id)
            .where.not(published_at: nil)
            .order(published_at: :desc)
            .pick(:theme)
        raise RepeatedTheme if previous_theme == record.theme
      end

      def mark_published!(record, post)
        record.update!(
          status: "published",
          topic_id: post.topic_id,
          first_post_id: post.id,
          published_at: record.published_at || Time.zone.now
        )
      end

      def translate(key)
        I18n.t("where_is_my_friends.licensed_import.#{key}", locale: :zh_CN)
      end

      def escaped_author(author)
        author.to_s.gsub(/([\[\]\\])/, '\\\\\1')
      end

      def https_url?(value)
        uri = URI.parse(value.to_s)
        uri.is_a?(URI::HTTPS) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end

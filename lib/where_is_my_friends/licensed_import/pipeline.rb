# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class Pipeline
      Outcome = Struct.new(:status, :failure_code, :record, keyword_init: true)
      LICENSE_PATTERN = /\ACC BY-SA (?:3\.0|4\.0)\z/
      TERMINAL_FAILURE_CODES = %w[
        missing_api_key
        monthly_token_budget_exhausted
        ai_error
      ].freeze
      PROCESSING_STALE_AFTER = 20.hours

      def initialize(
        source: StackExchangeClient.new,
        moderator: nil,
        model: nil,
        publisher: Publisher.new,
        processor: ContentProcessor.new,
        policy: ContentPolicy.new,
        formatter: PostFormatter.new,
        budget: TokenBudget.new
      )
        @source = source
        @moderator = moderator
        @model = model
        @publisher = publisher
        @processor = processor
        @policy = policy
        @formatter = formatter
        @budget = budget
      end

      def run
        return skipped("disabled") unless SiteSetting.licensed_import_enabled

        prepare_ai_clients!

        documents = @source.candidates
        return skipped("no_candidate") if documents.blank?

        last_outcome = nil
        documents.each do |document|
          recovered = recover_publication(document)
          return recovered if recovered

          if imported?(document)
            last_outcome = skipped("duplicate_source")
            next
          end

          last_outcome = process(document)
          if %w[preview published].include?(last_outcome.status)
            return last_outcome
          end
          if TERMINAL_FAILURE_CODES.include?(last_outcome.failure_code)
            return last_outcome
          end
        end
        last_outcome || skipped("no_candidate")
      rescue StackExchangeClient::SourceError
        skipped("source_error")
      rescue AiGateway::MissingApiKey,
             AiGateway::MissingCredentialMasterKey,
             AiGateway::InvalidCredential
        Outcome.new(status: "failed", failure_code: "missing_api_key")
      rescue ActiveRecord::RecordNotUnique
        skipped("already_claimed")
      end

      private

      def prepare_ai_clients!
        @moderator ||= OpenAiModerationClient.new
        @model ||= ResponsesClient.new
      end

      def process(document)
        record = start_record(document)
        return failure(record, "license_missing") unless licensed?(document)

        content = @processor.call(document)
        unless content.word_count.between?(400, 3_500)
          return failure(record, "word_count_out_of_range")
        end

        hard_failure =
          @policy.failure_code(
            ([content.title] + content.segments.map(&:text)).join("\n")
          )
        return failure(record, hard_failure) if hard_failure

        @moderator.moderate!(english_text(content))
        classification =
          call_model(record, estimate: content_bytes(content) + 800) do
            @model.classify!(content)
          end
        unless allowed_classification?(classification.data)
          return failure(record, "scope_or_safety_rejected")
        end
        theme = classification.data.fetch("theme")
        return failure(record, "repeated_theme") if repeated_theme?(theme)

        translation =
          call_model(record, estimate: content_bytes(content) + 8_192) do
            @model.translate!(content)
          end
        unless valid_translation?(content, translation.data)
          return failure(record, "invalid_translation")
        end

        @moderator.moderate!(chinese_text(translation.data))
        review =
          call_model(
            record,
            estimate:
              content_bytes(content) + chinese_text(translation.data).bytesize +
                1_500
          ) { @model.review!(content, translation.data) }
        unless passing_review?(content, review.data)
          return failure(record, "quality_review_failed")
        end

        formatted =
          @formatter.call(
            document: document,
            content: content,
            translation: translation.data
          )
        if SiteSetting.licensed_import_dry_run
          record.update!(
            status: "preview",
            theme: theme,
            translated_title: formatted.fetch(:title),
            translated_body: formatted.fetch(:raw)
          )
          Outcome.new(status: "preview", record: record)
        else
          post =
            @publisher.publish!(
              title: formatted.fetch(:title),
              raw: formatted.fetch(:raw),
              tags: [translate("tags.curated"), translate("tags.safety")],
              source_question_id: document.fetch(:question_id)
            )
          record.update!(
            status: "published",
            theme: theme,
            translated_title: formatted.fetch(:title),
            translated_body: formatted.fetch(:raw),
            topic_id: post.topic_id,
            first_post_id: post.id,
            published_at: Time.zone.now
          )
          Outcome.new(status: "published", record: record)
        end
      rescue AiGateway::MissingApiKey
        failure(record, "missing_api_key")
      rescue AiGateway::Rejected => error
        record.add_tokens!(error.token_count)
        failure(record, "model_or_moderation_rejected")
      rescue AiGateway::Error => error
        record.add_tokens!(error.token_count)
        failure(record, "ai_error")
      rescue TokenBudget::Exhausted
        failure(record, "monthly_token_budget_exhausted")
      rescue KeyError, ArgumentError
        failure(record, "invalid_model_output")
      end

      def start_record(document)
        WhereIsMyFriendsLicensedImport.create!(
          source_question_id: document.fetch(:question_id),
          source_answer_id: document[:answer_id],
          source_question_url: document[:question_url],
          source_answer_url: document[:answer_url],
          question_author: document[:question_author],
          answer_author: document[:answer_author],
          question_license: document[:question_license],
          answer_license: document[:answer_license],
          source_revised_at: document[:revised_at],
          scheduled_for_date:
            Time.zone.now.in_time_zone(ScheduleGuard::ZONE).to_date,
          status: "processing"
        )
      end

      def licensed?(document)
        document
          .values_at(:question_license, :answer_license)
          .all? { |license| license.to_s.match?(LICENSE_PATTERN) }
      end

      def imported?(document)
        WhereIsMyFriendsLicensedImport.successful.exists?(
          source_question_id: document.fetch(:question_id)
        )
      end

      def recover_publication(document)
        records =
          WhereIsMyFriendsLicensedImport.where(
            source_question_id: document.fetch(:question_id)
          )
        return if records.successful.exists?

        processing =
          records.where(status: "processing").order(created_at: :desc).first
        topic_id =
          TopicCustomField
            .where(
              name: "where_is_my_friends_licensed_import_source_id",
              value: document.fetch(:question_id).to_s
            )
            .order(id: :desc)
            .pick(:topic_id)
        if topic_id.blank?
          return unless processing
          if processing.updated_at >= PROCESSING_STALE_AFTER.ago
            return skipped("already_claimed")
          end

          processing.fail!("interrupted")
          return
        end

        topic = Topic.find_by(id: topic_id, deleted_at: nil, visible: true)
        return if topic.blank?

        record = processing || start_record(document)
        post = topic.first_post
        record.update!(
          status: "published",
          topic_id: topic.id,
          first_post_id: post&.id,
          translated_title: topic.title,
          translated_body: post&.raw,
          published_at: topic.created_at
        )
        Outcome.new(status: "published", record: record)
      end

      def call_model(record, estimate:)
        @budget.ensure_available!(estimate)
        result = yield
        record.add_tokens!(result.token_count)
        result
      end

      def allowed_classification?(data)
        data["decision"] == "allow" &&
          AiGateway::THEMES.include?(data["theme"]) &&
          data["adult_status"] == "clear" &&
          data["consent_status"] == "clear" && data["prohibited_reasons"] == []
      end

      def valid_translation?(content, data)
        return false unless data["decision"] == "allow"
        return false unless data["redactions"] == []
        return false if data["translated_title"].to_s.blank?
        return false if data["translated_title"].to_s.length > 180
        return false if data["discussion_prompt"].to_s.blank?

        source_ids = content.segments.map(&:id)
        segments = data["segments"]
        return false unless segments.is_a?(Array)
        return false unless segments.map { |entry| entry["id"] } == source_ids
        if segments.any? { |entry| entry["translation"].to_s.blank? }
          return false
        end

        source_text = content.segments.map(&:text).join("\n")
        translated_text =
          segments.map { |entry| entry["translation"] }.join("\n")
        invariant_tokens(source_text) == invariant_tokens(translated_text)
      end

      def passing_review?(content, data)
        data["verdict"] == "pass" && data["omitted_meaning"] == false &&
          data["added_facts_or_advice"] == false &&
          data["numbers_names_links_consistent"] == true &&
          data["tone_strengthened"] == false &&
          data["high_risk_mistranslation"] == false &&
          data["covered_segment_ids"] == content.segments.map(&:id)
      end

      def invariant_tokens(text)
        {
          numbers: text.to_s.scan(/\b\d+(?:[.,]\d+)*\b/).sort,
          links: text.to_s.scan(%r{https?://[^\s)]+}).sort
        }
      end

      def repeated_theme?(theme)
        WhereIsMyFriendsLicensedImport
          .successful
          .where.not(theme: nil)
          .order(created_at: :desc)
          .limit(1)
          .pick(:theme) == theme
      end

      def english_text(content)
        ([content.title] + content.segments.map(&:text)).join("\n")
      end

      def chinese_text(translation)
        [
          translation["translated_title"],
          *translation.fetch("segments").map { |entry| entry["translation"] },
          translation["discussion_prompt"]
        ].join("\n")
      end

      def content_bytes(content)
        english_text(content).bytesize
      end

      def failure(record, code)
        record.fail!(code)
        Outcome.new(status: "failed", failure_code: code, record: record)
      end

      def skipped(code)
        Outcome.new(status: "skipped", failure_code: code)
      end

      def translate(key)
        I18n.t("where_is_my_friends.licensed_import.#{key}", locale: :zh_CN)
      end
    end
  end
end

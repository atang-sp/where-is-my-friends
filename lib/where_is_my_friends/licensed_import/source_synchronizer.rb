# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class SourceSynchronizer
      MAX_PER_RUN = 50

      def initialize(source: StackExchangeClient.new, publisher: Publisher.new)
        @source = source
        @publisher = publisher
      end

      def call
        WhereIsMyFriendsLicensedImport
          .published
          .where.not(topic_id: nil)
          .order(updated_at: :asc, published_at: :asc)
          .limit(MAX_PER_RUN)
          .each { |record| synchronize(record) }
      end

      private

      def synchronize(record)
        document = @source.fetch(record.source_question_id)
        unless changed?(record, document)
          record.touch
          return
        end

        hide(record, "source_changed")
      rescue StackExchangeClient::MissingSource
        hide(record, "source_removed")
      rescue StackExchangeClient::SourceError
        # A transient source failure does not prove the published attribution
        # is stale. Keep it visible and move it behind unchecked sources.
        record.touch
      end

      def changed?(record, document)
        if document[:answer_id].present? &&
             document[:answer_id].to_i != record.source_answer_id.to_i
          return true
        end
        {
          question_author: :question_author,
          answer_author: :answer_author,
          question_license: :question_license,
          answer_license: :answer_license,
          source_question_url: :question_url,
          source_answer_url: :answer_url
        }.each do |record_field, document_field|
          value = document[document_field]
          return true if record.public_send(record_field) != value
        end

        revised_at = document[:revised_at]
        revised_at.present? &&
          (
            record.source_revised_at.blank? ||
              revised_at.to_i > record.source_revised_at.to_i
          )
      end

      def hide(record, reason)
        @publisher.hide!(record)
        record.update!(status: "hidden", failure_code: reason)
      end
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class SourceVerifier
      class Changed < StandardError
      end

      COMPARISONS = {
        source_question_id: :question_id,
        source_answer_id: :answer_id,
        source_question_url: :question_url,
        source_answer_url: :answer_url,
        question_author: :question_author,
        answer_author: :answer_author,
        question_license: :question_license,
        answer_license: :answer_license
      }.freeze

      def initialize(source: SourceCatalog.new)
        @source = source
      end

      def verify!(record)
        document = @source.fetch(record.source_type, record.source_question_id)
        raise Changed unless unchanged?(record, document)

        document
      end

      private

      def unchanged?(record, document)
        return false if document[:source_type].to_s != record.source_type

        COMPARISONS.all? do |record_field, document_field|
          equivalent?(
            record.public_send(record_field),
            document[document_field]
          )
        end && equivalent_time?(record.source_revised_at, document[:revised_at])
      end

      def equivalent?(stored, current)
        if stored.is_a?(Integer)
          current.present? && stored == current.to_i
        else
          stored == current
        end
      end

      def equivalent_time?(stored, current)
        return true if stored.blank? && current.blank?
        return false if stored.blank? || current.blank?

        stored.to_i == current.to_i
      end
    end
  end
end

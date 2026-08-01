# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class SourceCatalog
      def initialize(sources: [WikimediaClient.new, StackExchangeClient.new])
        @sources = sources
      end

      def candidates
        documents = []
        failures = 0
        @sources.each do |source|
          documents.concat(source.candidates)
        rescue SourceError
          failures += 1
        end
        raise SourceError if documents.empty? && failures.positive?

        documents
      end

      def fetch(source_type, source_id)
        source =
          @sources.find { |candidate| candidate.source_type == source_type }
        raise MissingSource if source.blank?

        source.fetch(source_id)
      end
    end
  end
end

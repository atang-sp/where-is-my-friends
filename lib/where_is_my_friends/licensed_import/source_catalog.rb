# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class SourceCatalog
      def self.candidate_capacity
        SpankingArtClient::PAGES.length
      end

      def initialize(candidate_sources: nil, verification_sources: nil)
        spanking_art = SpankingArtClient.new
        @candidate_sources = candidate_sources || [spanking_art]
        @verification_sources =
          verification_sources ||
            [spanking_art, WikimediaClient.new, StackExchangeClient.new]
      end

      def candidates
        documents = []
        failures = 0
        @candidate_sources.each do |source|
          documents.concat(source.candidates)
        rescue SourceError
          failures += 1
        end
        raise SourceError if documents.empty? && failures.positive?

        documents
      end

      def fetch(source_type, source_id)
        source =
          @verification_sources.find do |candidate|
            candidate.source_type == source_type
          end
        raise MissingSource if source.blank?

        source.fetch(source_id)
      end
    end
  end
end

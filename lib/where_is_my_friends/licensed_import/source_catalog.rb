# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class SourceCatalog
      CANDIDATE_SOURCE_TYPE = SpankingArtClient::SOURCE_TYPE
      CANDIDATE_SOURCE_IDS =
        SpankingArtClient::PAGES.map { |page| page.fetch(:page_id) }.freeze

      def self.candidate_capacity
        CANDIDATE_SOURCE_IDS.length
      end

      def self.candidate_source_type
        CANDIDATE_SOURCE_TYPE
      end

      def self.candidate_source_ids
        CANDIDATE_SOURCE_IDS
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

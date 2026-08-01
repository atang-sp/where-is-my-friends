# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class SourceSynchronizer
      MAX_PER_RUN = 50

      def initialize(source: SourceCatalog.new, publisher: Publisher.new)
        @source_verifier = SourceVerifier.new(source: source)
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
        @source_verifier.verify!(record)
        record.touch
      rescue MissingSource
        hide(record, "source_removed")
      rescue SourceVerifier::Changed
        hide(record, "source_changed")
      rescue SourceError
        # A transient source failure does not prove the published attribution
        # is stale. Keep it visible and move it behind unchecked sources.
        record.touch
      end

      def hide(record, reason)
        @publisher.hide!(record)
        record.update!(status: "hidden", failure_code: reason)
      end
    end
  end
end

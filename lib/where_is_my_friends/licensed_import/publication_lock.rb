# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class PublicationLock
      VALIDITY = 2.hours

      def self.synchronize(&block)
        site = RailsMultisite::ConnectionManagement.current_db
        DistributedMutex.synchronize(
          "where_is_my_friends_licensed_import_#{site}",
          validity: VALIDITY,
          &block
        )
      end
    end
  end
end

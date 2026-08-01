# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    module AiGateway
      THEMES = %w[boundaries online_safety communication making_friends].freeze

      class Error < StandardError
        attr_reader :token_count

        def initialize(message = nil, token_count: 0)
          @token_count = token_count.to_i
          super(message)
        end
      end

      class MissingApiKey < Error
      end

      class MissingCredentialMasterKey < Error
      end

      class InvalidCredential < Error
      end

      class Rejected < Error
      end

      class InvalidResponse < Error
      end

      Result = Struct.new(:data, :token_count, keyword_init: true)
    end
  end
end

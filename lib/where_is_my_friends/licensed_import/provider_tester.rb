# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class ProviderTester
      Result =
        Struct.new(:success, :error_code, keyword_init: true) do
          def success?
            success
          end
        end

      def initialize(profile:, endpoint_policy: EndpointPolicy.new)
        @profile = profile
        @endpoint_policy = endpoint_policy
      end

      def call
        tested_digest = @profile.configuration_digest
        test_connection!
        mark_passed(tested_digest)
      rescue AiGateway::MissingCredentialMasterKey
        mark_failed("credential_master_key_missing")
      rescue AiGateway::MissingApiKey, AiGateway::InvalidCredential
        mark_failed("credential_unavailable")
      rescue AiGateway::Error
        mark_failed("connection_failed")
      end

      private

      def test_connection!
        if @profile.purpose == "generation"
          ResponsesClient.new(
            profile: @profile,
            endpoint_policy: @endpoint_policy
          ).test_connection!
        elsif @profile.purpose == "moderation"
          OpenAiModerationClient.new(
            profile: @profile,
            endpoint_policy: @endpoint_policy
          ).moderate!("This is a harmless connection test.")
        else
          raise AiGateway::Error
        end
      end

      def mark_passed(tested_digest)
        now = Time.zone.now
        @profile.with_lock do
          if @profile.configuration_digest != tested_digest
            return mark_failed("configuration_changed")
          end

          @profile.update_columns(
            verified_at: now,
            verified_config_digest: tested_digest,
            last_tested_at: now,
            last_test_status: "passed",
            last_test_error_code: nil,
            updated_at: now
          )
        end
        Result.new(success: true)
      end

      def mark_failed(error_code)
        now = Time.zone.now
        @profile.update_columns(
          active: false,
          verified_at: nil,
          verified_config_digest: nil,
          last_tested_at: now,
          last_test_status: "failed",
          last_test_error_code: error_code,
          updated_at: now
        )
        SiteSetting.licensed_import_enabled = false
        Result.new(success: false, error_code: error_code)
      end
    end
  end
end

# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class OpenAiModerationClient
      def initialize(
        profile: WhereIsMyFriendsAiProviderProfile.active_profile!(
          "moderation"
        ),
        endpoint_policy: EndpointPolicy.new,
        open_timeout: 5,
        read_timeout: 60
      )
        @model = profile.model
        @http =
          JsonHttpClient.new(
            base_url: profile.base_url,
            api_key: profile.api_key,
            endpoint_policy: endpoint_policy,
            open_timeout: open_timeout,
            read_timeout: read_timeout
          )
      end

      def moderate!(text)
        payload = @http.post("/moderations", model: @model, input: text.to_s)
        results = payload["results"]
        unless results.is_a?(Array) && results.one?
          raise AiGateway::InvalidResponse
        end
        raise AiGateway::Rejected if results.first["flagged"] != false

        true
      end
    end
  end
end

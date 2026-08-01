# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class OpenAiModerationClient
      API_ROOT = "https://api.openai.com/v1"
      API_KEY_ENV = "WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"

      def initialize(open_timeout: 5, read_timeout: 60)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def moderate!(text)
        payload =
          post_json(
            "/moderations",
            model: "omni-moderation-latest",
            input: text.to_s
          )
        results = payload["results"]
        unless results.is_a?(Array) && results.one?
          raise AiGateway::InvalidResponse
        end
        raise AiGateway::Rejected if results.first["flagged"] != false

        true
      end

      private

      def post_json(path, body)
        uri = URI("#{API_ROOT}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request["User-Agent"] = "where-is-my-friends-licensed-import"
        request.body = body.to_json
        response =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: true,
            open_timeout: @open_timeout,
            read_timeout: @read_timeout
          ) { |http| http.request(request) }
        raise AiGateway::Error unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError,
             Timeout::Error,
             SocketError,
             SystemCallError,
             OpenSSL::SSL::SSLError
        raise AiGateway::Error
      end

      def api_key
        ENV.fetch(API_KEY_ENV).presence || raise(AiGateway::MissingApiKey)
      rescue KeyError
        raise AiGateway::MissingApiKey
      end
    end
  end
end

# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class JsonHttpClient
      USER_AGENT = "where-is-my-friends-licensed-import"

      def initialize(
        base_url:,
        api_key:,
        endpoint_policy: EndpointPolicy.new,
        open_timeout: 5,
        read_timeout: 60
      )
        @base_url = base_url
        @api_key = api_key
        @endpoint_policy = endpoint_policy
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def post(path, body)
        endpoint = @endpoint_policy.resolve!("#{@base_url}#{path}")
        request = Net::HTTP::Post.new(endpoint.uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request["User-Agent"] = USER_AGENT
        request.body = body.to_json

        http = Net::HTTP.new(endpoint.uri.host, endpoint.uri.port)
        http.ipaddr = endpoint.ip_address
        http.use_ssl = true
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        response = http.start { |connection| connection.request(request) }
        raise AiGateway::Error unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError,
             Timeout::Error,
             SocketError,
             SystemCallError,
             OpenSSL::SSL::SSLError,
             EndpointPolicy::UnsafeEndpoint
        raise AiGateway::Error
      end
    end
  end
end

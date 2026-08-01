# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class JsonHttpClient
      USER_AGENT = "where-is-my-friends-licensed-import"
      DEFAULT_MAX_ATTEMPTS = 3
      MAX_RETRY_DELAY = 10.0
      RETRIABLE_HTTP_STATUSES = [408, 429].freeze
      RETRIABLE_NETWORK_ERRORS = [
        Timeout::Error,
        SocketError,
        SystemCallError,
        OpenSSL::SSL::SSLError
      ].freeze

      def initialize(
        base_url:,
        api_key:,
        endpoint_policy: EndpointPolicy.new,
        open_timeout: 5,
        read_timeout: 60,
        max_attempts: DEFAULT_MAX_ATTEMPTS,
        retry_wait: ->(seconds) { Kernel.sleep(seconds) }
      )
        @base_url = base_url
        @api_key = api_key
        @endpoint_policy = endpoint_policy
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @max_attempts = [max_attempts.to_i, 1].max
        @retry_wait = retry_wait
      end

      def post(path, body)
        endpoint = @endpoint_policy.resolve!("#{@base_url}#{path}")
        request = Net::HTTP::Post.new(endpoint.uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request["User-Agent"] = USER_AGENT
        request.body = body.to_json

        attempts = 0
        loop do
          attempts += 1
          response = perform_request(endpoint, request)
          return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

          if retriable_response?(response) && attempts < @max_attempts
            wait_before_retry(attempts, response)
            next
          end

          raise AiGateway::Error
        rescue *RETRIABLE_NETWORK_ERRORS
          raise AiGateway::Error if attempts >= @max_attempts

          wait_before_retry(attempts)
        end
      rescue JSON::ParserError, EndpointPolicy::UnsafeEndpoint
        raise AiGateway::Error
      end

      private

      def perform_request(endpoint, request)
        http = Net::HTTP.new(endpoint.uri.host, endpoint.uri.port)
        http.ipaddr = endpoint.ip_address
        http.use_ssl = true
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        http.start { |connection| connection.request(request) }
      end

      def retriable_response?(response)
        status = response.code.to_i
        RETRIABLE_HTTP_STATUSES.include?(status) || status.between?(500, 599)
      end

      def wait_before_retry(attempts, response = nil)
        retry_after = Float(response&.[]("Retry-After"), exception: false)
        delay =
          retry_after && retry_after >= 0 ? retry_after : 2**(attempts - 1)

        @retry_wait.call([delay.to_f, MAX_RETRY_DELAY].min)
      end
    end
  end
end

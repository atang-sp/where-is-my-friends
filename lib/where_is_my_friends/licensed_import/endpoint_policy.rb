# frozen_string_literal: true

require "ipaddr"
require "socket"
require "uri"

module WhereIsMyFriends
  module LicensedImport
    class EndpointPolicy
      class UnsafeEndpoint < StandardError
      end

      Endpoint = Struct.new(:uri, :ip_address, keyword_init: true)
      NON_PUBLIC_NETWORKS =
        %w[
          0.0.0.0/8
          10.0.0.0/8
          100.64.0.0/10
          127.0.0.0/8
          169.254.0.0/16
          172.16.0.0/12
          192.0.0.0/24
          192.0.2.0/24
          192.88.99.0/24
          192.168.0.0/16
          198.18.0.0/15
          198.51.100.0/24
          203.0.113.0/24
          224.0.0.0/4
          240.0.0.0/4
          ::/128
          ::1/128
          ::ffff:0:0/96
          100::/64
          2001:db8::/32
          fc00::/7
          fe80::/10
          ff00::/8
        ].map { |network| IPAddr.new(network) }.freeze

      def initialize(resolver: nil)
        @resolver = resolver || method(:resolve_addresses)
      end

      def resolve!(url)
        uri = parse!(url)
        addresses = Array(@resolver.call(uri.host)).uniq
        raise UnsafeEndpoint if addresses.empty?

        parsed = addresses.map { |address| IPAddr.new(address) }
        raise UnsafeEndpoint if parsed.any? { |address| non_public?(address) }

        Endpoint.new(uri: uri, ip_address: addresses.first)
      rescue URI::InvalidURIError,
             IPAddr::InvalidAddressError,
             SocketError,
             SystemCallError
        raise UnsafeEndpoint
      end

      def self.safe_url_syntax?(url)
        uri = URI.parse(url.to_s)
        uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? &&
          uri.query.nil? && uri.fragment.nil?
      rescue URI::InvalidURIError
        false
      end

      private

      def parse!(url)
        raise UnsafeEndpoint unless self.class.safe_url_syntax?(url)

        URI.parse(url.to_s)
      end

      def non_public?(address)
        NON_PUBLIC_NETWORKS.any? { |network| network.include?(address) }
      end

      def resolve_addresses(host)
        Addrinfo
          .getaddrinfo(host, nil, nil, :STREAM)
          .filter_map(&:ip_address)
          .uniq
      end
    end
  end
end

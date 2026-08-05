# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module WhereIsMyFriends
  module FlyingChess
    class ClaimToken
      VERSION = 1
      ISSUER = "flying-chess-room-server"
      AUDIENCE = "where-is-my-friends"
      EVENT = "game_completed"
      MODE = "online_party"
      ALGORITHM = "HS256"
      TOKEN_TYPE = "JWT"
      KEY_ID = "flying-chess-v1"
      HEADER = {
        "alg" => ALGORITHM,
        "typ" => TOKEN_TYPE,
        "kid" => KEY_ID
      }.freeze
      MINIMUM_SECRET_BYTES = 32
      MAXIMUM_TOKEN_BYTES = 4096
      MAXIMUM_IDENTIFIER_BYTES = 128
      MAXIMUM_LIFETIME_SECONDS = 8.days.to_i
      CLOCK_SKEW_SECONDS = 5.minutes.to_i

      Claim =
        Data.define(
          :claim_id,
          :game_id,
          :player_id,
          :mode,
          :ruleset_version,
          :completed_at,
          :place,
          :winner,
          :issued_at,
          :expires_at
        ) do
          def completion_attributes
            {
              claim_id:,
              game_id:,
              player_id:,
              mode:,
              ruleset_version:,
              completed_at: Time.zone.at(completed_at),
              place:,
              winner:
            }
          end
        end

      class InvalidClaim < StandardError
      end

      def self.verify(token, secret:, now: Time.current)
        new(token, secret:, now:).verify
      end

      def initialize(token, secret:, now:)
        @token = token.to_s
        @secret = secret.to_s
        @now = now
      end

      def verify
        validate_secret!
        segments = @token.split(".", -1)
        if @token.blank? || @token.bytesize > MAXIMUM_TOKEN_BYTES ||
             segments.length != 3
          invalid!
        end

        header_segment, payload_segment, signature_segment = segments
        unless segments.all? { |segment| segment.match?(/\A[A-Za-z0-9_-]+\z/) }
          invalid!
        end
        verify_signature!(header_segment, payload_segment, signature_segment)

        header = decode_json(header_segment)
        payload = decode_json(payload_segment)
        invalid! unless header == HEADER
        validate_payload!(payload)
        build_claim(payload)
      rescue JSON::ParserError, ArgumentError
        invalid!
      end

      private

      def validate_secret!
        invalid! if @secret.bytesize < MINIMUM_SECRET_BYTES
      end

      def verify_signature!(header, payload, signature)
        expected =
          OpenSSL::HMAC.digest("SHA256", @secret, "#{header}.#{payload}")
        actual = decode_base64url(signature)
        invalid! unless actual.bytesize == expected.bytesize
        unless ActiveSupport::SecurityUtils.secure_compare(actual, expected)
          invalid!
        end
      end

      def decode_json(segment)
        value = JSON.parse(decode_base64url(segment))
        invalid! unless value.is_a?(Hash)
        value
      end

      def decode_base64url(value)
        Base64.urlsafe_decode64(value.ljust((value.length + 3) / 4 * 4, "="))
      end

      def validate_payload!(payload)
        invalid! unless payload["v"] == VERSION
        invalid! unless payload["iss"] == ISSUER
        invalid! unless payload["aud"] == AUDIENCE
        invalid! unless payload["event"] == EVENT
        invalid! unless payload["mode"] == MODE
        %w[jti game_id player_id ruleset_version].each do |key|
          value = payload[key]
          invalid! unless value.is_a?(String) && value.present?
          invalid! if value.bytesize > MAXIMUM_IDENTIFIER_BYTES
        end
        %w[completed_at iat exp place].each do |key|
          invalid! unless payload[key].is_a?(Integer)
        end
        invalid! unless payload["winner"] == true || payload["winner"] == false
        invalid! unless payload["place"].positive?
        invalid! unless payload["completed_at"] == payload["iat"]
        invalid! if payload["exp"] <= payload["iat"]
        invalid! if payload["exp"] - payload["iat"] > MAXIMUM_LIFETIME_SECONDS
        invalid! if @now.to_i >= payload["exp"]
        invalid! if payload["iat"] > @now.to_i + CLOCK_SKEW_SECONDS
      end

      def build_claim(payload)
        Claim.new(
          claim_id: payload.fetch("jti"),
          game_id: payload.fetch("game_id"),
          player_id: payload.fetch("player_id"),
          mode: payload.fetch("mode"),
          ruleset_version: payload.fetch("ruleset_version"),
          completed_at: payload.fetch("completed_at"),
          place: payload.fetch("place"),
          winner: payload.fetch("winner"),
          issued_at: payload.fetch("iat"),
          expires_at: payload.fetch("exp")
        )
      end

      def invalid!
        raise InvalidClaim,
              I18n.t("where_is_my_friends.flying_chess.invalid_claim")
      end
    end
  end
end

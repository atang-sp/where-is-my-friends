# frozen_string_literal: true

module FlyingChessClaimTokenSpecHelpers
  def encode_claim_segment(value)
    Base64.urlsafe_encode64(value, padding: false)
  end

  def build_claim_token(header:, payload:, signing_secret:)
    build_raw_claim_token(
      header_json: JSON.generate(header),
      payload_json: JSON.generate(payload),
      signing_secret:
    )
  end

  def build_raw_claim_token(header_json:, payload_json:, signing_secret:)
    header_segment = encode_claim_segment(header_json)
    payload_segment = encode_claim_segment(payload_json)
    signature =
      OpenSSL::HMAC.digest(
        "SHA256",
        signing_secret,
        "#{header_segment}.#{payload_segment}"
      )

    [header_segment, payload_segment, encode_claim_segment(signature)].join(".")
  end
end

RSpec.describe WhereIsMyFriends::FlyingChess::ClaimToken do
  include FlyingChessClaimTokenSpecHelpers

  describe ".verify" do
    subject(:verified_claim) { described_class.verify(token, secret:, now:) }

    let(:now) { Time.zone.parse("2026-08-05 12:00:00") }
    let(:secret) { "s" * described_class::MINIMUM_SECRET_BYTES }
    let(:signing_secret) { secret }
    let(:header) { described_class::HEADER.dup }
    let(:payload) do
      {
        "v" => described_class::VERSION,
        "iss" => described_class::ISSUER,
        "aud" => described_class::AUDIENCE,
        "event" => described_class::EVENT,
        "jti" => "claim-1",
        "game_id" => "game-1",
        "player_id" => "player-1",
        "mode" => described_class::MODE,
        "ruleset_version" => "party-v1",
        "completed_at" => now.to_i - 1.minute.to_i,
        "iat" => now.to_i - 1.minute.to_i,
        "exp" => now.to_i + 1.hour.to_i,
        "place" => 1,
        "winner" => true
      }
    end
    let(:token) { build_claim_token(header:, payload:, signing_secret:) }

    shared_examples "an invalid claim" do
      it do
        expect { verified_claim }.to raise_error(
          described_class::InvalidClaim,
          I18n.t("where_is_my_friends.flying_chess.invalid_claim")
        )
      end
    end

    context "with a valid claim" do
      it "returns the verified completion data", :aggregate_failures do
        expect(verified_claim.claim_id).to eq(payload.fetch("jti"))
        expect(verified_claim.game_id).to eq(payload.fetch("game_id"))
        expect(verified_claim.player_id).to eq(payload.fetch("player_id"))
        expect(verified_claim.mode).to eq(payload.fetch("mode"))
        expect(verified_claim.ruleset_version).to eq(
          payload.fetch("ruleset_version")
        )
        expect(verified_claim.completed_at).to eq_time(
          payload.fetch("completed_at")
        )
        expect(verified_claim.place).to eq(payload.fetch("place"))
        expect(verified_claim.winner).to eq(payload.fetch("winner"))
        expect(verified_claim.issued_at).to eq_time(payload.fetch("iat"))
        expect(verified_claim.expires_at).to eq_time(payload.fetch("exp"))
      end
    end

    context "with a non-HS256 algorithm" do
      let(:header) { super().merge("alg" => "none") }

      include_examples "an invalid claim"
    end

    context "with a different token type" do
      let(:header) { super().merge("typ" => "JWS") }

      include_examples "an invalid claim"
    end

    context "with a different key id" do
      let(:header) { super().merge("kid" => "other-key") }

      include_examples "an invalid claim"
    end

    context "with an extra header field" do
      let(:header) { super().merge("extra" => true) }

      include_examples "an invalid claim"
    end

    context "with a signature produced by another secret" do
      let(:signing_secret) { "x" * described_class::MINIMUM_SECRET_BYTES }

      include_examples "an invalid claim"
    end

    context "with a payload changed after signing" do
      let(:token) do
        segments =
          build_claim_token(header:, payload:, signing_secret:).split(".")
        segments[1] = encode_claim_segment(
          JSON.generate(payload.merge("place" => 2))
        )
        segments.join(".")
      end

      include_examples "an invalid claim"
    end

    {
      "v" => 2,
      "iss" => "another-issuer",
      "aud" => "another-audience",
      "event" => "another-event",
      "mode" => "another-mode"
    }.each do |field, value|
      context "with an invalid #{field}" do
        let(:payload) { super().merge(field => value) }

        include_examples "an invalid claim"
      end
    end

    %w[jti game_id player_id ruleset_version].each do |field|
      context "with a blank #{field}" do
        let(:payload) { super().merge(field => "") }

        include_examples "an invalid claim"
      end

      context "with a non-string #{field}" do
        let(:payload) { super().merge(field => 1) }

        include_examples "an invalid claim"
      end

      context "with an oversized #{field}" do
        let(:payload) do
          super().merge(
            field => "x" * (described_class::MAXIMUM_IDENTIFIER_BYTES + 1)
          )
        end

        include_examples "an invalid claim"
      end
    end

    context "with an identifier at the maximum byte length" do
      let(:payload) do
        super().merge("jti" => "x" * described_class::MAXIMUM_IDENTIFIER_BYTES)
      end

      it "accepts the boundary" do
        expect(verified_claim.claim_id.bytesize).to eq(
          described_class::MAXIMUM_IDENTIFIER_BYTES
        )
      end
    end

    %w[completed_at iat exp place].each do |field|
      context "with a non-integer #{field}" do
        let(:payload) do
          parent_payload = super()
          parent_payload.merge(field => parent_payload.fetch(field).to_s)
        end

        include_examples "an invalid claim"
      end
    end

    context "when completion time differs from issued time" do
      let(:payload) do
        super().merge("completed_at" => super().fetch("iat") - 1)
      end

      include_examples "an invalid claim"
    end

    context "when expiration is not after issuance" do
      let(:payload) { super().merge("exp" => super().fetch("iat")) }

      include_examples "an invalid claim"
    end

    context "when token lifetime exceeds the maximum" do
      let(:payload) do
        issued_at = super().fetch("iat")
        super().merge(
          "exp" => issued_at + described_class::MAXIMUM_LIFETIME_SECONDS + 1
        )
      end

      include_examples "an invalid claim"
    end

    context "when token lifetime is at the maximum" do
      let(:payload) do
        issued_at = super().fetch("iat")
        super().merge(
          "exp" => issued_at + described_class::MAXIMUM_LIFETIME_SECONDS
        )
      end

      it "accepts the boundary" do
        expect(verified_claim.expires_at - verified_claim.issued_at).to eq(
          described_class::MAXIMUM_LIFETIME_SECONDS
        )
      end
    end

    context "when the token is expired" do
      let(:payload) { super().merge("exp" => now.to_i) }

      include_examples "an invalid claim"
    end

    context "when issuance exceeds allowed clock skew" do
      let(:payload) do
        issued_at = now.to_i + described_class::CLOCK_SKEW_SECONDS + 1
        super().merge(
          "completed_at" => issued_at,
          "iat" => issued_at,
          "exp" => issued_at + 1.hour.to_i
        )
      end

      include_examples "an invalid claim"
    end

    context "when issuance is at the clock-skew boundary" do
      let(:payload) do
        issued_at = now.to_i + described_class::CLOCK_SKEW_SECONDS
        super().merge(
          "completed_at" => issued_at,
          "iat" => issued_at,
          "exp" => issued_at + 1.hour.to_i
        )
      end

      it "accepts the boundary" do
        expect(verified_claim.issued_at).to eq_time(
          now.to_i + described_class::CLOCK_SKEW_SECONDS
        )
      end
    end

    context "with a non-boolean winner" do
      let(:payload) { super().merge("winner" => "true") }

      include_examples "an invalid claim"
    end

    context "with a non-positive place" do
      let(:payload) { super().merge("place" => 0) }

      include_examples "an invalid claim"
    end

    context "with a blank token" do
      let(:token) { "" }

      include_examples "an invalid claim"
    end

    context "with the wrong number of segments" do
      let(:token) { "header.payload" }

      include_examples "an invalid claim"
    end

    context "with characters outside base64url" do
      let(:token) { "header.pay+load.signature" }

      include_examples "an invalid claim"
    end

    context "with malformed JSON" do
      let(:token) do
        build_raw_claim_token(
          header_json: JSON.generate(header),
          payload_json: "{",
          signing_secret:
        )
      end

      include_examples "an invalid claim"
    end

    context "with a non-object payload" do
      let(:token) do
        build_raw_claim_token(
          header_json: JSON.generate(header),
          payload_json: JSON.generate([]),
          signing_secret:
        )
      end

      include_examples "an invalid claim"
    end

    context "with an oversized token" do
      let(:token) { "a" * (described_class::MAXIMUM_TOKEN_BYTES + 1) + ".a.a" }

      include_examples "an invalid claim"
    end

    context "with a weak verification secret" do
      let(:secret) { "s" * (described_class::MINIMUM_SECRET_BYTES - 1) }
      let(:signing_secret) { "x" * described_class::MINIMUM_SECRET_BYTES }

      include_examples "an invalid claim"
    end
  end
end

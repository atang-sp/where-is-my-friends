# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class OpenAiClient
      class Error < StandardError
      end
      class MissingApiKey < Error
      end
      class Rejected < Error
      end
      class InvalidResponse < Error
      end

      Result = Struct.new(:data, :token_count, keyword_init: true)
      API_ROOT = "https://api.openai.com/v1"
      THEMES = %w[boundaries online_safety communication making_friends].freeze

      CLASSIFICATION_SCHEMA = {
        type: "object",
        additionalProperties: false,
        properties: {
          decision: {
            type: "string",
            enum: %w[allow reject]
          },
          theme: {
            type: "string",
            enum: THEMES + ["none"]
          },
          adult_status: {
            type: "string",
            enum: %w[clear unclear minor]
          },
          consent_status: {
            type: "string",
            enum: %w[clear unclear nonconsensual]
          },
          prohibited_reasons: {
            type: "array",
            items: {
              type: "string"
            }
          }
        },
        required: %w[
          decision
          theme
          adult_status
          consent_status
          prohibited_reasons
        ]
      }.freeze

      TRANSLATION_SCHEMA = {
        type: "object",
        additionalProperties: false,
        properties: {
          decision: {
            type: "string",
            enum: %w[allow reject]
          },
          translated_title: {
            type: "string"
          },
          segments: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                id: {
                  type: "string"
                },
                translation: {
                  type: "string"
                }
              },
              required: %w[id translation]
            }
          },
          discussion_prompt: {
            type: "string"
          },
          redactions: {
            type: "array",
            items: {
              type: "string"
            }
          }
        },
        required: %w[
          decision
          translated_title
          segments
          discussion_prompt
          redactions
        ]
      }.freeze

      REVIEW_SCHEMA = {
        type: "object",
        additionalProperties: false,
        properties: {
          verdict: {
            type: "string",
            enum: %w[pass fail]
          },
          omitted_meaning: {
            type: "boolean"
          },
          added_facts_or_advice: {
            type: "boolean"
          },
          numbers_names_links_consistent: {
            type: "boolean"
          },
          tone_strengthened: {
            type: "boolean"
          },
          high_risk_mistranslation: {
            type: "boolean"
          },
          covered_segment_ids: {
            type: "array",
            items: {
              type: "string"
            }
          }
        },
        required: %w[
          verdict
          omitted_meaning
          added_facts_or_advice
          numbers_names_links_consistent
          tone_strengthened
          high_risk_mistranslation
          covered_segment_ids
        ]
      }.freeze

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
        raise InvalidResponse unless results.is_a?(Array) && results.one?
        raise Rejected if results.first["flagged"] != false

        true
      end

      def classify!(content)
        structured_response(
          name: "licensed_import_classification",
          schema: CLASSIFICATION_SCHEMA,
          max_output_tokens: 800,
          developer: <<~PROMPT,
            Classify this licensed English Q&A for a Chinese community.
            Allow only useful material about boundaries, online dating or
            meeting safety, relationship communication, or making friends.
            Reject if every person is not clearly an adult, consent is unclear,
            or the content includes explicit sexual material, self-harm,
            medical or legal advice, illegal conduct, or personal information.
            Do not translate or add advice.
          PROMPT
          user: source_payload(content)
        )
      end

      def translate!(content)
        structured_response(
          name: "licensed_import_translation",
          schema: TRANSLATION_SCHEMA,
          max_output_tokens: 8_192,
          developer: <<~PROMPT,
            Translate the supplied English title and numbered segments into
            faithful, natural Simplified Chinese. Preserve every segment ID,
            order, number, proper name, and Markdown link exactly. Do not add
            facts, advice, examples, or moral judgments. Return no redactions;
            the program has already removed disallowed material. Keep the
            separate discussion_prompt to one open-ended Chinese question and
            never present it as the source author's words. Reject when a
            faithful safe translation is not possible.
          PROMPT
          user: source_payload(content)
        )
      end

      def review!(content, translation)
        structured_response(
          name: "licensed_import_review",
          schema: REVIEW_SCHEMA,
          max_output_tokens: 1_500,
          developer: <<~PROMPT,
            Independently compare the English source segments with the Chinese
            translation. Fail for any omitted meaning, added fact or advice,
            changed number, proper name or link, materially stronger tone, high
            risk mistranslation, missing segment, extra segment, or reordered
            segment. The discussion prompt is separate and must not be treated
            as source content.
          PROMPT
          user: {
            source: JSON.parse(source_payload(content)),
            translation: translation
          }.to_json
        )
      end

      private

      def structured_response(
        name:,
        schema:,
        max_output_tokens:,
        developer:,
        user:
      )
        payload =
          post_json(
            "/responses",
            model: SiteSetting.licensed_import_model,
            store: false,
            reasoning: {
              effort: "low"
            },
            tools: [],
            max_output_tokens: max_output_tokens,
            input: [
              { role: "developer", content: developer },
              { role: "user", content: user }
            ],
            text: {
              verbosity: "low",
              format: {
                type: "json_schema",
                name: name,
                strict: true,
                schema: schema
              }
            }
          )
        raise InvalidResponse unless payload["status"] == "completed"
        raise Rejected if refusal?(payload)

        text = output_text(payload)
        data = JSON.parse(text)
        raise InvalidResponse unless data.is_a?(Hash)

        Result.new(
          data: data,
          token_count: payload.dig("usage", "total_tokens").to_i
        )
      rescue JSON::ParserError
        raise InvalidResponse
      end

      def source_payload(content)
        {
          title: content.title,
          segments:
            content.segments.map do |segment|
              { id: segment.id, kind: segment.kind, text: segment.text }
            end
        }.to_json
      end

      def refusal?(payload)
        payload
          .fetch("output", [])
          .any? do |item|
            item.fetch("content", []).any? { |part| part["type"] == "refusal" }
          end
      end

      def output_text(payload)
        parts =
          payload
            .fetch("output", [])
            .flat_map do |item|
              item
                .fetch("content", [])
                .filter_map do |part|
                  part["text"] if part["type"] == "output_text"
                end
            end
        raise InvalidResponse unless parts.one? && parts.first.present?

        parts.first
      end

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
        raise Error unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError,
             Timeout::Error,
             SocketError,
             SystemCallError,
             OpenSSL::SSL::SSLError
        raise Error
      end

      def api_key
        ENV.fetch("WHERE_IS_MY_FRIENDS_OPENAI_API_KEY").presence ||
          raise(MissingApiKey)
      rescue KeyError
        raise MissingApiKey
      end
    end
  end
end

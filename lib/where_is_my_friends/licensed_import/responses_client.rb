# frozen_string_literal: true

require "net/http"

module WhereIsMyFriends
  module LicensedImport
    class ResponsesClient
      PROVIDERS = {
        "deepseek-v4-flash" => {
          api_root: "https://api.deepseek.com",
          api_key_env: "WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY"
        },
        "gpt-5.6-terra" => {
          api_root: "https://api.openai.com/v1",
          api_key_env: "WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"
        }
      }.freeze
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
            enum: AiGateway::THEMES + ["none"]
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
        @model = SiteSetting.licensed_import_model
        @provider = PROVIDERS.fetch(@model) { raise AiGateway::Error }
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
        token_count = 0
        payload =
          post_json(
            "/responses",
            model: @model,
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
        token_count = response_token_count(payload)
        unless payload["status"] == "completed"
          raise AiGateway::InvalidResponse.new(token_count: token_count)
        end
        if refusal?(payload)
          raise AiGateway::Rejected.new(token_count: token_count)
        end

        text = output_text(payload, token_count: token_count)
        data = JSON.parse(text)
        unless data.is_a?(Hash)
          raise AiGateway::InvalidResponse.new(token_count: token_count)
        end

        AiGateway::Result.new(data: data, token_count: token_count)
      rescue JSON::ParserError
        raise AiGateway::InvalidResponse.new(token_count: token_count)
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

      def output_text(payload, token_count:)
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
        unless parts.one? && parts.first.present?
          raise AiGateway::InvalidResponse.new(token_count: token_count)
        end

        parts.first
      end

      def response_token_count(payload)
        total = payload.dig("usage", "total_tokens")
        return total.to_i unless total.nil?

        payload.dig("usage", "input_tokens").to_i +
          payload.dig("usage", "output_tokens").to_i
      end

      def post_json(path, body)
        uri = URI("#{@provider.fetch(:api_root)}#{path}")
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
        ENV.fetch(@provider.fetch(:api_key_env)).presence ||
          raise(AiGateway::MissingApiKey)
      rescue KeyError
        raise AiGateway::MissingApiKey
      end
    end
  end
end

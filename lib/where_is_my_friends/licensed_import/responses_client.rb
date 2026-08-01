# frozen_string_literal: true

module WhereIsMyFriends
  module LicensedImport
    class ResponsesClient
      TEST_SCHEMA = {
        type: "object",
        additionalProperties: false,
        properties: {
          ok: {
            type: "boolean"
          }
        },
        required: %w[ok]
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

      def initialize(
        profile: WhereIsMyFriendsAiProviderProfile.active_profile!(
          "generation"
        ),
        endpoint_policy: EndpointPolicy.new,
        open_timeout: 5,
        read_timeout: 60
      )
        @protocol = profile.protocol
        @structured_output_mode = profile.structured_output_mode
        @model = profile.model
        @http =
          JsonHttpClient.new(
            base_url: profile.base_url,
            api_key: profile.api_key!,
            endpoint_policy: endpoint_policy,
            open_timeout: open_timeout,
            read_timeout: read_timeout
          )
      end

      def test_connection!
        result =
          structured_response(
            name: "licensed_import_connection_test",
            schema: TEST_SCHEMA,
            max_output_tokens: 32,
            developer: "Return JSON with ok set to true. Do nothing else.",
            user: "Test this configured model connection."
          )
        raise AiGateway::InvalidResponse unless result.data == { "ok" => true }

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
        token_count = 0
        payload =
          request_structured_response(
            name: name,
            schema: schema,
            max_output_tokens: max_output_tokens,
            developer: developer,
            user: user
          )
        raise AiGateway::InvalidResponse unless payload.is_a?(Hash)

        token_count = response_token_count!(payload)
        text = extract_text!(payload, token_count: token_count)
        data = JSON.parse(text)
        JsonSchemaValidator.validate!(data, schema)

        AiGateway::Result.new(data: data, token_count: token_count)
      rescue JSON::ParserError, AiGateway::InvalidResponse
        raise AiGateway::InvalidResponse.new(token_count: token_count)
      end

      def request_structured_response(
        name:,
        schema:,
        max_output_tokens:,
        developer:,
        user:
      )
        case @protocol
        when "responses"
          @http.post(
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
        when "chat_completions"
          chat_developer = developer
          response_format =
            if @structured_output_mode == "json_object"
              chat_developer = <<~PROMPT
                #{developer}
                Return only one JSON object matching this JSON Schema exactly:
                #{schema.to_json}
              PROMPT
              { type: "json_object" }
            else
              {
                type: "json_schema",
                json_schema: {
                  name: name,
                  strict: true,
                  schema: schema
                }
              }
            end
          @http.post(
            "/chat/completions",
            model: @model,
            max_tokens: max_output_tokens,
            messages: [
              { role: "system", content: chat_developer },
              { role: "user", content: user }
            ],
            response_format: response_format
          )
        else
          raise AiGateway::Error
        end
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

      def responses_refusal?(payload)
        output = payload["output"]
        raise AiGateway::InvalidResponse unless output.is_a?(Array)

        output.any? do |item|
          raise AiGateway::InvalidResponse unless item.is_a?(Hash)

          next false if item["type"] == "reasoning"
          raise AiGateway::InvalidResponse unless item["type"] == "message"

          content = item["content"]
          raise AiGateway::InvalidResponse unless content.is_a?(Array)

          content.any? do |part|
            raise AiGateway::InvalidResponse unless part.is_a?(Hash)

            part["type"] == "refusal"
          end
        end
      end

      def responses_output_text(payload, token_count:)
        output = payload["output"]
        raise AiGateway::InvalidResponse unless output.is_a?(Array)

        parts =
          output.flat_map do |item|
            raise AiGateway::InvalidResponse unless item.is_a?(Hash)

            next [] if item["type"] == "reasoning"
            raise AiGateway::InvalidResponse unless item["type"] == "message"

            content = item["content"]
            raise AiGateway::InvalidResponse unless content.is_a?(Array)

            content.filter_map do |part|
              raise AiGateway::InvalidResponse unless part.is_a?(Hash)

              part["text"] if part["type"] == "output_text"
            end
          end
        unless parts.one? && parts.first.present?
          raise AiGateway::InvalidResponse.new(token_count: token_count)
        end

        parts.first
      end

      def response_token_count!(payload)
        total = payload.dig("usage", "total_tokens")
        return total.to_i if total.is_a?(Numeric)

        input = payload.dig("usage", "input_tokens")
        output = payload.dig("usage", "output_tokens")
        if input.is_a?(Numeric) && output.is_a?(Numeric)
          return input.to_i + output.to_i
        end

        prompt = payload.dig("usage", "prompt_tokens")
        completion = payload.dig("usage", "completion_tokens")
        if prompt.is_a?(Numeric) && completion.is_a?(Numeric)
          return prompt.to_i + completion.to_i
        end

        raise AiGateway::InvalidResponse
      end

      def extract_text!(payload, token_count:)
        if @protocol == "responses"
          unless payload["status"] == "completed"
            raise AiGateway::InvalidResponse.new(token_count: token_count)
          end
          if responses_refusal?(payload)
            raise AiGateway::Rejected.new(token_count: token_count)
          end

          responses_output_text(payload, token_count: token_count)
        else
          choices = payload["choices"]
          unless choices.is_a?(Array) && choices.one? &&
                   choices.first.is_a?(Hash)
            raise AiGateway::InvalidResponse.new(token_count: token_count)
          end
          choice = choices.first
          if choice["finish_reason"] != "stop"
            raise AiGateway::InvalidResponse.new(token_count: token_count)
          end
          message = choice["message"]
          unless message.is_a?(Hash)
            raise AiGateway::InvalidResponse.new(token_count: token_count)
          end
          if message["refusal"].present?
            raise AiGateway::Rejected.new(token_count: token_count)
          end

          text = message["content"]
          unless text.is_a?(String) && text.present?
            raise AiGateway::InvalidResponse.new(token_count: token_count)
          end

          text
        end
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::ResponsesClient do
  fab!(:admin)

  around do |example|
    original =
      ENV[WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV]
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = Base64.strict_encode64("g" * 32)
    example.run
  ensure
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = original
  end

  let(:endpoint_policy) do
    WhereIsMyFriends::LicensedImport::EndpointPolicy.new(
      resolver: ->(_host) { ["1.1.1.1"] }
    )
  end

  let(:content) do
    WhereIsMyFriends::LicensedImport::ContentProcessor::ProcessedContent.new(
      title: "A boundary question",
      segments: [
        WhereIsMyFriends::LicensedImport::ContentProcessor::Segment.new(
          id: "question_01",
          kind: "question",
          text: "I am 25 and want to set one boundary."
        ),
        WhereIsMyFriends::LicensedImport::ContentProcessor::Segment.new(
          id: "answer_01",
          kind: "answer",
          text: "State the boundary clearly."
        )
      ],
      redactions: [],
      word_count: 400
    )
  end

  let(:translation) do
    {
      decision: "allow",
      translated_title: "如何设定边界",
      segments: [
        { id: "question_01", translation: "我今年 25 岁，想设定一个边界。" },
        { id: "answer_01", translation: "清楚说明这个边界。" }
      ],
      discussion_prompt: "你会如何清楚表达自己的边界？",
      redactions: []
    }
  end

  def profile(
    protocol:,
    base_url: "https://gateway.example/v1",
    structured_output_mode: "json_schema"
  )
    WhereIsMyFriendsAiProviderProfile.create!(
      name: "Generation gateway",
      purpose: "generation",
      protocol: protocol,
      structured_output_mode: structured_output_mode,
      base_url: base_url,
      model: "supplier-model",
      api_key: "supplier-secret",
      created_by_id: admin.id,
      updated_by_id: admin.id
    )
  end

  it "uses a profile snapshot with the Responses API and strict schema" do
    configured = profile(protocol: "responses")
    stub_request(:post, "https://gateway.example/v1/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: translation.to_json }]
          }
        ],
        usage: {
          input_tokens: 100,
          output_tokens: 23
        }
      }.to_json
    )

    client =
      described_class.new(profile: configured, endpoint_policy: endpoint_policy)
    configured.update_columns(
      base_url: "https://replacement.invalid/v1",
      model: "replacement-model"
    )
    result = client.translate!(content)

    expect(result.data).to eq(translation.deep_stringify_keys)
    expect(result.token_count).to eq(123)
    expect(
      a_request(:post, "https://gateway.example/v1/responses").with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer supplier-secret" &&
          body["model"] == "supplier-model" && body["store"] == false &&
          body.dig("reasoning", "effort") == "low" && body["tools"] == [] &&
          body.dig("text", "format", "type") == "json_schema" &&
          body.dig("text", "format", "strict") == true
      end
    ).to have_been_made.once
  end

  it "supports OpenAI-compatible Chat Completions with strict schema" do
    configured = profile(protocol: "chat_completions")
    stub_request(
      :post,
      "https://gateway.example/v1/chat/completions"
    ).to_return(
      status: 200,
      body: {
        choices: [
          {
            finish_reason: "stop",
            message: {
              role: "assistant",
              content: translation.to_json
            }
          }
        ],
        usage: {
          prompt_tokens: 80,
          completion_tokens: 20
        }
      }.to_json
    )

    result =
      described_class.new(
        profile: configured,
        endpoint_policy: endpoint_policy
      ).translate!(content)

    expect(result.data).to eq(translation.deep_stringify_keys)
    expect(result.token_count).to eq(100)
    expect(
      a_request(
        :post,
        "https://gateway.example/v1/chat/completions"
      ).with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer supplier-secret" &&
          body["model"] == "supplier-model" &&
          body.dig("messages", 0, "role") == "system" &&
          body.dig("response_format", "type") == "json_schema" &&
          body.dig("response_format", "json_schema", "strict") == true
      end
    ).to have_been_made.once
  end

  it "supports JSON object mode with the same strict local validation" do
    configured =
      profile(
        protocol: "chat_completions",
        structured_output_mode: "json_object"
      )
    stub_request(
      :post,
      "https://gateway.example/v1/chat/completions"
    ).to_return(
      status: 200,
      body: {
        choices: [
          {
            finish_reason: "stop",
            message: {
              role: "assistant",
              content: { ok: true }.to_json
            }
          }
        ],
        usage: {
          prompt_tokens: 10,
          completion_tokens: 2
        }
      }.to_json
    )

    expect(
      described_class.new(
        profile: configured,
        endpoint_policy: endpoint_policy
      ).test_connection!
    ).to eq(true)
    expect(
      a_request(
        :post,
        "https://gateway.example/v1/chat/completions"
      ).with do |request|
        body = JSON.parse(request.body)
        body.dig("response_format", "type") == "json_object" &&
          body.dig("messages", 0, "content").include?("JSON Schema") &&
          body["max_tokens"] == 32
      end
    ).to have_been_made.once
  end

  it "fails closed when output violates the local schema" do
    configured = profile(protocol: "responses")
    stub_request(:post, "https://gateway.example/v1/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [
              {
                type: "output_text",
                text: translation.merge(unexpected: "addition").to_json
              }
            ]
          }
        ],
        usage: {
          total_tokens: 10
        }
      }.to_json
    )

    expect {
      described_class.new(
        profile: configured,
        endpoint_policy: endpoint_policy
      ).translate!(content)
    }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::InvalidResponse
    ) { |error| expect(error.token_count).to eq(10) }
  end

  it "does not read legacy provider key environment variables" do
    configured = profile(protocol: "responses")
    configured.update_columns(encrypted_api_key: "")
    ENV["WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY"] = "legacy-key"
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = "legacy-key"

    expect {
      described_class.new(profile: configured, endpoint_policy: endpoint_policy)
    }.to raise_error(WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey)
  ensure
    ENV.delete("WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY")
    ENV.delete("WHERE_IS_MY_FRIENDS_OPENAI_API_KEY")
  end

  it "fails closed on timeout, refusal, malformed JSON, and missing usage" do
    configured = profile(protocol: "responses")
    client =
      described_class.new(profile: configured, endpoint_policy: endpoint_policy)

    stub_request(:post, "https://gateway.example/v1/responses").to_timeout
    expect { client.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::Error
    )

    stub_request(:post, "https://gateway.example/v1/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "refusal", refusal: "Cannot comply" }]
          }
        ],
        usage: {
          total_tokens: 10
        }
      }.to_json
    )
    expect { client.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::Rejected
    )

    stub_request(:post, "https://gateway.example/v1/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: "not json" }]
          }
        ],
        usage: {
          total_tokens: 10
        }
      }.to_json
    )
    expect { client.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::InvalidResponse
    )

    stub_request(:post, "https://gateway.example/v1/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: translation.to_json }]
          }
        ]
      }.to_json
    )
    expect { client.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::InvalidResponse
    )
  end
end

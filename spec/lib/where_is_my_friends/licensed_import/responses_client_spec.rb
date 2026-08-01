# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::ResponsesClient do
  around do |example|
    original_deepseek = ENV["WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY"]
    original_openai = ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"]
    original_model = SiteSetting.licensed_import_model
    ENV["WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY"] = "deepseek-test-key"
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = "openai-test-key"
    SiteSetting.licensed_import_model = "deepseek-v4-flash"
    example.run
  ensure
    ENV["WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY"] = original_deepseek
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = original_openai
    SiteSetting.licensed_import_model = original_model
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

  it "uses the official DeepSeek Responses endpoint by default" do
    output = {
      decision: "allow",
      translated_title: "如何设定边界",
      segments: [
        { id: "question_01", translation: "我今年 25 岁，想设定一个边界。" },
        { id: "answer_01", translation: "清楚说明这个边界。" }
      ],
      discussion_prompt: "你会如何清楚表达自己的边界？",
      redactions: []
    }
    stub_request(:post, "https://api.deepseek.com/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: output.to_json }]
          }
        ],
        usage: {
          input_tokens: 100,
          output_tokens: 23
        }
      }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    result = described_class.new.translate!(content)

    expect(result.data).to eq(output.deep_stringify_keys)
    expect(result.token_count).to eq(123)
    expect(
      a_request(:post, "https://api.deepseek.com/responses").with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer deepseek-test-key" &&
          body["model"] == "deepseek-v4-flash" && body["store"] == false &&
          body.dig("reasoning", "effort") == "low" && body["tools"] == [] &&
          body.dig("text", "format", "type") == "json_schema" &&
          body.dig("text", "format", "strict") == true
      end
    ).to have_been_made.once
  end

  it "can switch generation back to OpenAI from the model setting" do
    SiteSetting.licensed_import_model = "gpt-5.6-terra"
    output = {
      decision: "allow",
      translated_title: "如何设定边界",
      segments: [
        { id: "question_01", translation: "我今年 25 岁，想设定一个边界。" },
        { id: "answer_01", translation: "清楚说明这个边界。" }
      ],
      discussion_prompt: "你会如何清楚表达自己的边界？",
      redactions: []
    }
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: output.to_json }]
          }
        ],
        usage: {
          total_tokens: 45
        }
      }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    result = described_class.new.translate!(content)

    expect(result.token_count).to eq(45)
    expect(
      a_request(:post, "https://api.openai.com/v1/responses").with do |request|
        request.headers["Authorization"] == "Bearer openai-test-key"
      end
    ).to have_been_made.once
    expect(
      a_request(:post, %r{\Ahttps://api\.deepseek\.com/})
    ).not_to have_been_made
  end

  it "keeps one provider for the lifetime of a pipeline client" do
    client = described_class.new
    SiteSetting.licensed_import_model = "gpt-5.6-terra"
    output = {
      decision: "allow",
      translated_title: "如何设定边界",
      segments: [
        { id: "question_01", translation: "我今年 25 岁，想设定一个边界。" },
        { id: "answer_01", translation: "清楚说明这个边界。" }
      ],
      discussion_prompt: "你会如何清楚表达自己的边界？",
      redactions: []
    }
    stub_request(:post, "https://api.deepseek.com/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: output.to_json }]
          }
        ],
        usage: {
          input_tokens: 40,
          output_tokens: 5
        }
      }.to_json
    )

    expect(client.translate!(content).token_count).to eq(45)
    expect(
      a_request(:post, "https://api.deepseek.com/responses")
    ).to have_been_made.once
    expect(
      a_request(:post, "https://api.openai.com/v1/responses")
    ).not_to have_been_made
  end

  it "fails closed on an API timeout" do
    stub_request(:post, "https://api.deepseek.com/responses").to_timeout

    expect { described_class.new.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::Error
    )
  end

  it "fails closed when the model refuses structured output" do
    stub_request(:post, "https://api.deepseek.com/responses").to_return(
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
          input_tokens: 8,
          output_tokens: 2
        }
      }.to_json
    )

    expect { described_class.new.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::Rejected
    ) { |error| expect(error.token_count).to eq(10) }
  end

  it "fails closed on non-JSON model output" do
    stub_request(:post, "https://api.deepseek.com/responses").to_return(
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
          input_tokens: 8,
          output_tokens: 2
        }
      }.to_json
    )

    expect { described_class.new.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::InvalidResponse
    ) { |error| expect(error.token_count).to eq(10) }
  end

  it "fails closed when the selected provider key is missing" do
    ENV.delete("WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY")

    expect { described_class.new.translate!(content) }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey
    )
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::OpenAiClient do
  around do |example|
    original = ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"]
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = "test-key"
    example.run
  ensure
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = original
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

  it "uses non-persistent tool-free strict structured output for translation" do
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
          total_tokens: 123
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
      a_request(:post, "https://api.openai.com/v1/responses").with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer test-key" &&
          body["model"] == "gpt-5.6-terra" && body["store"] == false &&
          body.dig("reasoning", "effort") == "low" && body["tools"] == [] &&
          body.dig("text", "format", "type") == "json_schema" &&
          body.dig("text", "format", "strict") == true
      end
    ).to have_been_made.once
  end

  it "fails closed on an API timeout" do
    stub_request(:post, "https://api.openai.com/v1/responses").to_timeout

    expect { described_class.new.translate!(content) }.to raise_error(
      described_class::Error
    )
  end

  it "fails closed when the model refuses structured output" do
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(
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

    expect { described_class.new.translate!(content) }.to raise_error(
      described_class::Rejected
    )
  end

  it "fails closed on non-JSON model output" do
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(
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

    expect { described_class.new.translate!(content) }.to raise_error(
      described_class::InvalidResponse
    ) { |error| expect(error.token_count).to eq(10) }
  end

  it "fails closed when moderation flags content" do
    stub_request(:post, "https://api.openai.com/v1/moderations").to_return(
      status: 200,
      body: { results: [{ flagged: true }] }.to_json
    )

    expect { described_class.new.moderate!("unsafe") }.to raise_error(
      described_class::Rejected
    )
  end
end

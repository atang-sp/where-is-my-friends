# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::OpenAiModerationClient do
  around do |example|
    original = ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"]
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = "openai-test-key"
    example.run
  ensure
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = original
  end

  it "uses OpenAI moderation independently of the generation provider" do
    stub_request(:post, "https://api.openai.com/v1/moderations").to_return(
      status: 200,
      body: { results: [{ flagged: false }] }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    expect(described_class.new.moderate!("safe text")).to eq(true)
    expect(
      a_request(
        :post,
        "https://api.openai.com/v1/moderations"
      ).with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer openai-test-key" &&
          body ==
            { "model" => "omni-moderation-latest", "input" => "safe text" }
      end
    ).to have_been_made.once
    expect(
      a_request(:post, %r{\Ahttps://api\.deepseek\.com/})
    ).not_to have_been_made
  end

  it "fails closed when OpenAI flags content" do
    stub_request(:post, "https://api.openai.com/v1/moderations").to_return(
      status: 200,
      body: { results: [{ flagged: true }] }.to_json
    )

    expect { described_class.new.moderate!("unsafe") }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::Rejected
    )
  end

  it "fails closed when the OpenAI moderation key is missing" do
    ENV.delete("WHERE_IS_MY_FRIENDS_OPENAI_API_KEY")

    expect { described_class.new.moderate!("safe text") }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey
    )
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::OpenAiModerationClient do
  fab!(:admin)

  around do |example|
    original =
      ENV[WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV]
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = Base64.strict_encode64("s" * 32)
    example.run
  ensure
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = original
  end

  let(:profile) do
    WhereIsMyFriendsAiProviderProfile.create!(
      name: "OpenAI safety",
      purpose: "moderation",
      protocol: "ignored-by-normalization",
      base_url: "https://ignored.invalid",
      model: "ignored-model",
      api_key: "moderation-secret",
      created_by_id: admin.id,
      updated_by_id: admin.id
    )
  end

  let(:endpoint_policy) do
    WhereIsMyFriends::LicensedImport::EndpointPolicy.new(
      resolver: ->(_host) { ["1.1.1.1"] }
    )
  end

  it "uses the separately encrypted official OpenAI moderation profile" do
    stub_request(:post, "https://api.openai.com/v1/moderations").to_return(
      status: 200,
      body: { results: [{ flagged: false }] }.to_json
    )

    expect(
      described_class.new(
        profile: profile,
        endpoint_policy: endpoint_policy
      ).moderate!("safe text")
    ).to eq(true)
    expect(profile.protocol).to eq("openai_moderation")
    expect(profile.model).to eq("omni-moderation-latest")
    expect(
      a_request(
        :post,
        "https://api.openai.com/v1/moderations"
      ).with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer moderation-secret" &&
          body ==
            { "model" => "omni-moderation-latest", "input" => "safe text" }
      end
    ).to have_been_made.once
  end

  it "fails closed when OpenAI flags content" do
    stub_request(:post, "https://api.openai.com/v1/moderations").to_return(
      status: 200,
      body: { results: [{ flagged: true }] }.to_json
    )

    expect {
      described_class.new(
        profile: profile,
        endpoint_policy: endpoint_policy
      ).moderate!("unsafe")
    }.to raise_error(WhereIsMyFriends::LicensedImport::AiGateway::Rejected)
  end

  it "does not fall back to the legacy OpenAI key environment variable" do
    profile.update_columns(encrypted_api_key: "")
    ENV["WHERE_IS_MY_FRIENDS_OPENAI_API_KEY"] = "legacy-key"

    expect {
      described_class.new(profile: profile, endpoint_policy: endpoint_policy)
    }.to raise_error(WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey)
  ensure
    ENV.delete("WHERE_IS_MY_FRIENDS_OPENAI_API_KEY")
  end
end

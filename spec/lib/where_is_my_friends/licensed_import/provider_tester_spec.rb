# frozen_string_literal: true
RSpec.describe WhereIsMyFriends::LicensedImport::ProviderTester do
  fab!(:admin)

  let(:endpoint_policy) do
    WhereIsMyFriends::LicensedImport::EndpointPolicy.new(
      resolver: ->(_host) { ["1.1.1.1"] }
    )
  end

  def create_profile(purpose:, protocol:, base_url:, model:)
    WhereIsMyFriendsAiProviderProfile.create!(
      name: "Provider under test",
      purpose: purpose,
      protocol: protocol,
      base_url: base_url,
      model: model,
      api_key: "provider-key",
      created_by_id: admin.id,
      updated_by_id: admin.id
    )
  end

  it "verifies the exact current Responses configuration before activation" do
    profile =
      create_profile(
        purpose: "generation",
        protocol: "responses",
        base_url: "https://gateway.example/v1",
        model: "supplier-model"
      )
    stub_request(:post, "https://gateway.example/v1/responses").to_return(
      status: 200,
      body: {
        status: "completed",
        output: [
          {
            type: "message",
            content: [{ type: "output_text", text: { ok: true }.to_json }]
          }
        ],
        usage: {
          total_tokens: 4
        }
      }.to_json
    )

    result =
      described_class.new(
        profile: profile,
        endpoint_policy: endpoint_policy
      ).call

    expect(result).to be_success
    expect(profile.reload.last_test_status).to eq("passed")
    expect(profile).to be_verified_for_current_configuration
    profile.activate!
    expect(profile).to be_active
  end

  it "refuses activation after any tested configuration changes" do
    profile =
      create_profile(
        purpose: "generation",
        protocol: "chat_completions",
        base_url: "https://gateway.example/v1",
        model: "supplier-model"
      )
    profile.update_columns(
      verified_at: Time.zone.now,
      verified_config_digest: profile.configuration_digest,
      last_test_status: "passed"
    )

    profile.update!(model: "new-model", updated_by_id: admin.id)

    expect { profile.activate! }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::InvalidResponse
    )
  end
end

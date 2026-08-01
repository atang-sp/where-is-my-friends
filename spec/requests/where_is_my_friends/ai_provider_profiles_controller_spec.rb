# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::AiProviderProfilesController do
  fab!(:user)
  fab!(:admin)

  around do |example|
    original =
      ENV[WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV]
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = Base64.strict_encode64("a" * 32)
    example.run
  ensure
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = original
  end

  def create_profile
    WhereIsMyFriendsAiProviderProfile.create!(
      name: "Gateway",
      purpose: "generation",
      protocol: "responses",
      base_url: "https://api.openai.com/v1",
      model: "supplier-model",
      api_key: "never-return-this",
      created_by_id: admin.id,
      updated_by_id: admin.id
    )
  end

  it "allows only administrators and never serializes credentials" do
    profile = create_profile

    sign_in(user)
    get "/where-is-my-friends/admin/ai-provider-profiles.json"
    expect(response.status).to eq(404).or eq(403)

    sign_in(admin)
    get "/where-is-my-friends/admin/ai-provider-profiles.json"

    expect(response.status).to eq(200)
    serialized = response.parsed_body.fetch("profiles").sole
    expect(serialized).to include(
      "id" => profile.id,
      "name" => "Gateway",
      "api_key_configured" => true,
      "active" => false
    )
    expect(serialized.keys).not_to include("api_key", "encrypted_api_key")
    expect(response.body).not_to include("never-return-this")
  end

  it "creates and updates profiles while blank keys retain the secret" do
    sign_in(admin)
    post "/where-is-my-friends/admin/ai-provider-profiles.json",
         params: {
           profile: {
             name: "Compatible supplier",
             purpose: "generation",
             protocol: "chat_completions",
             base_url: "https://api.openai.com/v1/",
             model: "vendor-model",
             api_key: "initial-secret"
           }
         }

    expect(response.status).to eq(201)
    profile = WhereIsMyFriendsAiProviderProfile.find(response.parsed_body["id"])
    ciphertext = profile.encrypted_api_key
    expect(profile.api_key).to eq("initial-secret")

    put "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}.json",
        params: {
          profile: {
            name: "Renamed supplier",
            purpose: "generation",
            protocol: "chat_completions",
            base_url: "https://api.openai.com/v1",
            model: "vendor-model",
            api_key: ""
          }
        }

    expect(response.status).to eq(200)
    expect(profile.reload.name).to eq("Renamed supplier")
    expect(profile.encrypted_api_key).to eq(ciphertext)
  end

  it "tests and activates only the verified current configuration" do
    profile = create_profile
    sign_in(admin)
    result =
      WhereIsMyFriends::LicensedImport::ProviderTester::Result.new(
        success: true,
        error_code: nil
      )
    tester =
      instance_double(
        WhereIsMyFriends::LicensedImport::ProviderTester,
        call: result
      )
    allow(WhereIsMyFriends::LicensedImport::ProviderTester).to receive(
      :new
    ).and_return(tester)

    post "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}/test.json"

    expect(response.status).to eq(200)

    profile.update_columns(
      verified_at: Time.zone.now,
      verified_config_digest: profile.configuration_digest,
      last_test_status: "passed"
    )
    post "/where-is-my-friends/admin/ai-provider-profiles/#{profile.id}/activate.json"

    expect(response.status).to eq(200)
    expect(profile.reload).to be_active
    expect(SiteSetting.licensed_import_enabled).to eq(false)
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriendsAiProviderProfile do
  fab!(:admin)

  around do |example|
    original =
      ENV[WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV]
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = Base64.strict_encode64("m" * 32)
    example.run
  ensure
    ENV[
      WhereIsMyFriends::LicensedImport::CredentialCipher::MASTER_KEY_ENV
    ] = original
  end

  def build_profile
    described_class.new(
      name: "Primary supplier",
      purpose: "generation",
      protocol: "responses",
      base_url: "https://gateway.example/v1/",
      model: "vendor-model",
      api_key: "secret-key",
      created_by_id: admin.id,
      updated_by_id: admin.id
    )
  end

  it "normalizes configuration and stores only encrypted credentials" do
    profile = build_profile
    profile.save!

    expect(profile.base_url).to eq("https://gateway.example/v1")
    expect(profile.encrypted_api_key).not_to include("secret-key")
    expect(profile.api_key).to eq("secret-key")
  end

  it "invalidates verification, deactivates, and disables imports on config change" do
    profile = build_profile
    profile.save!
    profile.update_columns(
      active: true,
      verified_at: Time.zone.now,
      verified_config_digest: profile.configuration_digest
    )
    SiteSetting.licensed_import_enabled = true

    profile.update!(model: "replacement-model", updated_by_id: admin.id)

    expect(profile).not_to be_active
    expect(profile.verified_at).to be_nil
    expect(profile.verified_config_digest).to be_nil
    expect(SiteSetting.licensed_import_enabled).to eq(false)
  end

  it "retains the encrypted key when an update omits a new plaintext key" do
    profile = build_profile
    profile.save!
    ciphertext = profile.encrypted_api_key

    profile.update!(name: "Renamed", updated_by_id: admin.id)

    expect(profile.encrypted_api_key).to eq(ciphertext)
    expect(profile.api_key).to eq("secret-key")
  end

  it "allows only one active profile for each purpose" do
    first = build_profile
    first.save!
    second = build_profile
    second.name = "Backup supplier"
    second.save!
    [first, second].each do |profile|
      profile.update_columns(
        verified_at: Time.zone.now,
        verified_config_digest: profile.configuration_digest
      )
    end

    first.activate!
    second.activate!

    expect(first.reload).not_to be_active
    expect(second.reload).to be_active
  end
end

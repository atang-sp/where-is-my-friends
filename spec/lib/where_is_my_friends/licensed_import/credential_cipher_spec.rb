# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::CredentialCipher do
  around do |example|
    original = ENV[described_class::MASTER_KEY_ENV]
    ENV[described_class::MASTER_KEY_ENV] = Base64.strict_encode64("k" * 32)
    example.run
  ensure
    ENV[described_class::MASTER_KEY_ENV] = original
  end

  it "encrypts credentials with authenticated encryption" do
    ciphertext = described_class.encrypt("supplier-secret")

    expect(ciphertext).to start_with("v1:")
    expect(ciphertext).not_to include("supplier-secret")
    expect(described_class.decrypt(ciphertext)).to eq("supplier-secret")
  end

  it "fails closed without a valid stable master key" do
    ENV.delete(described_class::MASTER_KEY_ENV)

    expect { described_class.encrypt("secret") }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::MissingCredentialMasterKey
    )
  end

  it "fails closed when ciphertext has been modified" do
    ciphertext = described_class.encrypt("supplier-secret")

    expect { described_class.decrypt("#{ciphertext}modified") }.to raise_error(
      WhereIsMyFriends::LicensedImport::AiGateway::InvalidCredential
    )
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::EndpointPolicy do
  it "accepts HTTPS endpoints only when every resolved address is public" do
    policy = described_class.new(resolver: ->(_host) { ["1.1.1.1"] })

    endpoint = policy.resolve!("https://gateway.example/v1")

    expect(endpoint.uri.to_s).to eq("https://gateway.example/v1")
    expect(endpoint.ip_address).to eq("1.1.1.1")
  end

  it "rejects plaintext, credentials, queries, fragments, and private targets" do
    public_resolver = ->(_host) { ["1.1.1.1"] }
    private_resolver = ->(_host) { %w[127.0.0.1 10.0.0.4] }

    expect {
      described_class.new(resolver: public_resolver).resolve!(
        "http://gateway.example/v1"
      )
    }.to raise_error(described_class::UnsafeEndpoint)
    expect {
      described_class.new(resolver: public_resolver).resolve!(
        "https://user:pass@gateway.example/v1"
      )
    }.to raise_error(described_class::UnsafeEndpoint)
    expect {
      described_class.new(resolver: public_resolver).resolve!(
        "https://gateway.example/v1?token=secret#fragment"
      )
    }.to raise_error(described_class::UnsafeEndpoint)
    expect {
      described_class.new(resolver: private_resolver).resolve!(
        "https://gateway.example/v1"
      )
    }.to raise_error(described_class::UnsafeEndpoint)
  end
end

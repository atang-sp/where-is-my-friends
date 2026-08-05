# frozen_string_literal: true
# rubocop:disable Discourse/Plugins/NamespaceMethods -- RSpec example-group helper.

RSpec.describe WhereIsMyFriends::LicensedImport::JsonHttpClient do
  let(:endpoint_policy) do
    WhereIsMyFriends::LicensedImport::EndpointPolicy.new(
      resolver: ->(_host) { ["1.1.1.1"] }
    )
  end

  def client(waits: [])
    described_class.new(
      base_url: "https://gateway.example/v1",
      api_key: "supplier-secret",
      endpoint_policy: endpoint_policy,
      retry_wait: ->(seconds) { waits << seconds }
    )
  end

  it "retries transient HTTP responses and honors Retry-After" do
    waits = []
    request = stub_request(:post, "https://gateway.example/v1/responses")
    request.to_return(
      { status: 429, headers: { "Retry-After" => "2" } },
      { status: 502 },
      { status: 200, body: { ok: true }.to_json }
    )

    expect(client(waits: waits).post("/responses", test: true)).to eq(
      "ok" => true
    )
    expect(waits).to eq([2.0, 2.0])
    expect(request).to have_been_requested.times(3)
  end

  it "retries transient connection failures" do
    waits = []
    request = stub_request(:post, "https://gateway.example/v1/responses")
    request.to_timeout.then.to_return(status: 200, body: { ok: true }.to_json)

    expect(client(waits: waits).post("/responses", test: true)).to eq(
      "ok" => true
    )
    expect(waits).to eq([1.0])
    expect(request).to have_been_requested.times(2)
  end

  it "stops after three transient failures" do
    waits = []
    request = stub_request(:post, "https://gateway.example/v1/responses")
    request.to_return(status: 503)

    expect { client(waits: waits).post("/responses", test: true) }.to(
      raise_error(WhereIsMyFriends::LicensedImport::AiGateway::Error)
    )
    expect(waits).to eq([1.0, 2.0])
    expect(request).to have_been_requested.times(3)
  end

  it "does not retry permanent client errors" do
    waits = []
    request = stub_request(:post, "https://gateway.example/v1/responses")
    request.to_return(status: 401)

    expect { client(waits: waits).post("/responses", test: true) }.to(
      raise_error(WhereIsMyFriends::LicensedImport::AiGateway::Error)
    )
    expect(waits).to be_empty
    expect(request).to have_been_requested.once
  end
end

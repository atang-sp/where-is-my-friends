# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::SourceCatalog do
  it "prioritizes curated Wikimedia articles and dispatches refreshes by source type" do
    wikimedia =
      instance_double(
        WhereIsMyFriends::LicensedImport::WikimediaClient,
        source_type: "wikimedia",
        candidates: [{ source_type: "wikimedia", question_id: 100 }]
      )
    stack_exchange =
      instance_double(
        WhereIsMyFriends::LicensedImport::StackExchangeClient,
        source_type: "stack_exchange",
        candidates: [{ source_type: "stack_exchange", question_id: 200 }]
      )
    allow(wikimedia).to receive(:fetch).with(100).and_return(
      source_type: "wikimedia",
      question_id: 100
    )

    catalog = described_class.new(sources: [wikimedia, stack_exchange])

    expect(catalog.candidates.pluck(:source_type)).to eq(
      %w[wikimedia stack_exchange]
    )
    expect(catalog.fetch("wikimedia", 100)).to include(question_id: 100)
    expect(wikimedia).to have_received(:fetch).with(100)
  end

  it "surfaces source failure when no healthy source has a candidate" do
    failed_source =
      instance_double(
        WhereIsMyFriends::LicensedImport::WikimediaClient,
        source_type: "wikimedia"
      )
    allow(failed_source).to receive(:candidates).and_raise(
      WhereIsMyFriends::LicensedImport::SourceError
    )
    empty_source =
      instance_double(
        WhereIsMyFriends::LicensedImport::StackExchangeClient,
        source_type: "stack_exchange",
        candidates: []
      )

    expect {
      described_class.new(sources: [failed_source, empty_source]).candidates
    }.to raise_error(WhereIsMyFriends::LicensedImport::SourceError)
  end
end

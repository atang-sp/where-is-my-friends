# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::SourceCatalog do
  it "offers only Spanking Art candidates while dispatching legacy refreshes by source type" do
    spanking_art =
      instance_double(
        WhereIsMyFriends::LicensedImport::SpankingArtClient,
        source_type: "spanking_art",
        candidates: [{ source_type: "spanking_art", question_id: 50 }]
      )
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

    allow(spanking_art).to receive(:fetch).with(50).and_return(
      source_type: "spanking_art",
      question_id: 50
    )
    catalog =
      described_class.new(
        candidate_sources: [spanking_art],
        verification_sources: [spanking_art, wikimedia, stack_exchange]
      )

    expect(catalog.candidates.pluck(:source_type)).to eq(%w[spanking_art])
    expect(catalog.fetch("spanking_art", 50)).to include(question_id: 50)
    expect(catalog.fetch("wikimedia", 100)).to include(question_id: 100)
    expect(spanking_art).to have_received(:fetch).with(50)
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
      described_class.new(
        candidate_sources: [failed_source, empty_source]
      ).candidates
    }.to raise_error(WhereIsMyFriends::LicensedImport::SourceError)
  end
end

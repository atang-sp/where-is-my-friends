# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::SourceCatalog do
  it "reports the fixed candidate capacity without constructing a source client" do
    allow(WhereIsMyFriends::LicensedImport::SpankingArtClient).to receive(:new)

    expect(described_class.candidate_capacity).to eq(
      WhereIsMyFriends::LicensedImport::SpankingArtClient::PAGES.length
    )
    expect(described_class.candidate_capacity).to eq(5)
    expect(described_class.candidate_source_type).to eq(
      WhereIsMyFriends::LicensedImport::SpankingArtClient::SOURCE_TYPE
    )
    expect(described_class.candidate_source_ids).to eq(
      WhereIsMyFriends::LicensedImport::SpankingArtClient::PAGES.map do |page|
        page.fetch(:page_id)
      end
    )
    expect(
      WhereIsMyFriends::LicensedImport::SpankingArtClient
    ).not_to have_received(:new)
  end

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

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::TokenBudget do
  it "reserves enough room for the next response before spending past the monthly cap" do
    SiteSetting.licensed_import_monthly_token_budget = 10_000
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 42,
      status: "failed",
      token_count: 9_990
    )

    expect { described_class.new.ensure_available!(11) }.to raise_error(
      described_class::Exhausted
    )
    expect { described_class.new.ensure_available!(10) }.not_to raise_error
  end
end

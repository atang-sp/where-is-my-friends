# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::PublicationTags do
  it "adds the SP education tag to every Spanking Art import" do
    expect(described_class.for("boundaries", source_type: "spanking_art")).to(
      contain_exactly("英文精选", "安全与边界", "sp知识")
    )
  end

  it "keeps adding the SP education tag for SP themes from other sources" do
    expect(described_class.for("aftercare", source_type: "wikimedia")).to(
      contain_exactly("英文精选", "安全与边界", "sp知识")
    )
  end
end

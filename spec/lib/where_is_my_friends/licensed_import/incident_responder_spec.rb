# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::IncidentResponder do
  it "immediately disables importing and hides every affected topic" do
    SiteSetting.licensed_import_enabled = true
    topic = Fabricate(:topic, visible: true)
    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 42,
        status: "published",
        topic_id: topic.id,
        published_at: 1.day.ago
      )

    described_class.new.halt!(
      source_question_id: 42,
      reason: "copyright_complaint"
    )

    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(topic.reload.visible).to eq(false)
    expect(record.reload).to have_attributes(
      status: "hidden",
      failure_code: "copyright_complaint"
    )
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::IncidentResponder do
  fab!(:topic)

  it "immediately disables importing and hides every affected topic" do
    SiteSetting.licensed_import_enabled = true
    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_type: "wikimedia",
        source_question_id: 42,
        status: "published",
        topic_id: topic.id,
        published_at: 1.day.ago
      )
    unrelated =
      WhereIsMyFriendsLicensedImport.create!(
        source_type: "stack_exchange",
        source_question_id: 42,
        status: "preview"
      )

    described_class.new.halt!(
      source_type: "wikimedia",
      source_question_id: 42,
      reason: "copyright_complaint"
    )

    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(topic.reload.visible).to eq(false)
    expect(record.reload).to have_attributes(
      status: "hidden",
      failure_code: "copyright_complaint"
    )
    expect(unrelated.reload.status).to eq("preview")
  end
end

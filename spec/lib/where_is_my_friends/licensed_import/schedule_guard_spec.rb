# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::ScheduleGuard do
  before do
    SiteSetting.licensed_import_enabled = true
    SiteSetting.licensed_import_interval_hours = 24
    SiteSetting.licensed_import_publish_hour = 20
    SiteSetting.licensed_import_max_per_day = 1
  end

  it "runs at the configured Beijing hour, at most once daily and at least 24 hours apart" do
    freeze_time Time.utc(2026, 7, 31, 11, 0)
    expect(described_class.new.due?).to eq(false)

    freeze_time Time.utc(2026, 7, 31, 12, 0)
    expect(described_class.new.due?).to eq(true)

    freeze_time Time.utc(2026, 7, 31, 12, 37)
    expect(described_class.new.due?).to eq(false)

    freeze_time Time.utc(2026, 7, 31, 12, 0)

    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 42,
        status: "preview",
        created_at: 23.hours.ago
      )
    expect(described_class.new.due?).to eq(false)

    record.update_column(:created_at, 25.hours.ago)
    expect(described_class.new.due?).to eq(true)

    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 43,
      status: "preview",
      created_at: 1.hour.ago
    )
    expect(described_class.new.due?).to eq(false)
  end

  it "uses an old preview's actual promotion time for daily and interval limits" do
    freeze_time Time.utc(2026, 8, 1, 12, 0)
    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 44,
        status: "published",
        created_at: 3.days.ago,
        published_at: 1.hour.ago
      )

    expect(described_class.new.due?).to eq(false)

    record.update_column(:published_at, 25.hours.ago)
    expect(described_class.new.due?).to eq(true)
  end
end

# frozen_string_literal: true

RSpec.describe Jobs::WhereIsMyFriendsLicensedImport do
  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.licensed_import_enabled = true
  end

  it "has no side effects while licensed imports are disabled" do
    SiteSetting.licensed_import_enabled = false

    allow(WhereIsMyFriends::LicensedImport::PublicationLock).to receive(
      :synchronize
    )
    allow(WhereIsMyFriends::LicensedImport::ScheduleGuard).to receive(:new)
    allow(WhereIsMyFriends::LicensedImport::EngagementGuard).to receive(:new)

    described_class.new.execute({})

    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(
      WhereIsMyFriends::LicensedImport::PublicationLock
    ).not_to have_received(:synchronize)
    expect(
      WhereIsMyFriends::LicensedImport::ScheduleGuard
    ).not_to have_received(:new)
    expect(
      WhereIsMyFriends::LicensedImport::EngagementGuard
    ).not_to have_received(:new)
  end

  it "stops future runs and notifies administrators when the API key is missing" do
    allow(WhereIsMyFriends::LicensedImport::ScheduleGuard).to receive(
      :new
    ).and_return(double(due?: true))
    allow(WhereIsMyFriends::LicensedImport::EngagementGuard).to receive(
      :new
    ).and_return(double(allow_publication?: true))
    synchronizer =
      instance_spy(WhereIsMyFriends::LicensedImport::SourceSynchronizer)
    allow(synchronizer).to receive(:call)
    allow(WhereIsMyFriends::LicensedImport::SourceSynchronizer).to receive(
      :new
    ).and_return(synchronizer)
    outcome =
      WhereIsMyFriends::LicensedImport::Pipeline::Outcome.new(
        status: "failed",
        failure_code: "missing_api_key"
      )
    allow(WhereIsMyFriends::LicensedImport::Pipeline).to receive(
      :new
    ).and_return(double(run: outcome))
    notifier = instance_spy(WhereIsMyFriends::LicensedImport::AdminNotifier)
    allow(notifier).to receive(:notify)
    allow(WhereIsMyFriends::LicensedImport::AdminNotifier).to receive(
      :new
    ).and_return(notifier)
    allow(DistributedMutex).to receive(:synchronize).and_yield

    described_class.new.execute({})

    expect(DistributedMutex).to have_received(:synchronize).with(
      a_string_matching(/where_is_my_friends_licensed_import_/),
      validity: 2.hours
    )
    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(synchronizer).to have_received(:call)
    expect(notifier).to have_received(:notify).with("missing_api_key")
  end

  it "stops future runs after an AI provider error" do
    allow(WhereIsMyFriends::LicensedImport::ScheduleGuard).to receive(
      :new
    ).and_return(double(due?: true))
    allow(WhereIsMyFriends::LicensedImport::EngagementGuard).to receive(
      :new
    ).and_return(double(allow_publication?: true))
    allow(WhereIsMyFriends::LicensedImport::SourceSynchronizer).to receive(
      :new
    ).and_return(double(call: true))
    outcome =
      WhereIsMyFriends::LicensedImport::Pipeline::Outcome.new(
        status: "failed",
        failure_code: "ai_error"
      )
    allow(WhereIsMyFriends::LicensedImport::Pipeline).to receive(
      :new
    ).and_return(double(run: outcome))
    notifier = instance_spy(WhereIsMyFriends::LicensedImport::AdminNotifier)
    allow(notifier).to receive(:notify)
    allow(WhereIsMyFriends::LicensedImport::AdminNotifier).to receive(
      :new
    ).and_return(notifier)
    allow(DistributedMutex).to receive(:synchronize).and_yield

    described_class.new.execute({})

    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(notifier).to have_received(:notify).with("ai_error")
  end
end

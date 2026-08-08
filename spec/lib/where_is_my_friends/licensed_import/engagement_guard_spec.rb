# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::EngagementGuard do
  let(:as_of) { Time.zone.parse("2030-01-31 12:00:00") }
  let(:notifier) do
    instance_spy(WhereIsMyFriends::LicensedImport::AdminNotifier)
  end

  before { SiteSetting.licensed_import_enabled = true }

  it "defaults the mature sample target to the fixed candidate capacity" do
    values = described_class.new(notifier: notifier).stats(as_of: as_of)

    expect(values.fetch(:mature_sample_requirement)).to eq(
      WhereIsMyFriends::LicensedImport::SourceCatalog.candidate_capacity
    )
  end

  it "does not trigger the no-reply gate with only four mature pilot posts" do
    4.times { |index| create_published(published_at: as_of - (8 + index).days) }

    allowed =
      described_class.new(
        notifier: notifier,
        mature_sample_size: 5
      ).allow_publication?(as_of: as_of)

    expect(allowed).to eq(true)
    expect(SiteSetting.licensed_import_enabled).to eq(true)
    expect(notifier).not_to have_received(:notify)
  end

  it "pauses immediately when all five mature pilot posts have no human reply" do
    5.times { |index| create_published(published_at: as_of - (8 + index).days) }

    allowed =
      described_class.new(notifier: notifier).allow_publication?(as_of: as_of)

    expect(allowed).to eq(false)
    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(notifier).to have_received(:notify).with("pilot_without_human_reply")
  end

  it "fails the 30-day reply-rate gate when only two of five posts have replies" do
    5.times do |index|
      create_published(
        published_at: as_of - (30 - index).days,
        replied: index < 2
      )
    end

    allowed =
      described_class.new(notifier: notifier).allow_publication?(as_of: as_of)

    expect(allowed).to eq(false)
    expect(notifier).to have_received(:notify).with(
      "thirty_day_reply_rate_below_half"
    )
  end

  it "passes the 30-day reply-rate gate when three of five posts have replies" do
    5.times do |index|
      create_published(
        published_at: as_of - (30 - index).days,
        replied: index < 3
      )
    end

    allowed =
      described_class.new(notifier: notifier).allow_publication?(as_of: as_of)

    expect(allowed).to eq(true)
    expect(SiteSetting.licensed_import_enabled).to eq(true)
    expect(notifier).not_to have_received(:notify)
  end

  it "fails closed at 30 days when fewer than five mature posts exist" do
    4.times do |index|
      create_published(
        published_at: as_of - (30 - index).days,
        replied: index < 2
      )
    end

    allowed =
      described_class.new(notifier: notifier).allow_publication?(as_of: as_of)

    expect(allowed).to eq(false)
    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(notifier).to have_received(:notify).with(
      "thirty_day_insufficient_mature_sample"
    )
  end

  it "pauses when current human-original topic supply declines" do
    5.times do |index|
      create_published(
        published_at: as_of - (30 - index).days,
        replied: index < 3
      )
    end
    create_human_topic(created_at: as_of - 45.days)
    create_human_topic(created_at: as_of - 40.days)
    create_human_topic(created_at: as_of - 15.days)

    allowed =
      described_class.new(notifier: notifier).allow_publication?(as_of: as_of)

    expect(allowed).to eq(false)
    expect(notifier).to have_received(:notify).with(
      "human_original_topics_declined"
    )
  end

  it "does not treat a zero human-original baseline as a decline" do
    5.times do |index|
      create_published(
        published_at: as_of - (30 - index).days,
        replied: index < 3
      )
    end

    allowed =
      described_class.new(notifier: notifier).allow_publication?(as_of: as_of)

    expect(allowed).to eq(true)
    expect(notifier).not_to have_received(:notify)
  end

  it "does not draw a 30-day conclusion before the first post reaches 30 days" do
    5.times do |index|
      create_published(
        published_at: as_of - (29 - index).days,
        replied: index.zero?
      )
    end

    allowed =
      described_class.new(notifier: notifier).allow_publication?(as_of: as_of)

    expect(allowed).to eq(true)
    expect(SiteSetting.licensed_import_enabled).to eq(true)
    expect(notifier).not_to have_received(:notify)
  end

  it "accepts an injected mature sample size without consulting the network" do
    allow(Net::HTTP).to receive(:start)
    2.times { |index| create_published(published_at: as_of - (8 + index).days) }
    guard = described_class.new(notifier: notifier, mature_sample_size: 2)

    expect(guard.stats(as_of: as_of)).to include(mature_sample_requirement: 2)
    expect(guard.allow_publication?(as_of: as_of)).to eq(false)
    expect(notifier).to have_received(:notify).with("pilot_without_human_reply")
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "does not count human replies that arrive after the seven-day window" do
    2.times do |index|
      create_published(
        published_at: as_of - (9 + index).days,
        replied: true,
        reply_delay: 8.days
      )
    end

    allowed =
      described_class.new(
        notifier: notifier,
        mature_sample_size: 2
      ).allow_publication?(as_of: as_of)

    expect(allowed).to eq(false)
    expect(notifier).to have_received(:notify).with("pilot_without_human_reply")
  end

  def create_published(published_at:, replied: false, reply_delay: 1.day)
    topic =
      Fabricate(:topic, user: Discourse.system_user, created_at: published_at)
    first_post =
      Fabricate(
        :post,
        topic: topic,
        user: Discourse.system_user,
        post_number: 1,
        created_at: published_at
      )
    if replied
      Fabricate(
        :post,
        topic: topic,
        user: Fabricate(:user),
        post_number: 2,
        created_at: published_at + reply_delay
      )
    end
    @source_id = (@source_id || 10_000) + 1
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: @source_id,
      status: "published",
      topic: topic,
      first_post_id: first_post.id,
      published_at: published_at,
      created_at: published_at
    )
  end

  def create_human_topic(created_at:)
    Fabricate(:topic, user: Fabricate(:user), created_at: created_at)
  end
end

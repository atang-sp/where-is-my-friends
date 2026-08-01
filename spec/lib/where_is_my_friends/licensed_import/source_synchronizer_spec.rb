# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::SourceSynchronizer do
  fab!(:changed_topic, :topic)
  fab!(:deleted_topic, :topic)
  fab!(:license_topic, :topic)
  fab!(:wikimedia_topic, :topic)

  it "unlists a published translation when the licensed source has changed" do
    topic = changed_topic
    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 42,
        source_answer_id: 84,
        status: "published",
        topic_id: topic.id,
        source_revised_at: 2.days.ago,
        published_at: 1.day.ago
      )
    source = instance_double(WhereIsMyFriends::LicensedImport::SourceCatalog)
    allow(source).to receive(:fetch).with("stack_exchange", 42).and_return(
      {
        source_type: "stack_exchange",
        question_id: 42,
        answer_id: 84,
        revised_at: 1.hour.ago
      }
    )

    described_class.new(source: source).call

    expect(record.reload).to have_attributes(
      status: "hidden",
      failure_code: "source_changed"
    )
    expect(topic.reload.visible).to eq(false)
  end

  it "unlists a published translation when the licensed source is deleted" do
    topic = deleted_topic
    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 43,
        source_answer_id: 86,
        status: "published",
        topic_id: topic.id,
        source_revised_at: 2.days.ago,
        published_at: 1.day.ago
      )
    source = instance_double(WhereIsMyFriends::LicensedImport::SourceCatalog)
    allow(source).to receive(:fetch).with("stack_exchange", 43).and_raise(
      WhereIsMyFriends::LicensedImport::MissingSource
    )

    described_class.new(source: source).call

    expect(record.reload).to have_attributes(
      status: "hidden",
      failure_code: "source_removed"
    )
    expect(topic.reload.visible).to eq(false)
  end

  it "unlists a translation when either source license disappears" do
    revised_at = 2.days.ago
    topic = license_topic
    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 44,
        source_answer_id: 88,
        source_question_url: "https://interpersonal.stackexchange.com/q/44",
        source_answer_url: "https://interpersonal.stackexchange.com/a/88",
        question_author: "Question Author",
        answer_author: "Answer Author",
        question_license: "CC BY-SA 4.0",
        answer_license: "CC BY-SA 4.0",
        source_revised_at: revised_at,
        status: "published",
        topic_id: topic.id,
        published_at: 1.day.ago
      )
    source = instance_double(WhereIsMyFriends::LicensedImport::SourceCatalog)
    allow(source).to receive(:fetch).with("stack_exchange", 44).and_return(
      {
        source_type: "stack_exchange",
        question_id: 44,
        answer_id: 88,
        question_url: "https://interpersonal.stackexchange.com/q/44",
        answer_url: "https://interpersonal.stackexchange.com/a/88",
        question_author: "Question Author",
        answer_author: "Answer Author",
        question_license: "CC BY-SA 4.0",
        answer_license: nil,
        revised_at: revised_at
      }
    )

    described_class.new(source: source).call

    expect(record.reload).to have_attributes(
      status: "hidden",
      failure_code: "source_changed"
    )
    expect(topic.reload.visible).to eq(false)
  end

  it "unlists a Wikimedia excerpt when its permanent revision changes" do
    topic = wikimedia_topic
    record =
      WhereIsMyFriendsLicensedImport.create!(
        source_type: "wikimedia",
        source_question_id: 1_008_761,
        source_answer_id: 100,
        status: "published",
        topic_id: topic.id,
        published_at: 1.day.ago
      )
    source = instance_double(WhereIsMyFriends::LicensedImport::SourceCatalog)
    allow(source).to receive(:fetch).with("wikimedia", 1_008_761).and_return(
      { source_type: "wikimedia", question_id: 1_008_761, answer_id: 101 }
    )

    described_class.new(source: source).call

    expect(record.reload).to have_attributes(
      status: "hidden",
      failure_code: "source_changed"
    )
    expect(topic.reload.visible).to eq(false)
  end
end

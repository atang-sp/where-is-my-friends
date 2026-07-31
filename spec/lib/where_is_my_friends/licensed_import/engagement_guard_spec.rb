# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::EngagementGuard do
  it "pauses after seven mature consecutive translations receive no human reply" do
    SiteSetting.licensed_import_enabled = true
    notifier = instance_spy(WhereIsMyFriends::LicensedImport::AdminNotifier)
    allow(notifier).to receive(:notify)

    7.times do |index|
      topic =
        Fabricate(
          :topic,
          user: Discourse.system_user,
          created_at: (14 - index).days.ago
        )
      Fabricate(
        :post,
        topic: topic,
        user: Discourse.system_user,
        post_number: 1,
        created_at: topic.created_at
      )
      if index.zero?
        Fabricate(
          :post,
          topic: topic,
          user: Discourse.system_user,
          post_number: 2,
          created_at: topic.created_at + 1.minute
        )
      end
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 100 + index,
        source_answer_id: 200 + index,
        status: "published",
        topic_id: topic.id,
        first_post_id: topic.first_post.id,
        published_at: topic.created_at,
        created_at: topic.created_at
      )
    end

    allowed = described_class.new(notifier: notifier).allow_publication?

    expect(allowed).to eq(false)
    expect(SiteSetting.licensed_import_enabled).to eq(false)
    expect(notifier).to have_received(:notify).with("seven_without_human_reply")
  end

  it "does not count replies posted after the seven-day response window" do
    SiteSetting.licensed_import_enabled = true
    notifier = instance_spy(WhereIsMyFriends::LicensedImport::AdminNotifier)
    human = Fabricate(:user)

    7.times do |index|
      published_at = (15 - index).days.ago
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
      Fabricate(
        :post,
        topic: topic,
        user: human,
        post_number: 2,
        created_at: published_at + 8.days
      )
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 300 + index,
        status: "published",
        topic_id: topic.id,
        first_post_id: first_post.id,
        published_at: published_at,
        created_at: published_at
      )
    end

    allowed = described_class.new(notifier: notifier).allow_publication?

    expect(allowed).to eq(false)
    expect(notifier).to have_received(:notify).with("seven_without_human_reply")
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::GrowthReport do
  def content_supply_without(topics, since:, as_of:)
    original_created_at = topics.to_h { |topic| [topic.id, topic.created_at] }
    Topic.where(id: original_created_at.keys).update_all(
      created_at: as_of + 1.day
    )

    described_class.new(since:, as_of:).call.fetch(:content_supply)
  ensure
    original_created_at&.each do |topic_id, created_at|
      Topic.where(id: topic_id).update_all(created_at: created_at)
    end
  end

  it "includes privacy-safe connection outcomes without replacing existing sections" do
    as_of = Time.zone.parse("2026-08-31 12:00:00")
    SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3
    3.times do
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "shared-interest",
        created_at: as_of - 2.days
      )
    end

    report = described_class.new(since: as_of - 30.days, as_of: as_of).call

    expect(report.keys).to contain_exactly(
      :period,
      :funnel,
      :connections,
      :dynamics,
      :content_supply,
      :daily
    )
    expect(
      report.dig(:connections, :by_source, "native", :window, :invitations_sent)
    ).to eq(3)
  end

  context "with public-topic supply" do
    let(:as_of) { Time.zone.parse("2026-08-10 12:00:00") }

    fab!(:author, :user)
    fab!(:responder, :user)
    fab!(:replied_topic) do
      Fabricate(
        :topic,
        user: author,
        created_at: Time.zone.parse("2026-08-02 12:00:00")
      )
    end
    fab!(:unanswered_topic) do
      Fabricate(
        :topic,
        user: author,
        created_at: Time.zone.parse("2026-08-02 12:00:00")
      )
    end
    fab!(:reply) do
      Fabricate(
        :post,
        topic: replied_topic,
        user: responder,
        post_number: 2,
        created_at: Time.zone.parse("2026-08-03 12:00:00")
      )
    end
    fab!(:recent_topic) do
      Fabricate(
        :topic,
        user: author,
        created_at: Time.zone.parse("2026-08-09 12:00:00")
      )
    end
    fab!(:recent_reply) do
      Fabricate(
        :post,
        topic: recent_topic,
        user: responder,
        post_number: 2,
        created_at: Time.zone.parse("2026-08-10 00:00:00")
      )
    end
    fab!(:private_group, :group)
    fab!(:private_category) do
      Fabricate(:private_category, group: private_group)
    end
    fab!(:private_topic) do
      Fabricate(
        :topic,
        user: author,
        category: private_category,
        created_at: Time.zone.parse("2026-08-09 12:00:00")
      )
    end

    it "reports mature public-topic supply and human responses" do
      since = as_of - 30.days
      baseline_supply =
        content_supply_without(
          [replied_topic, unanswered_topic, recent_topic],
          since: since,
          as_of: as_of
        )
      supply =
        described_class
          .new(since: since, as_of: as_of)
          .call
          .fetch(:content_supply)

      additive_metrics =
        supply
          .except(:seven_day_human_response_rate)
          .to_h { |key, value| [key, value - baseline_supply.fetch(key)] }
      expect(additive_metrics).to eq(
        public_topics_created: 3,
        human_topics_created: 3,
        imported_topics_created: 0,
        unique_human_topic_authors: 1,
        unique_human_repliers: 1,
        mature_topics: 2,
        in_progress_topics: 1,
        mature_topics_with_human_response: 1
      )
      expect(supply.fetch(:seven_day_human_response_rate)).to eq(
        (
          (baseline_supply.fetch(:mature_topics_with_human_response) + 1).to_f /
            (baseline_supply.fetch(:mature_topics) + 2)
        ).round(4)
      )
    end
  end

  context "with a licensed import" do
    let(:as_of) { Time.zone.parse("2026-08-10 12:00:00") }

    fab!(:imported_topic) do
      Fabricate(
        :topic,
        user: Discourse.system_user,
        created_at: Time.zone.parse("2026-08-02 12:00:00")
      )
    end

    before do
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 12_345,
        topic: imported_topic,
        status: "published"
      )
    end

    it "separates licensed imports from human-created topics" do
      since = as_of - 30.days
      baseline_supply =
        content_supply_without([imported_topic], since: since, as_of: as_of)
      supply =
        described_class
          .new(since: since, as_of: as_of)
          .call
          .fetch(:content_supply)

      expect(
        supply
          .slice(
            :public_topics_created,
            :human_topics_created,
            :imported_topics_created,
            :unique_human_topic_authors
          )
          .to_h { |key, value| [key, value - baseline_supply.fetch(key)] }
      ).to eq(
        public_topics_created: 1,
        human_topics_created: 0,
        imported_topics_created: 1,
        unique_human_topic_authors: 0
      )
    end
  end

  context "with discovery activity on multiple days" do
    let(:since) { Time.zone.parse("2026-08-08 00:00:00") }
    let(:as_of) { Time.zone.parse("2026-08-10 12:00:00") }

    fab!(:recommendation_user, :user)
    fab!(:local_user, :user)
    fab!(:topic_author, :user)
    fab!(:responder, :user)
    fab!(:topic) do
      Fabricate(
        :topic,
        user: topic_author,
        created_at: Time.zone.parse("2026-08-08 12:00:00")
      )
    end
    fab!(:response) do
      Fabricate(
        :post,
        topic: topic,
        user: responder,
        post_number: 2,
        created_at: Time.zone.parse("2026-08-09 12:00:00")
      )
    end
    fab!(:older_topic) do
      Fabricate(
        :topic,
        user: topic_author,
        created_at: Time.zone.parse("2026-07-29 00:00:00")
      )
    end
    fab!(:older_topic_response) do
      Fabricate(
        :post,
        topic: older_topic,
        user: responder,
        post_number: 2,
        created_at: Time.zone.parse("2026-08-09 12:00:00")
      )
    end

    it "returns a daily trend for discovery and content supply" do
      WhereIsMyFriendsEvent.create!(
        user: recommendation_user,
        event_name: "recommendation_panel_expanded",
        surface: "homepage",
        recommendation_group: "topics",
        created_at: since + 12.hours
      )
      WhereIsMyFriendsEvent.create!(
        user: recommendation_user,
        event_name: "recommendation_impression",
        surface: "homepage",
        recommendation_group: "topics",
        created_at: since + 12.hours
      )
      WhereIsMyFriendsEvent.create!(
        user: recommendation_user,
        event_name: "recommended_topic_opened",
        surface: "homepage",
        recommendation_group: "topics",
        created_at: since + 12.hours
      )
      WhereIsMyFriendsEvent.create!(
        user: local_user,
        event_name: "local_callout_viewed",
        surface: "homepage",
        created_at: since + 1.day + 12.hours
      )
      WhereIsMyFriendsEvent.create!(
        user: local_user,
        event_name: "local_callout_opened",
        surface: "homepage",
        created_at: since + 1.day + 12.hours
      )

      daily = described_class.new(since: since, as_of: as_of).call.fetch(:daily)

      expect(daily).to eq(
        [
          {
            date: "2026-08-08",
            recommendation_panel_expanded_users: 1,
            recommendation_exposed_users: 1,
            recommendation_openers: 1,
            local_callout_viewers: 0,
            local_callout_openers: 0,
            local_callout_location_savers: 0,
            public_topics_created: 1,
            topics_receiving_human_response: 0
          },
          {
            date: "2026-08-09",
            recommendation_panel_expanded_users: 0,
            recommendation_exposed_users: 0,
            recommendation_openers: 0,
            local_callout_viewers: 1,
            local_callout_openers: 1,
            local_callout_location_savers: 0,
            public_topics_created: 0,
            topics_receiving_human_response: 2
          },
          {
            date: "2026-08-10",
            recommendation_panel_expanded_users: 0,
            recommendation_exposed_users: 0,
            recommendation_openers: 0,
            local_callout_viewers: 0,
            local_callout_openers: 0,
            local_callout_location_savers: 0,
            public_topics_created: 0,
            topics_receiving_human_response: 0
          }
        ]
      )
    end
  end
end

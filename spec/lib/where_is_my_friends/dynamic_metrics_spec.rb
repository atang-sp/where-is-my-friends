# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::DynamicMetrics do
  let(:since) { Time.zone.parse("2026-08-01 00:00:00") }
  let(:as_of) { Time.zone.parse("2026-08-31 12:00:00") }

  fab!(:author, :user)
  fab!(:second_author, :user)
  fab!(:historic_author, :user)
  fab!(:responder, :user)
  fab!(:late_responder, :user)
  fab!(:viewer, :user)
  fab!(:preview_viewer, :user)
  fab!(:plain_card_viewer, :user)
  fab!(:regular_participant, :user)
  fab!(:staff, :admin)

  let(:create_dynamic) do
    lambda do |user:, created_at:|
      topic = Fabricate(:topic, user: user, created_at: created_at)
      Fabricate(
        :post,
        topic: topic,
        user: user,
        post_number: 1,
        raw: "A personal dynamic with enough text",
        created_at: created_at
      )
      topic.custom_fields[WhereIsMyFriends::DynamicFeed::FIELD] = true
      topic.save_custom_fields
      topic
    end
  end

  it "reports supply, replies, discovery funnels, and UserVisit returns" do
    first = create_dynamic.call(user: author, created_at: since + 1.day)
    create_dynamic.call(user: second_author, created_at: since + 2.days)
    create_dynamic.call(user: author, created_at: since + 19.days)
    create_dynamic.call(user: author, created_at: since + 27.days)
    create_dynamic.call(user: staff, created_at: since + 3.days)
    historic =
      create_dynamic.call(user: historic_author, created_at: since - 10.days)

    Fabricate(
      :post,
      topic: first,
      user: responder,
      post_number: 2,
      created_at: since + 3.days
    )
    Fabricate(
      :post,
      topic: first,
      user: author,
      post_number: 3,
      created_at: since + 4.days
    )
    Fabricate(
      :post,
      topic: historic,
      user: late_responder,
      post_number: 2,
      created_at: since + 6.days
    )
    Fabricate(
      :post,
      topic: first,
      user: staff,
      post_number: 4,
      created_at: since + 4.days
    )

    WhereIsMyFriendsEvent.create!(
      user: viewer,
      event_name: "recent_dynamics_viewed",
      surface: "homepage",
      recommendation_group: "dynamics",
      created_at: since + 2.days
    )
    WhereIsMyFriendsEvent.create!(
      user: viewer,
      event_name: "dynamic_opened",
      surface: "homepage",
      recommendation_group: "dynamics",
      created_at: since + 3.days
    )
    WhereIsMyFriendsEvent.create!(
      user: preview_viewer,
      event_name: "recommendation_impression",
      surface: "homepage",
      recommendation_group: "people",
      has_dynamic_preview: true,
      created_at: since + 4.days
    )
    WhereIsMyFriendsEvent.create!(
      user: preview_viewer,
      event_name: "recommended_user_dynamic_opened",
      surface: "homepage",
      recommendation_group: "people",
      has_dynamic_preview: true,
      created_at: since + 5.days
    )
    WhereIsMyFriendsEvent.create!(
      user: plain_card_viewer,
      event_name: "recommendation_impression",
      surface: "homepage",
      recommendation_group: "people",
      has_dynamic_preview: false,
      created_at: since + 4.days
    )
    WhereIsMyFriendsEvent.create!(
      user: plain_card_viewer,
      event_name: "recommended_user_profile_opened",
      surface: "homepage",
      recommendation_group: "people",
      has_dynamic_preview: false,
      created_at: since + 5.days
    )

    regular_topic =
      Fabricate(:topic, user: regular_participant, created_at: since + 5.days)
    Fabricate(
      :post,
      topic: regular_topic,
      user: regular_participant,
      post_number: 1,
      created_at: since + 5.days
    )

    author.user_visits.create!(visited_at: (since + 2.days).to_date)
    responder.user_visits.create!(visited_at: (since + 4.days).to_date)
    late_responder.user_visits.create!(visited_at: (since + 7.days).to_date)
    staff.user_visits.create!(visited_at: (since + 6.days).to_date)
    viewer.user_visits.create!(visited_at: (since + 4.days).to_date)
    preview_viewer.user_visits.create!(visited_at: (since + 7.days).to_date)
    regular_participant.user_visits.create!(
      visited_at: (since + 7.days).to_date
    )

    report = nil
    queries =
      track_sql_queries do
        report = described_class.new(since: since, as_of: as_of).call
      end

    expect(queries.grep(/FROM \"user_visits\"/).length).to eq(1)

    expect(report.fetch(:supply)).to eq(
      dynamics_created: 4,
      unique_non_staff_authors: 2,
      daily_authors: [
        { date: "2026-08-02", authors: 1 },
        { date: "2026-08-03", authors: 1 },
        { date: "2026-08-20", authors: 1 },
        { date: "2026-08-28", authors: 1 }
      ],
      mature_authors: 2,
      repeat_authors: 1,
      repeat_author_rate: 0.5
    )
    expect(report.fetch(:replies)).to eq(
      mature_dynamics: 3,
      in_progress_dynamics: 1,
      dynamics_with_non_author_reply: 1,
      seven_day_reply_rate: 0.3333,
      unanswered_mature_dynamics: 2,
      median_first_reply_seconds: 172_800,
      unique_repliers: 2
    )
    expect(report.fetch(:homepage)).to eq(
      viewed_users: 1,
      opened_users: 1,
      open_rate: 1.0
    )
    expect(report.fetch(:member_cards)).to eq(
      with_dynamic_preview: {
        exposed_users: 1,
        card_openers: 1,
        composite_open_rate: 1.0,
        dynamic_openers: 1,
        dynamic_open_rate: 1.0
      },
      without_dynamic_preview: {
        exposed_users: 1,
        card_openers: 1,
        composite_open_rate: 1.0,
        dynamic_openers: 0,
        dynamic_open_rate: 0.0
      }
    )
    expect(report.fetch(:seven_day_return)).to eq(
      publishers: {
        mature_users: 2,
        in_progress_users: 0,
        returning_users: 1,
        return_rate: 0.5
      },
      repliers: {
        mature_users: 3,
        in_progress_users: 0,
        returning_users: 3,
        return_rate: 1.0
      },
      openers: {
        mature_users: 2,
        in_progress_users: 0,
        returning_users: 2,
        return_rate: 1.0
      },
      regular_public_content_participants: {
        mature_users: 1,
        in_progress_users: 0,
        returning_users: 1,
        return_rate: 1.0
      }
    )
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::ConnectionMetrics do
  let(:as_of) { Time.zone.parse("2026-08-31 12:00:00") }
  let(:since) { as_of - 30.days }

  before { SiteSetting.where_is_my_friends_aggregate_privacy_threshold = 3 }

  it "suppresses empty source groups instead of exposing exact zeroes" do
    expect(described_class.new(since: since, as_of: as_of).call).to eq(
      as_of: as_of.iso8601,
      seven_day_cutoff: (as_of - 7.days).iso8601,
      privacy_threshold: 3,
      by_source: {
        "native" => {
          limited: true
        },
        "legacy_reconfirmed" => {
          limited: true
        }
      }
    )
  end

  it "keeps invitations with an incomplete observation window in progress" do
    senders = 3.times.map { Fabricate(:user) }
    recipients = 3.times.map { Fabricate(:user) }
    3.times do |index|
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: senders.fetch(index),
        recipient: recipients.fetch(index),
        interest_name: "shared-interest",
        created_at: as_of - 2.days
      )
    end

    native =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native")

    expect(native).to include(limited: false)
    expect(native.fetch(:window)).to eq(
      invitations_sent: 3,
      unique_senders: 3,
      unique_recipients: 3,
      state_breakdown: {
        limited: false,
        responded_at_present: 0,
        pending: 3,
        accepted: 0,
        declined: 0,
        ignored: 0,
        cancelled: 0
      }
    )
    expect(native.fetch(:response_cohort_7d)).to include(
      limited: false,
      mature_invitations: 0,
      in_progress_invitations: 3,
      unresolved_within_7d: 0
    )
  end

  it "does not leak responses that occur after the historical as_of" do
    %w[accepted declined ignored].each do |status|
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "shared-interest",
        status: status,
        created_at: as_of - 10.days,
        responded_at: as_of + 1.day
      )
    end

    native =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native")

    expect(native.dig(:window, :state_breakdown)).to include(
      responded_at_present: 0,
      pending: 3,
      accepted: 0,
      declined: 0,
      ignored: 0
    )
    expect(native.fetch(:response_cohort_7d)).to include(
      mature_invitations: 3,
      responded_within_7d: 0,
      unresolved_within_7d: 3,
      response_rate_7d: 0.0,
      median_response_seconds: nil
    )
  end

  it "reports every current state and the mature response outcomes" do
    senders = 3.times.map { Fabricate(:user) }
    recipients = 3.times.map { Fabricate(:user) }
    %w[
      pending
      accepted
      declined
      ignored
      cancelled
    ].each_with_index do |status, index|
      2.times do |offset|
        responded_at = as_of - 9.days if %w[accepted declined ignored].include?(
          status
        )
        WhereIsMyFriendsPracticeInvitation.create!(
          sender: senders.fetch((index + offset) % senders.length),
          recipient: recipients.fetch((index + offset) % recipients.length),
          interest_name: "shared-interest",
          status: status,
          created_at: as_of - 10.days,
          responded_at: responded_at
        )
      end
    end

    native =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native")

    expect(native.fetch(:window)).to eq(
      invitations_sent: 10,
      unique_senders: 3,
      unique_recipients: 3,
      state_breakdown: {
        limited: false,
        responded_at_present: 6,
        pending: 2,
        accepted: 2,
        declined: 2,
        ignored: 2,
        cancelled: 2
      }
    )
    expect(native.fetch(:response_cohort_7d)).to eq(
      limited: false,
      mature_invitations: 10,
      in_progress_invitations: 0,
      responded_within_7d: 6,
      accepted_within_7d: 2,
      declined_within_7d: 2,
      ignored_within_7d: 2,
      unresolved_within_7d: 4,
      response_rate_7d: 0.6,
      acceptance_rate_of_mature_7d: 0.2,
      acceptance_rate_of_responded_7d: 0.3333,
      median_response_seconds: 86_400,
      late_responses: 0
    )
  end

  it "uses inclusive seven-day maturity and response boundaries" do
    senders = 6.times.map { Fabricate(:user) }
    recipients = 6.times.map { Fabricate(:user) }
    3.times do |index|
      created_at = as_of - 14.days
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: senders.fetch(index),
        recipient: recipients.fetch(index),
        interest_name: "shared-interest",
        status: "accepted",
        created_at: created_at,
        responded_at: created_at + 7.days
      )
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: senders.fetch(index + 3),
        recipient: recipients.fetch(index + 3),
        interest_name: "shared-interest",
        status: "accepted",
        created_at: created_at,
        responded_at: created_at + 7.days + 1.second
      )
    end
    3.times do |index|
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: senders.fetch(index),
        recipient: recipients.fetch(index + 3),
        interest_name: "shared-interest",
        created_at: as_of - 7.days
      )
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: senders.fetch(index + 3),
        recipient: recipients.fetch(index),
        interest_name: "shared-interest",
        created_at: as_of - 7.days + 1.second
      )
    end

    cohort =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :response_cohort_7d)

    expect(cohort).to include(
      mature_invitations: 9,
      in_progress_invitations: 3,
      responded_within_7d: 3,
      accepted_within_7d: 3,
      unresolved_within_7d: 6,
      late_responses: 3
    )
  end

  it "calculates an odd response-time median from mature seven-day responses" do
    create_accepted_responses([1.hour, 2.hours, 3.hours])

    cohort =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :response_cohort_7d)

    expect(cohort.fetch(:median_response_seconds)).to eq(2.hours.to_i)
  end

  it "calculates an even response-time median from mature seven-day responses" do
    create_accepted_responses([1.hour, 2.hours, 3.hours, 4.hours])

    cohort =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :response_cohort_7d)

    expect(cohort.fetch(:median_response_seconds)).to eq(2.5.hours.to_i)
  end

  it "excludes accepted invitations without a PM from the reciprocal denominator" do
    create_accepted_responses([1.hour, 2.hours, 3.hours])

    reciprocal =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :reciprocal_conversation_7d)

    expect(reciprocal).to eq(
      limited: false,
      mature_accepted_invitations: 0,
      accepted_in_progress: 0,
      sender_followed_up_within_7d: 0,
      reciprocal_conversation_rate_7d: 0.0
    )
  end

  it "atomically suppresses a small accepted-without-PM subgroup" do
    3.times { create_accepted_pm_invitation(responded_at: as_of - 10.days) }
    create_accepted_responses([1.hour])

    source =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native")

    expect(source.dig(:response_cohort_7d, :accepted_within_7d)).to eq(4)
    expect(source.fetch(:reciprocal_conversation_7d)).to eq(limited: true)
  end

  it "anchors reciprocal cohorts on acceptance inside the report window" do
    3.times do
      create_accepted_pm_invitation(
        responded_at: as_of - 10.days,
        created_at: since - 1.day
      )
    end

    source =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native")

    expect(source.fetch(:window)).to eq(limited: true)
    expect(source.fetch(:response_cohort_7d)).to eq(limited: true)
    expect(source.fetch(:reciprocal_conversation_7d)).to include(
      limited: false,
      mature_accepted_invitations: 3,
      accepted_in_progress: 0,
      sender_followed_up_within_7d: 0,
      reciprocal_conversation_rate_7d: 0.0
    )
  end

  it "does not count the recipient-created first PM post as sender follow-up" do
    3.times { create_accepted_pm_invitation(responded_at: as_of - 10.days) }

    reciprocal =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :reciprocal_conversation_7d)

    expect(reciprocal).to eq(
      limited: false,
      mature_accepted_invitations: 3,
      accepted_in_progress: 0,
      sender_followed_up_within_7d: 0,
      reciprocal_conversation_rate_7d: 0.0
    )
  end

  it "counts a regular sender reply inside seven days as reciprocal conversation" do
    3.times do
      invitation, first_post =
        create_accepted_pm_invitation(responded_at: as_of - 10.days)
      Fabricate(
        :post,
        topic: first_post.topic,
        user: invitation.sender,
        post_number: 2,
        created_at: invitation.responded_at + 3.days
      )
    end

    reciprocal =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :reciprocal_conversation_7d)

    expect(reciprocal).to include(
      mature_accepted_invitations: 3,
      sender_followed_up_within_7d: 3,
      reciprocal_conversation_rate_7d: 1.0
    )
  end

  it "does not count a sender reply after the seven-day follow-up window" do
    3.times do
      invitation, first_post =
        create_accepted_pm_invitation(responded_at: as_of - 10.days)
      Fabricate(
        :post,
        topic: first_post.topic,
        user: invitation.sender,
        post_number: 2,
        created_at: invitation.responded_at + 7.days + 1.second
      )
    end

    reciprocal =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :reciprocal_conversation_7d)

    expect(reciprocal).to include(
      mature_accepted_invitations: 3,
      sender_followed_up_within_7d: 0,
      reciprocal_conversation_rate_7d: 0.0
    )
  end

  it "rejects deleted, hidden, non-regular, non-sender, and non-later PM posts" do
    invalid_attributes = [
      { deleted_at: as_of - 8.days },
      { hidden: true },
      { post_type: Post.types[:moderator_action] },
      { user: Fabricate(:user) },
      { user: Discourse.system_user },
      { created_at: nil }
    ]

    invalid_attributes.each do |attributes|
      invitation, first_post =
        create_accepted_pm_invitation(responded_at: as_of - 10.days)
      defaults = {
        topic: first_post.topic,
        user: invitation.sender,
        post_number: 2,
        created_at: invitation.responded_at + 1.day
      }
      defaults[:created_at] = invitation.responded_at if attributes[
        :created_at
      ].nil?
      Fabricate(:post, **defaults.merge(attributes.compact))
    end

    reciprocal =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :reciprocal_conversation_7d)

    expect(reciprocal).to include(
      mature_accepted_invitations: 6,
      sender_followed_up_within_7d: 0,
      reciprocal_conversation_rate_7d: 0.0
    )
  end

  it "keeps accepted PMs in progress until their follow-up window matures" do
    3.times { create_accepted_pm_invitation(responded_at: as_of - 2.days) }

    reciprocal =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :reciprocal_conversation_7d)

    expect(reciprocal).to eq(
      limited: false,
      mature_accepted_invitations: 0,
      accepted_in_progress: 3,
      sender_followed_up_within_7d: 0,
      reciprocal_conversation_rate_7d: 0.0
    )
  end

  it "keeps native and legacy-reconfirmed invitations in separate source groups" do
    3.times do
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "native-interest",
        source: "native",
        created_at: as_of - 2.days
      )
    end
    4.times do
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "legacy-interest",
        source: "legacy_reconfirmed",
        created_at: as_of - 2.days
      )
    end

    report = described_class.new(since: since, as_of: as_of).call

    expect(report.dig(:by_source, "native", :window, :invitations_sent)).to eq(
      3
    )
    expect(
      report.dig(:by_source, "legacy_reconfirmed", :window, :invitations_sent)
    ).to eq(4)
    expect(report).not_to include(:total, :invitations_sent)
  end

  it "suppresses a small source group without exposing a subtractable total" do
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: Fabricate(:user),
      recipient: Fabricate(:user),
      interest_name: "native-interest",
      source: "native",
      created_at: as_of - 2.days
    )
    3.times do
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "legacy-interest",
        source: "legacy_reconfirmed",
        created_at: as_of - 2.days
      )
    end

    report = described_class.new(since: since, as_of: as_of).call

    expect(report.dig(:by_source, "native")).to eq(limited: true)
    expect(
      report.dig(:by_source, "legacy_reconfirmed", :window, :invitations_sent)
    ).to eq(3)
    expect(report.keys).to contain_exactly(
      :as_of,
      :seven_day_cutoff,
      :privacy_threshold,
      :by_source
    )
  end

  it "atomically suppresses response outcomes when a late-response subgroup is small" do
    created_at = as_of - 14.days
    3.times do
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "shared-interest",
        status: "accepted",
        created_at: created_at,
        responded_at: created_at + 1.day
      )
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "shared-interest",
        status: "pending",
        created_at: created_at
      )
    end
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: Fabricate(:user),
      recipient: Fabricate(:user),
      interest_name: "shared-interest",
      status: "accepted",
      created_at: created_at,
      responded_at: created_at + 8.days
    )

    cohort =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :response_cohort_7d)

    expect(cohort).to eq(limited: true)
  end

  it "hides the entire current-state breakdown when one state is a small subgroup" do
    3.times do
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "shared-interest",
        created_at: as_of - 2.days
      )
    end
    WhereIsMyFriendsPracticeInvitation.create!(
      sender: Fabricate(:user),
      recipient: Fabricate(:user),
      interest_name: "shared-interest",
      status: "declined",
      created_at: as_of - 2.days,
      responded_at: as_of - 1.day
    )

    window =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :window)

    expect(window).to include(
      invitations_sent: 4,
      unique_senders: 4,
      unique_recipients: 4,
      state_breakdown: {
        limited: true
      }
    )
  end

  it "hides the reciprocal breakdown when only a small sender subgroup follows up" do
    invitation, first_post =
      create_accepted_pm_invitation(responded_at: as_of - 10.days)
    Fabricate(
      :post,
      topic: first_post.topic,
      user: invitation.sender,
      post_number: 2,
      created_at: invitation.responded_at + 1.day
    )
    2.times { create_accepted_pm_invitation(responded_at: as_of - 10.days) }

    reciprocal =
      described_class
        .new(since: since, as_of: as_of)
        .call
        .dig(:by_source, "native", :reciprocal_conversation_7d)

    expect(reciprocal).to eq(limited: true)
  end

  it "uses a constant number of invitation and post queries as the cohort grows" do
    3.times { create_accepted_pm_invitation(responded_at: as_of - 10.days) }
    small_queries = connection_queries

    6.times { create_accepted_pm_invitation(responded_at: as_of - 10.days) }
    large_queries = connection_queries

    expect(small_queries).to eq(3)
    expect(large_queries).to eq(small_queries)
  end

  def create_accepted_responses(delays)
    created_at = as_of - 10.days
    delays.each do |delay|
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: Fabricate(:user),
        recipient: Fabricate(:user),
        interest_name: "shared-interest",
        status: "accepted",
        created_at: created_at,
        responded_at: created_at + delay
      )
    end
  end

  def create_accepted_pm_invitation(
    responded_at:,
    source: "native",
    created_at: responded_at - 1.day
  )
    sender = Fabricate(:user)
    recipient = Fabricate(:user)
    first_post =
      Fabricate(
        :private_message_post,
        user: recipient,
        recipient: sender,
        post_number: 1,
        created_at: responded_at
      )
    invitation =
      WhereIsMyFriendsPracticeInvitation.create!(
        sender: sender,
        recipient: recipient,
        interest_name: "shared-interest",
        source: source,
        status: "accepted",
        created_at: created_at,
        responded_at: responded_at,
        pm_topic: first_post.topic
      )
    [invitation, first_post]
  end

  def connection_queries
    track_sql_queries do
      described_class.new(since: since, as_of: as_of).call
    end.grep(/where_is_my_friends_practice_invitations|FROM "posts"/).length
  end
end

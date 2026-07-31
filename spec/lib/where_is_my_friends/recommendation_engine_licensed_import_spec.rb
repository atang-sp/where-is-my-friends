# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::RecommendationEngine do
  it "caps licensed translation topics at two of five recommendations" do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_interest_onboarding_enabled = true
    SiteSetting.where_is_my_friends_interest_tags = "boundaries"
    SiteSetting.tagging_enabled = true
    user = Fabricate(:user)
    author = Fabricate(:user, last_seen_at: 1.day.ago)
    tag = Fabricate(:tag, name: "boundaries")
    profile =
      WhereIsMyFriendsInterestProfile.create!(
        user: user,
        purpose: "learn",
        completed_at: Time.zone.now
      )
    profile.interests.create!(user: user, tag: tag, position: 0)
    topics =
      8.times.map do |index|
        Fabricate(
          :topic,
          user: author,
          title: "Boundary discussion #{index}",
          tags: [tag],
          created_at: index.minutes.ago,
          bumped_at: index.minutes.ago
        )
      end
    topics
      .first(4)
      .each_with_index do |topic, index|
        WhereIsMyFriendsLicensedImport.create!(
          source_question_id: 100 + index,
          status: "published",
          topic_id: topic.id,
          published_at: topic.created_at
        )
      end

    recommended =
      described_class
        .new(user)
        .call(profile: profile)
        .fetch(:recommended_topics)
    imported_ids = topics.first(4).map(&:id)

    expect(recommended.length).to eq(5)
    expect(
      recommended.pluck(:id).count { |id| imported_ids.include?(id) }
    ).to be <= 2
  end
end

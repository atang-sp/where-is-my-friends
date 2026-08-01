# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::Pipeline do
  subject(:pipeline) do
    described_class.new(
      source: source,
      moderator: moderator,
      model: model,
      publisher: publisher
    )
  end

  fab!(:recovered_topic) { Fabricate(:topic, user: Discourse.system_user) }
  fab!(:recovered_first_post) do
    Fabricate(
      :post,
      topic: recovered_topic,
      user: Discourse.system_user,
      post_number: 1,
      raw: "已经创建的中文译文"
    )
  end

  let(:moderator) do
    instance_spy(WhereIsMyFriends::LicensedImport::OpenAiModerationClient)
  end
  let(:model) do
    instance_spy(WhereIsMyFriends::LicensedImport::ResponsesClient)
  end
  let(:publisher) { instance_spy(WhereIsMyFriends::LicensedImport::Publisher) }
  let(:source) do
    Class
      .new do
        def candidates
          [
            {
              question_id: 42,
              answer_id: 84,
              question_url: "https://interpersonal.stackexchange.com/q/42",
              answer_url: "https://interpersonal.stackexchange.com/a/84",
              question_author: "Question Author",
              answer_author: "Answer Author",
              question_license: nil,
              answer_license: "CC BY-SA 4.0",
              title: "How can I set a boundary?",
              question_html:
                "<p>I am an adult. How can I set a boundary kindly?</p>",
              answer_html:
                "<p>State what you need and listen to the reply.</p>",
              revised_at: Time.zone.parse("2026-07-30 12:00:00")
            }
          ]
        end
      end
      .new
  end

  before do
    SiteSetting.licensed_import_enabled = true
    SiteSetting.licensed_import_dry_run = true
  end

  it "fails before source retrieval when active provider profiles are missing" do
    outcome = described_class.new.run

    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "missing_api_key"
    )
  end

  it "fails closed before AI or publishing when either post lacks a CC BY-SA license" do
    outcome = pipeline.run

    expect(moderator).not_to have_received(:moderate!)
    expect(model).not_to have_received(:classify!)
    expect(model).not_to have_received(:translate!)
    expect(publisher).not_to have_received(:publish!)
    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "license_missing"
    )
    expect(WhereIsMyFriendsLicensedImport.last).to have_attributes(
      source_question_id: 42,
      status: "failed",
      failure_code: "license_missing",
      translated_title: nil,
      translated_body: nil
    )
  end

  it "stops the candidate loop after a site-wide API key failure" do
    words = "I am an adult. " + Array.new(196, "boundary").join(" ")
    documents =
      [101, 102].map do |question_id|
        {
          question_id: question_id,
          answer_id: question_id + 1_000,
          question_url:
            "https://interpersonal.stackexchange.com/q/#{question_id}",
          answer_url:
            "https://interpersonal.stackexchange.com/a/#{question_id + 1_000}",
          question_author: "Question Author",
          answer_author: "Answer Author",
          question_license: "CC BY-SA 4.0",
          answer_license: "CC BY-SA 4.0",
          title: "How can I set a boundary?",
          question_html: "<p>#{words}</p>",
          answer_html: "<p>#{words}</p>",
          revised_at: 1.day.ago
        }
      end
    allow(source).to receive(:candidates).and_return(documents)
    allow(moderator).to receive(:moderate!).and_raise(
      WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey
    )

    outcome = pipeline.run

    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "missing_api_key"
    )
    expect(moderator).to have_received(:moderate!).once
    expect(
      WhereIsMyFriendsLicensedImport.where(
        source_question_id: documents.pluck(:question_id)
      ).count
    ).to eq(1)
  end

  it "accounts for tokens returned with an invalid model response" do
    words = "I am an adult. " + Array.new(196, "boundary").join(" ")
    allow(source).to receive(:candidates).and_return(
      [
        {
          question_id: 103,
          answer_id: 1_103,
          question_url: "https://interpersonal.stackexchange.com/q/103",
          answer_url: "https://interpersonal.stackexchange.com/a/1103",
          question_author: "Question Author",
          answer_author: "Answer Author",
          question_license: "CC BY-SA 4.0",
          answer_license: "CC BY-SA 4.0",
          title: "How can I set a boundary?",
          question_html: "<p>#{words}</p>",
          answer_html: "<p>#{words}</p>",
          revised_at: 1.day.ago
        }
      ]
    )
    allow(moderator).to receive(:moderate!).once.and_return(true)
    allow(model).to receive(:classify!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "allow",
          "theme" => "boundaries",
          "adult_status" => "clear",
          "consent_status" => "clear",
          "prohibited_reasons" => []
        },
        token_count: 10
      )
    )
    allow(model).to receive(:translate!).and_raise(
      WhereIsMyFriends::LicensedImport::AiGateway::InvalidResponse.new(
        token_count: 20
      )
    )

    outcome = pipeline.run

    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "ai_error"
    )
    expect(outcome.record.token_count).to eq(30)
  end

  it "stores an admin-only Chinese preview after every safety and fidelity gate passes" do
    source_text = "I am an adult. " + Array.new(196, "boundary").join(" ")
    answer_text = Array.new(200, "communicate").join(" ")
    allow(source).to receive(:candidates).and_return(
      [
        {
          question_id: 43,
          answer_id: 86,
          question_url: "https://interpersonal.stackexchange.com/q/43",
          answer_url: "https://interpersonal.stackexchange.com/a/86",
          question_author: "Question Author",
          answer_author: "Answer Author",
          question_license: "CC BY-SA 4.0",
          answer_license: "CC BY-SA 4.0",
          title: "How can I set a boundary?",
          question_html: "<p>#{source_text}</p>",
          answer_html: "<p>#{answer_text}</p>",
          revised_at: Time.zone.parse("2026-07-30 12:00:00")
        }
      ]
    )
    allow(moderator).to receive(:moderate!).twice.and_return(true)
    allow(model).to receive(:classify!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "allow",
          "theme" => "boundaries",
          "adult_status" => "clear",
          "consent_status" => "clear",
          "prohibited_reasons" => []
        },
        token_count: 20
      )
    )
    allow(model).to receive(:translate!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "allow",
          "translated_title" => "如何设定边界",
          "segments" => [
            { "id" => "question_01", "translation" => "完整的问题译文。" },
            { "id" => "answer_01", "translation" => "完整的回答译文。" }
          ],
          "discussion_prompt" => "你会如何表达自己的边界？",
          "redactions" => []
        },
        token_count: 100
      )
    )
    allow(model).to receive(:review!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "verdict" => "pass",
          "omitted_meaning" => false,
          "added_facts_or_advice" => false,
          "numbers_names_links_consistent" => true,
          "tone_strengthened" => false,
          "high_risk_mistranslation" => false,
          "covered_segment_ids" => %w[question_01 answer_01]
        },
        token_count: 30
      )
    )
    outcome = pipeline.run

    expect(publisher).not_to have_received(:publish!)
    expect(outcome.status).to eq("preview")
    expect(outcome.record).to have_attributes(
      theme: "boundaries",
      token_count: 150,
      translated_title: "[英文精选·译文] 如何设定边界"
    )
    expect(outcome.record.translated_body).to include(
      "完整的问题译文。",
      "完整的回答译文。",
      "你会如何表达自己的边界？",
      "Question Author",
      "CC BY-SA 4.0"
    )
    expect(outcome.record.attributes.values.join(" ")).not_to include(
      source_text,
      answer_text
    )
  end

  it "rejects missing, extra, reordered, or numerically changed translation segments" do
    question =
      "I am 25. " + Array.new(198, "boundary").join(" ") +
        ' <a href="https://example.com/guide">guide</a>'
    answer = Array.new(200, "communicate").join(" ")
    document = {
      question_id: 44,
      answer_id: 88,
      question_url: "https://interpersonal.stackexchange.com/q/44",
      answer_url: "https://interpersonal.stackexchange.com/a/88",
      question_author: "Question Author",
      answer_author: "Answer Author",
      question_license: "CC BY-SA 4.0",
      answer_license: "CC BY-SA 4.0",
      title: "A boundary question",
      question_html: "<p>#{question}</p>",
      answer_html: "<p>#{answer}</p>",
      revised_at: 1.day.ago
    }
    valid_segments = [
      {
        "id" => "question_01",
        "translation" => "我今年 25 岁。[guide](https://example.com/guide)"
      },
      { "id" => "answer_01", "translation" => "清楚沟通。" }
    ]
    variants = [
      valid_segments.first(1),
      valid_segments + [{ "id" => "answer_02", "translation" => "新增内容" }],
      valid_segments.reverse,
      [
        {
          "id" => "question_01",
          "translation" => "我今年 26 岁。[guide](https://example.com/guide)"
        },
        valid_segments.last
      ]
    ]

    variants.each do |segments|
      bad_source =
        instance_double(
          WhereIsMyFriends::LicensedImport::StackExchangeClient,
          candidates: [document]
        )
      bad_moderator =
        instance_spy(
          WhereIsMyFriends::LicensedImport::OpenAiModerationClient,
          moderate!: true
        )
      bad_model =
        instance_spy(WhereIsMyFriends::LicensedImport::ResponsesClient)
      allow(bad_model).to receive(:classify!).and_return(
        WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
          data: {
            "decision" => "allow",
            "theme" => "boundaries",
            "adult_status" => "clear",
            "consent_status" => "clear",
            "prohibited_reasons" => []
          },
          token_count: 10
        )
      )
      allow(bad_model).to receive(:translate!).and_return(
        WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
          data: {
            "decision" => "allow",
            "translated_title" => "边界问题",
            "segments" => segments,
            "discussion_prompt" => "你会怎么做？",
            "redactions" => []
          },
          token_count: 20
        )
      )
      outcome =
        described_class.new(
          source: bad_source,
          moderator: bad_moderator,
          model: bad_model,
          publisher: publisher
        ).run

      expect(bad_model).not_to have_received(:review!)
      expect(publisher).not_to have_received(:publish!)
      expect(outcome).to have_attributes(
        status: "failed",
        failure_code: "invalid_translation"
      )
    end
  end

  it "recovers a completed PostCreator side effect on task retry without duplicating the topic" do
    TopicCustomField.create!(
      topic_id: recovered_topic.id,
      name: "where_is_my_friends_licensed_import_source_id",
      value: "42"
    )
    processing =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 42,
        status: "processing"
      )
    topic_count = Topic.count
    outcome = pipeline.run

    expect(moderator).not_to have_received(:moderate!)
    expect(publisher).not_to have_received(:publish!)
    expect(outcome.status).to eq("published")
    expect(processing.reload).to have_attributes(
      status: "published",
      topic_id: recovered_topic.id,
      first_post_id: recovered_first_post.id
    )
    expect(Topic.count).to eq(topic_count)
  end

  it "skips an already published source instead of recreating its database record" do
    TopicCustomField.create!(
      topic_id: recovered_topic.id,
      name: "where_is_my_friends_licensed_import_source_id",
      value: "42"
    )
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 42,
      status: "published",
      topic_id: recovered_topic.id,
      first_post_id: recovered_first_post.id,
      published_at: 1.day.ago
    )

    outcome = nil
    expect { outcome = pipeline.run }.not_to change(
      WhereIsMyFriendsLicensedImport,
      :count
    )
    expect(outcome).to have_attributes(
      status: "skipped",
      failure_code: "duplicate_source"
    )
  end

  it "cannot claim a second active import on the same Beijing date" do
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 999,
      status: "processing",
      scheduled_for_date: Time.zone.now.in_time_zone("Asia/Shanghai").to_date
    )

    outcome = pipeline.run

    expect(outcome).to have_attributes(
      status: "skipped",
      failure_code: "already_claimed"
    )
    expect(publisher).not_to have_received(:publish!)
  end

  it "rejects the same theme on consecutive successful imports" do
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 90,
      status: "preview",
      theme: "boundaries"
    )
    words = Array.new(200, "adult boundary").join(" ")
    allow(source).to receive(:candidates).and_return(
      [
        {
          question_id: 91,
          answer_id: 92,
          question_url: "https://interpersonal.stackexchange.com/q/91",
          answer_url: "https://interpersonal.stackexchange.com/a/92",
          question_author: "Question Author",
          answer_author: "Answer Author",
          question_license: "CC BY-SA 4.0",
          answer_license: "CC BY-SA 4.0",
          title: "Another boundary question",
          question_html: "<p>#{words}</p>",
          answer_html: "<p>#{words}</p>",
          revised_at: 1.day.ago
        }
      ]
    )
    allow(moderator).to receive(:moderate!).once.and_return(true)
    allow(model).to receive(:classify!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "allow",
          "theme" => "boundaries",
          "adult_status" => "clear",
          "consent_status" => "clear",
          "prohibited_reasons" => []
        },
        token_count: 10
      )
    )
    outcome = pipeline.run

    expect(model).not_to have_received(:translate!)
    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "repeated_theme"
    )
  end

  it "does not call AI again for a source already previewed or published" do
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 42,
      status: "preview",
      theme: "boundaries"
    )
    outcome = pipeline.run

    expect(moderator).not_to have_received(:moderate!)
    expect(outcome).to have_attributes(
      status: "skipped",
      failure_code: "duplicate_source"
    )
  end
end

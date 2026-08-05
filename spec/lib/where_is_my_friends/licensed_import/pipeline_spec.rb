# frozen_string_literal: true
# rubocop:disable Discourse/Plugins/NamespaceMethods -- Anonymous test source class.

RSpec.describe WhereIsMyFriends::LicensedImport::Pipeline do
  subject(:pipeline) do
    described_class.new(source: source, model: model, publisher: publisher)
  end

  fab!(:admin)
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

  it "fails before model calls when public publishing has no valid category" do
    SiteSetting.licensed_import_dry_run = false
    SiteSetting.licensed_import_category_id = ""

    outcome =
      described_class.new(
        source: source,
        model: model,
        publisher: WhereIsMyFriends::LicensedImport::Publisher.new
      ).run

    expect(model).not_to have_received(:classify!)
    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "publication_category_missing"
    )
    expect(outcome.record.status).to eq("failed")
  end

  it "starts with only an active generation provider configured" do
    profile =
      WhereIsMyFriendsAiProviderProfile.create!(
        name: "Generation gateway",
        purpose: "generation",
        protocol: "responses",
        base_url: "https://gateway.example/v1",
        model: "supplier-model",
        api_key: "provider-key",
        created_by_id: admin.id,
        updated_by_id: admin.id
      )
    profile.update_columns(
      verified_at: Time.zone.now,
      verified_config_digest: profile.configuration_digest,
      last_test_status: "passed"
    )
    profile.activate!
    SiteSetting.licensed_import_enabled = true
    empty_source =
      instance_double(
        WhereIsMyFriends::LicensedImport::StackExchangeClient,
        candidates: []
      )

    outcome = described_class.new(source: empty_source).run

    expect(outcome).to have_attributes(
      status: "skipped",
      failure_code: "no_candidate"
    )
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

  it "accepts a fixed GFDL article license before invoking content classification" do
    words = Array.new(65, "adult consent communication").join(" ")
    allow(source).to receive(:candidates).and_return(
      [
        {
          source_type: "spanking_art",
          content_kind: "article",
          adult_confirmed: true,
          theme_hint: "boundaries",
          minimum_word_count: 390,
          question_id: 1_232,
          answer_id: 152_283,
          question_url: "https://spankingart.org/wiki/Safeword",
          answer_url:
            "https://web.archive.org/web/20250101070711id_/https://spankingart.org/wiki/Safeword",
          question_author: "Spanking Art Wiki contributors",
          answer_author: "Spanking Art Wiki contributors",
          question_license: "GFDL 1.3",
          answer_license: "GFDL 1.3",
          title: "Safeword",
          question_html: "<p>#{words}</p>",
          answer_html: "<p>#{words}</p>",
          revised_at: nil
        }
      ]
    )
    allow(model).to receive(:classify!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "reject",
          "theme" => "none",
          "adult_status" => "clear",
          "consent_status" => "clear",
          "prohibited_reasons" => ["test rejection"]
        },
        token_count: 10
      )
    )

    outcome = pipeline.run

    expect(model).to have_received(:classify!).once
    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "scope_or_safety_rejected"
    )
    expect(outcome.record).to have_attributes(
      source_type: "spanking_art",
      question_license: "GFDL 1.3",
      answer_license: "GFDL 1.3"
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
    allow(model).to receive(:classify!).and_raise(
      WhereIsMyFriends::LicensedImport::AiGateway::MissingApiKey
    )

    outcome = pipeline.run

    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "missing_api_key"
    )
    expect(model).to have_received(:classify!).once
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
      source_type: "stack_exchange",
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

  it "fails closed when the fully formatted post exceeds the site limit" do
    source_text = Array.new(200, "adult boundary").join(" ")
    answer_text = Array.new(200, "communicate").join(" ")
    allow(source).to receive(:candidates).and_return(
      [
        {
          source_type: "spanking_art",
          content_kind: "article",
          adult_confirmed: true,
          theme_hint: "boundaries",
          question_id: 1_232,
          answer_id: 152_283,
          question_url: "https://spankingart.org/wiki/Safeword",
          answer_url:
            "https://web.archive.org/web/20250101070711id_/https://spankingart.org/wiki/Safeword",
          question_author: "Spanking Art Wiki contributors",
          answer_author: "Spanking Art Wiki contributors",
          question_license: "GFDL 1.3",
          answer_license: "GFDL 1.3",
          title: "Safeword",
          question_html: "<p>#{source_text}</p>",
          answer_html: "<p>#{answer_text}</p>",
          revised_at: nil
        }
      ]
    )
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
    allow(model).to receive(:translate!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "allow",
          "translated_title" => "安全词",
          "segments" => [
            { "id" => "question_01", "translation" => "安全词译文。" },
            { "id" => "answer_01", "translation" => "沟通译文。" }
          ],
          "discussion_prompt" => "你会怎样沟通安全词？",
          "redactions" => []
        },
        token_count: 20
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
        token_count: 10
      )
    )
    oversized = {
      title: "[英文精选·译文] 安全词",
      raw: "x" * (SiteSetting.max_post_length + 1)
    }
    formatter =
      instance_double(
        WhereIsMyFriends::LicensedImport::PostFormatter,
        call: oversized
      )

    outcome =
      described_class.new(
        source: source,
        model: model,
        publisher: publisher,
        formatter: formatter
      ).run

    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "formatted_post_too_long"
    )
    expect(outcome.record.translated_body).to be_nil
    expect(publisher).not_to have_received(:publish!)
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

  it "accepts a curated adult article and preserves its source namespace" do
    words = Array.new(210, "aftercare").join(" ")
    document = {
      source_type: "wikimedia",
      content_kind: "article",
      adult_confirmed: true,
      question_id: 1_008_761,
      answer_id: 123,
      question_url: "https://en.wikipedia.org/wiki/Aftercare_(BDSM)",
      answer_url:
        "https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=123",
      question_author: "Wikipedia contributors",
      answer_author: "Wikipedia contributors",
      question_license: "CC BY-SA 4.0",
      answer_license: "CC BY-SA 4.0",
      title: "Aftercare (BDSM)",
      question_html: "<p>#{words}</p>",
      answer_html: "<p>#{words}</p>",
      revised_at: nil
    }
    allow(source).to receive(:candidates).and_return([document])
    allow(model).to receive(:classify!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "allow",
          "theme" => "aftercare",
          "adult_status" => "clear",
          "consent_status" => "clear",
          "prohibited_reasons" => []
        },
        token_count: 10
      )
    )
    allow(model).to receive(:translate!).and_return(
      WhereIsMyFriends::LicensedImport::AiGateway::Result.new(
        data: {
          "decision" => "allow",
          "translated_title" => "BDSM 事后照护",
          "segments" => [
            { "id" => "question_01", "translation" => "第一部分译文。" },
            { "id" => "answer_01", "translation" => "第二部分译文。" }
          ],
          "discussion_prompt" => "你希望如何提前沟通事后照护？",
          "redactions" => []
        },
        token_count: 20
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
        token_count: 10
      )
    )

    outcome = pipeline.run

    expect(outcome).to have_attributes(status: "preview")
    expect(outcome.record).to have_attributes(
      source_type: "wikimedia",
      theme: "aftercare",
      source_answer_id: 123
    )
    expect(outcome.record.translated_body).to include(
      "## 精选译文",
      "固定版本",
      "Wikipedia contributors"
    )
  end

  it "recovers a completed PostCreator side effect on task retry without duplicating the topic" do
    TopicCustomField.create!(
      topic_id: recovered_topic.id,
      name: "where_is_my_friends_licensed_import_source_key",
      value: "stack_exchange:42"
    )
    processing =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 42,
        status: "processing"
      )
    topic_count = Topic.count
    outcome = pipeline.run

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

    expect(model).not_to have_received(:classify!)
    expect(outcome).to have_attributes(
      status: "skipped",
      failure_code: "duplicate_source"
    )
  end

  it "keeps identical numeric IDs from different source systems independent" do
    WhereIsMyFriendsLicensedImport.create!(
      source_type: "wikimedia",
      source_question_id: 42,
      status: "preview"
    )

    outcome = pipeline.run

    expect(outcome).to have_attributes(
      status: "failed",
      failure_code: "license_missing"
    )
    expect(
      WhereIsMyFriendsLicensedImport.where(source_question_id: 42).count
    ).to eq(2)
  end
end

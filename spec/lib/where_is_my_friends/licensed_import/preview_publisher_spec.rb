# frozen_string_literal: true
# rubocop:disable Discourse/Plugins/NamespaceMethods -- RSpec example-group helpers.

RSpec.describe WhereIsMyFriends::LicensedImport::PreviewPublisher do
  fab!(:category)

  def source_document(overrides = {})
    {
      source_type: "wikimedia",
      question_id: 1_008_761,
      answer_id: 123,
      question_url: "https://en.wikipedia.org/wiki/Aftercare_(BDSM)",
      answer_url:
        "https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=123",
      question_author: "Wikipedia contributors",
      answer_author: "Wikipedia contributors",
      question_license: "CC BY-SA 4.0",
      answer_license: "CC BY-SA 4.0",
      revised_at: nil
    }.merge(overrides)
  end

  def preview_publisher(document: source_document)
    source = instance_double(WhereIsMyFriends::LicensedImport::SourceCatalog)
    allow(source).to receive(:fetch).and_return(document)
    described_class.new(source: source)
  end

  def valid_preview_attributes(overrides = {})
    question_url = "https://en.wikipedia.org/wiki/Aftercare_(BDSM)"
    answer_url =
      "https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=123"
    {
      source_type: "wikimedia",
      source_question_id: 1_008_761,
      source_answer_id: 123,
      source_question_url: question_url,
      source_answer_url: answer_url,
      question_author: "Wikipedia contributors",
      answer_author: "Wikipedia contributors",
      question_license: "CC BY-SA 4.0",
      answer_license: "CC BY-SA 4.0",
      scheduled_for_date: Time.zone.today,
      status: "preview",
      theme: "aftercare",
      token_count: 100,
      translated_title: "[英文精选·译文] BDSM 事后照护",
      translated_body: <<~MARKDOWN
        > 本主题由英文精选翻译机器人自动生成，并经过许可、安全与忠实度校验。下文是中文译文；“社区讨论”不是原作者内容。

        ## 精选译文

        经过全部校验的中文译文

        ### 来源、署名与许可

        - 来源：[Wikipedia contributors](#{question_url}) · [固定版本](#{answer_url}) · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
      MARKDOWN
    }.merge(overrides)
  end

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.licensed_import_category_id = category.id
  end

  it "idempotently promotes one validated preview through the configured publisher" do
    allow(DistributedMutex).to receive(:synchronize).and_yield
    record = WhereIsMyFriendsLicensedImport.create!(valid_preview_attributes)

    post = preview_publisher.call(record.id)
    recovered = preview_publisher.call(record.id)

    expect(recovered.id).to eq(post.id)
    expect(record.reload).to have_attributes(
      status: "published",
      topic_id: post.topic_id,
      first_post_id: post.id
    )
    expect(post.topic).to have_attributes(category_id: category.id)
    expect(post.topic.tags.pluck(:name)).to contain_exactly(
      "英文精选",
      "安全与边界",
      "sp知识"
    )
    expect(
      post.topic.custom_fields["where_is_my_friends_licensed_import_source_key"]
    ).to eq("wikimedia:1008761")
    expect(DistributedMutex).to have_received(:synchronize).with(
      a_string_matching(/where_is_my_friends_licensed_import_/),
      validity: 2.hours
    ).twice
  end

  it "adds the SP education tag to a Spanking Art preview with a rotation theme" do
    allow(DistributedMutex).to receive(:synchronize).and_yield
    document =
      source_document(
        source_type: "spanking_art",
        question_id: 1_232,
        answer_id: 152_283,
        question_url: "https://spankingart.org/wiki/Safeword",
        answer_url:
          "https://web.archive.org/web/20250101070711id_/https://spankingart.org/wiki/Safeword",
        question_author: "Spanking Art Wiki contributors",
        answer_author: "Spanking Art Wiki contributors",
        question_license: "GFDL 1.3",
        answer_license: "GFDL 1.3"
      )
    record =
      WhereIsMyFriendsLicensedImport.create!(
        valid_preview_attributes(
          source_type: "spanking_art",
          source_question_id: 1_232,
          source_answer_id: 152_283,
          source_question_url: document.fetch(:question_url),
          source_answer_url: document.fetch(:answer_url),
          question_author: document.fetch(:question_author),
          answer_author: document.fetch(:answer_author),
          question_license: "GFDL 1.3",
          answer_license: "GFDL 1.3",
          theme: "boundaries",
          translated_body:
            valid_preview_attributes
              .fetch(:translated_body)
              .gsub(
                "https://en.wikipedia.org/wiki/Aftercare_(BDSM)",
                document.fetch(:question_url)
              )
              .gsub(
                "https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=123",
                document.fetch(:answer_url)
              )
              .gsub("Wikipedia contributors", document.fetch(:question_author))
              .gsub("CC BY-SA 4.0", "GFDL 1.3") +
              "\n\n#{WhereIsMyFriends::LicensedImport::PostFormatter::GFDL_NOTICE}" +
              "\n\n## 修改历史 (History)\n\nCopyright © 2026" +
              "\n\n#{WhereIsMyFriends::LicensedImport::PostFormatter::GFDL_TEXT}"
        )
      )

    post = preview_publisher(document: document).call(record.id)

    expect(post.topic.tags.pluck(:name)).to contain_exactly(
      "英文精选",
      "安全与边界",
      "sp知识"
    )
  end

  it "rejects an incomplete GFDL preview before public publishing" do
    document =
      source_document(
        source_type: "spanking_art",
        question_id: 1_232,
        answer_id: 152_283,
        question_url: "https://spankingart.org/wiki/Safeword",
        answer_url:
          "https://web.archive.org/web/20250101070711id_/https://spankingart.org/wiki/Safeword",
        question_author: "Spanking Art Wiki contributors",
        answer_author: "Spanking Art Wiki contributors",
        question_license: "GFDL 1.3",
        answer_license: "GFDL 1.3"
      )
    incomplete_body =
      valid_preview_attributes
        .fetch(:translated_body)
        .gsub(
          "https://en.wikipedia.org/wiki/Aftercare_(BDSM)",
          document.fetch(:question_url)
        )
        .gsub(
          "https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=123",
          document.fetch(:answer_url)
        )
        .gsub("Wikipedia contributors", document.fetch(:question_author))
        .gsub("CC BY-SA 4.0", "GFDL 1.3")
    record =
      WhereIsMyFriendsLicensedImport.create!(
        valid_preview_attributes(
          source_type: "spanking_art",
          source_question_id: 1_232,
          source_answer_id: 152_283,
          source_question_url: document.fetch(:question_url),
          source_answer_url: document.fetch(:answer_url),
          question_author: document.fetch(:question_author),
          answer_author: document.fetch(:answer_author),
          question_license: "GFDL 1.3",
          answer_license: "GFDL 1.3",
          theme: "boundaries",
          translated_body: incomplete_body
        )
      )

    expect { preview_publisher(document: document).call(record.id) }.to(
      raise_error(described_class::InvalidPreview)
    )
  end

  it "does not publish a second preview on the same Beijing day" do
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 42,
      status: "published",
      published_at: Time.zone.now
    )
    preview =
      WhereIsMyFriendsLicensedImport.create!(
        valid_preview_attributes(
          source_question_id: 44_439,
          theme: "spanking",
          translated_title: "[英文精选·译文] SP"
        )
      )

    expect { preview_publisher.call(preview.id) }.to raise_error(
      described_class::PublicationNotDue
    )
    expect(preview.reload.status).to eq("preview")
  end

  it "rejects a record that did not preserve the validated source metadata" do
    preview =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 42,
        status: "preview",
        theme: "aftercare",
        translated_title: "[英文精选·译文] 缺少署名",
        translated_body: "没有来源和许可的正文"
      )

    expect { preview_publisher.call(preview.id) }.to raise_error(
      described_class::InvalidPreview
    )
    expect(preview.reload.status).to eq("preview")
  end

  it "rejects consecutive public topics with the same theme" do
    WhereIsMyFriendsLicensedImport.create!(
      source_question_id: 42,
      status: "published",
      theme: "aftercare",
      published_at: 25.hours.ago
    )
    preview =
      WhereIsMyFriendsLicensedImport.create!(
        valid_preview_attributes(source_question_id: 1_008_762)
      )

    expect { preview_publisher.call(preview.id) }.to raise_error(
      described_class::RepeatedTheme
    )
  end

  it "rejects a preview when its licensed source changed after validation" do
    preview = WhereIsMyFriendsLicensedImport.create!(valid_preview_attributes)

    expect do
      preview_publisher(document: source_document(answer_id: 124)).call(
        preview.id
      )
    end.to raise_error(
      WhereIsMyFriends::LicensedImport::SourceVerifier::Changed
    )
    expect(preview.reload.status).to eq("preview")
  end

  it "does not publish when its licensed source cannot be rechecked" do
    source = instance_double(WhereIsMyFriends::LicensedImport::SourceCatalog)
    allow(source).to receive(:fetch).and_raise(
      WhereIsMyFriends::LicensedImport::SourceError
    )
    preview = WhereIsMyFriendsLicensedImport.create!(valid_preview_attributes)

    expect { described_class.new(source: source).call(preview.id) }.to(
      raise_error(WhereIsMyFriends::LicensedImport::SourceError)
    )
    expect(preview.reload.status).to eq("preview")
  end
end

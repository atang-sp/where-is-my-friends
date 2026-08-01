# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::PostFormatter do
  it "formats a curated article as an excerpt with revision-safe attribution" do
    content =
      WhereIsMyFriends::LicensedImport::ContentProcessor::ProcessedContent.new(
        title: "Aftercare (BDSM)",
        segments: [
          WhereIsMyFriends::LicensedImport::ContentProcessor::Segment.new(
            id: "question_01",
            kind: "question",
            text: "Overview",
            heading_level: 2
          ),
          WhereIsMyFriends::LicensedImport::ContentProcessor::Segment.new(
            id: "answer_01",
            kind: "answer",
            text: "Second paragraph"
          )
        ],
        redactions: [],
        word_count: 400
      )
    document = {
      content_kind: "article",
      question_author: "Wikipedia contributors",
      question_url: "https://en.wikipedia.org/wiki/Aftercare_(BDSM)",
      answer_url:
        "https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=123",
      question_license: "CC BY-SA 4.0"
    }
    translation = {
      "translated_title" => "BDSM 事后照护",
      "segments" => [
        { "id" => "question_01", "translation" => "第一段。" },
        { "id" => "answer_01", "translation" => "第二段。" }
      ],
      "discussion_prompt" => "你希望如何提前沟通事后照护？"
    }

    formatted =
      described_class.new.call(
        document: document,
        content: content,
        translation: translation
      )

    expect(formatted.fetch(:raw)).to include(
      "## 精选译文",
      "### 第一段。\n\n第二段。",
      "Wikipedia contributors",
      "[固定版本](https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=123)",
      "节选指定章节",
      "CC BY-SA 4.0"
    )
    expect(formatted.fetch(:raw)).not_to include("## 问题", "## 优质回答")
  end

  it "includes the complete GFDL and modified-version attribution in each translated topic" do
    content =
      WhereIsMyFriends::LicensedImport::ContentProcessor::ProcessedContent.new(
        title: "Safeword",
        segments: [
          WhereIsMyFriends::LicensedImport::ContentProcessor::Segment.new(
            id: "question_01",
            kind: "question",
            text: "A safeword can pause a consensual adult scene."
          ),
          WhereIsMyFriends::LicensedImport::ContentProcessor::Segment.new(
            id: "answer_01",
            kind: "answer",
            text: "Partners agree on its meaning in advance."
          )
        ],
        redactions: ["image"],
        word_count: 400
      )
    document = {
      source_type: "spanking_art",
      content_kind: "article",
      question_author: "Spanking Art Wiki contributors",
      question_url: "https://spankingart.org/wiki/Safeword",
      answer_url:
        "https://web.archive.org/web/20250101070711id_/https://spankingart.org/wiki/Safeword",
      question_license: "GFDL 1.3",
      source_title: "Safeword",
      source_history_url:
        "https://spankingart.org/index.php?title=Safeword&action=history",
      source_revision_url:
        "https://spankingart.org/index.php?title=Safeword&oldid=152283",
      source_snapshot_at: "20250101070711"
    }
    translation = {
      "translated_title" => "安全词：暂停与停止",
      "segments" => [
        { "id" => "question_01", "translation" => "安全词可以暂停成年人自愿参与的场景。" },
        { "id" => "answer_01", "translation" => "双方会事先约定它的含义。" }
      ],
      "discussion_prompt" => "你更习惯怎样约定暂停信号？"
    }

    formatted =
      described_class.new.call(
        document: document,
        content: content,
        translation: translation
      )
    raw = formatted.fetch(:raw)

    expect(raw).to include(
      "原始标题：Safeword",
      "### 版本标题页",
      "Spanking Art Wiki contributors",
      "[原始页面](https://spankingart.org/wiki/Safeword)",
      "[固定归档版本](https://web.archive.org/web/20250101070711id_/https://spankingart.org/wiki/Safeword)",
      "[原站永久版本](https://spankingart.org/index.php?title=Safeword&oldid=152283)",
      "[完整贡献历史](https://spankingart.org/index.php?title=Safeword&action=history)",
      "修改者：Where Is My Friends 英文精选翻译机器人",
      "修改版本发布者：https://atang-sp.run.place",
      "无恒定章节、封面文字或封底文字",
      "Permission is granted to copy, distribute and/or modify this document",
      "with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts.",
      "## 修改历史 (History)",
      "2025-01-01 07:07:11 UTC",
      "GNU Free Documentation License",
      "Version 1.3, 3 November 2008",
      "to permit their use in free software."
    )
    expect(raw.scan("GNU Free Documentation License").length).to be >= 2
    expect(raw).to include("删除图片", "翻译为简体中文")
    expect(
      Digest::SHA256.hexdigest(
        WhereIsMyFriends::LicensedImport::PostFormatter::GFDL_TEXT
      )
    ).to eq("110535522396708cea37c72a802c5e7e81391139f5f7985631c93ef242b206a4")
  end
end

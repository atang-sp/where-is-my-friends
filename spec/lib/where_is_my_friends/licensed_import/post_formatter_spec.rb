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
end

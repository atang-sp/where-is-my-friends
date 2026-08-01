# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::ContentProcessor do
  it "turns allowed HTML into stable segments while removing private and unlicensed material" do
    long_quote = Array.new(55, "quoted").join(" ")
    document = {
      content_kind: "article",
      adult_confirmed: true,
      theme_hint: "aftercare",
      title: "Setting a boundary",
      question_html: <<~HTML,
        <h2>Overview</h2>
        <p>Please email me at person@example.com.</p>
        <p>We planned to meet at 123 Main Street.</p>
        <p>The old office was at 127-129, Example Road.</p>
        <img src="https://example.com/private.jpg">
        <blockquote>#{long_quote}</blockquote>
      HTML
      answer_html: <<~HTML
        <p>State the boundary clearly.</p>
        <p>Listen to the other person's response.</p>
      HTML
    }

    content = described_class.new.call(document)

    expect(content.segments.map(&:id)).to eq(
      %w[question_01 question_02 question_03 question_04 answer_01 answer_02]
    )
    expect(content.segments.first).to have_attributes(
      text: "Overview",
      heading_level: 2
    )
    expect(content.segments.map(&:text).join(" ")).not_to include(
      "person@example.com",
      "123 Main Street",
      "127-129, Example Road",
      "private.jpg",
      long_quote
    )
    expect(content.redactions).to contain_exactly(
      "contact_information",
      "exact_address",
      "image",
      "long_quote"
    )
    expect(content).to have_attributes(
      content_kind: "article",
      adult_confirmed: true,
      theme_hint: "aftercare"
    )
  end
end

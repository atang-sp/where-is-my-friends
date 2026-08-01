# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::WikimediaClient do
  let(:pages) do
    [
      {
        page_id: 1_008_761,
        title: "Aftercare (BDSM)",
        sections: ["Overview", "Relational benefits"],
        theme_hint: "aftercare"
      }
    ]
  end

  it "returns a stable, licensed adult article excerpt through the source interface" do
    stub_request(:get, "https://en.wikipedia.org/w/api.php").with(
      query:
        hash_including(
          "action" => "query",
          "meta" => "siteinfo",
          "siprop" => "rightsinfo"
        )
    ).to_return(
      status: 200,
      body: {
        query: {
          rightsinfo: {
            text: "Creative Commons Attribution-ShareAlike License 4.0",
            url: "https://creativecommons.org/licenses/by-sa/4.0/deed.en"
          }
        }
      }.to_json
    )
    stub_request(:get, "https://en.wikipedia.org/w/api.php").with(
      query:
        hash_including(
          "action" => "parse",
          "page" => "Aftercare (BDSM)",
          "prop" => "text|sections|revid|displaytitle"
        )
    ).to_return(
      status: 200,
      body: {
        parse: {
          pageid: 1_008_761,
          revid: 1_362_273_067,
          displaytitle: "<span>Aftercare (BDSM)</span>",
          text: <<~HTML,
            <div class="mw-parser-output">
              <style>.unused { color: red; }</style>
              <div class="mw-heading mw-heading2"><h2 id="Overview">Overview</h2></div>
              <p>Adult participants may discuss what support they prefer.</p>
              <p>Water, a snack, rest, or quiet time may be welcome.</p>
              <div class="mw-heading mw-heading2"><h2 id="Emotional_benefits">Emotional benefits</h2></div>
              <p>This section is not selected.</p>
              <div class="mw-heading mw-heading2"><h2 id="Relational_benefits">Relational benefits</h2></div>
              <p><a href="/wiki/Communication">Communication</a> can include a later check-in.<sup class="reference">[1]</sup></p>
              <p>Preferences differ between people and sessions.</p>
              <figure><img src="example.jpg"></figure>
              <div class="mw-heading mw-heading2"><h2 id="References">References</h2></div>
              <p>This section is not selected either.</p>
            </div>
          HTML
          sections: [
            { index: "1", level: "2", line: "Overview", anchor: "Overview" },
            {
              index: "3",
              level: "2",
              line: "Relational benefits",
              anchor: "Relational_benefits"
            }
          ]
        }
      }.to_json
    )
    document = described_class.new(pages: pages).fetch(1_008_761)

    expect(document).to include(
      source_type: "wikimedia",
      content_kind: "article",
      adult_confirmed: true,
      theme_hint: "aftercare",
      question_id: 1_008_761,
      answer_id: 1_362_273_067,
      question_license: "CC BY-SA 4.0",
      answer_license: "CC BY-SA 4.0",
      question_author: "Wikipedia contributors",
      answer_author: "Wikipedia contributors",
      title: "Aftercare (BDSM)"
    )
    expect(document.fetch(:question_url)).to eq(
      "https://en.wikipedia.org/wiki/Aftercare_(BDSM)"
    )
    expect(document.fetch(:answer_url)).to eq(
      "https://en.wikipedia.org/w/index.php?title=Aftercare_%28BDSM%29&oldid=1362273067"
    )
    expect(document.fetch(:question_html)).to include(
      "Adult participants",
      "Water, a snack"
    )
    expect(document.fetch(:answer_html)).to include(
      "Communication can include",
      "Preferences differ"
    )
    expect(
      document.values_at(:question_html, :answer_html).join
    ).not_to include(
      "href=",
      'class="reference"',
      "<figure",
      "<img",
      "This section is not selected"
    )
  end

  it "returns no candidates when the source no longer declares CC BY-SA 4.0" do
    stub_request(:get, "https://en.wikipedia.org/w/api.php").with(
      query: hash_including("action" => "query", "siprop" => "rightsinfo")
    ).to_return(
      status: 200,
      body: {
        query: {
          rightsinfo: {
            text: "Different license",
            url: "https://example.com/license"
          }
        }
      }.to_json
    )

    expect { described_class.new(pages: pages).candidates }.to raise_error(
      WhereIsMyFriends::LicensedImport::SourceError
    )
  end
end

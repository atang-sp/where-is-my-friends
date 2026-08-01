# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::SpankingArtClient do
  let(:pages) do
    [
      {
        page_id: 1_232,
        revision_id: 152_283,
        slug: "Safeword",
        title: "Safeword",
        snapshot_at: "20250101070711",
        sections: ["__lead__", "Why safewords?"],
        theme_hint: "boundaries"
      }
    ]
  end
  let(:snapshot_url) do
    "https://web.archive.org/web/20250101070711id_/https://spankingart.org/wiki/Safeword"
  end
  let(:archive_html) { <<~HTML }
      <!doctype html>
      <html>
        <head>
          <script>
            window.RLCONF = {"wgArticleId":1232,"wgCurRevisionId":152283};
          </script>
        </head>
        <body>
          <div id="mw-content-text">
            <div class="mw-parser-output">
              <figure><img src="unsafe.jpg"><figcaption>Removed image</figcaption></figure>
              <p>A safeword is used in consensual adult spanking play.</p>
              <div class="toc">Navigation that is not article prose.</div>
              <h2><span class="mw-headline" id="Why_safewords.3F">Why safewords?</span></h2>
              <p>Partners can stop or pause immediately.</p>
              <p>Child participants are outside this adult-only excerpt.</p>
              <h2><span class="mw-headline" id="Links">Links</span></h2>
              <p>This section is not selected.</p>
              <div class="navbox">Template navigation is not selected.</div>
            </div>
          </div>
          <ul id="footer-info">
            <li id="footer-info-lastmod">This page was last edited on 19 April 2023.</li>
            <li id="footer-info-copyright">Content is available under <a href="https://gnu.org">GFDL</a> unless otherwise noted.</li>
          </ul>
        </body>
      </html>
    HTML

  it "returns a fixed adult-only GFDL excerpt through the licensed source interface" do
    stub_request(:get, snapshot_url).to_return(status: 200, body: archive_html)

    document = described_class.new(pages: pages).fetch(1_232)

    expect(document).to include(
      source_type: "spanking_art",
      content_kind: "article",
      adult_confirmed: true,
      theme_hint: "boundaries",
      question_id: 1_232,
      answer_id: 152_283,
      question_author: "Spanking Art Wiki contributors",
      answer_author: "Spanking Art Wiki contributors",
      question_license: "GFDL 1.3",
      answer_license: "GFDL 1.3",
      title: "Safeword",
      source_title: "Safeword"
    )
    expect(document.fetch(:question_url)).to eq(
      "https://spankingart.org/wiki/Safeword"
    )
    expect(document.fetch(:answer_url)).to eq(snapshot_url)
    expect(document.fetch(:source_history_url)).to eq(
      "https://spankingart.org/index.php?title=Safeword&action=history"
    )
    expect(document.fetch(:source_revision_url)).to eq(
      "https://spankingart.org/index.php?title=Safeword&oldid=152283"
    )
    expect(document.fetch(:question_html)).to include(
      "consensual adult spanking",
      "Why safewords?"
    )
    expect(document.fetch(:answer_html)).to include("stop or pause immediately")
    expect(
      document.values_at(:question_html, :answer_html).join
    ).not_to include(
      "Child participants",
      "Removed image",
      "Navigation that is not article prose",
      "This section is not selected",
      "Template navigation"
    )
  end

  it "rejects a changed revision or a snapshot without the page-level GFDL notice" do
    changed_revision =
      archive_html.sub('"wgCurRevisionId":152283', '"wgCurRevisionId":152284')
    stub_request(:get, snapshot_url).to_return(
      { status: 200, body: changed_revision },
      { status: 200, body: archive_html.sub("GFDL", "different license") }
    )
    client = described_class.new(pages: pages)

    expect { client.fetch(1_232) }.to raise_error(
      WhereIsMyFriends::LicensedImport::MissingSource
    )
    expect { client.fetch(1_232) }.to raise_error(
      WhereIsMyFriends::LicensedImport::SourceError
    )
  end
end

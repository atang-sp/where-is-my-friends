# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::StackExchangeClient do
  it "fetches only Interpersonal Skills questions and chooses the accepted answer" do
    stub_request(:get, %r{api\.stackexchange\.com/2\.3/questions\?}).to_return(
      status: 200,
      body: {
        items: [
          {
            question_id: 42,
            accepted_answer_id: 84,
            link:
              "https://interpersonal.stackexchange.com/questions/42/example",
            title: "How can I set a boundary?",
            body: "<p>Question body</p>",
            owner: {
              display_name: "Question Author"
            },
            content_license: "CC BY-SA 4.0",
            last_edit_date: 1_785_427_200
          }
        ],
        has_more: false
      }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )
    stub_request(
      :get,
      %r{api\.stackexchange\.com/2\.3/questions/42/answers\?}
    ).to_return(
      status: 200,
      body: {
        items: [
          {
            answer_id: 85,
            score: 100,
            link: "https://interpersonal.stackexchange.com/a/85",
            body: "<p>Higher score</p>",
            owner: {
              display_name: "Other Author"
            },
            content_license: "CC BY-SA 4.0"
          },
          {
            answer_id: 84,
            score: 10,
            link: "https://interpersonal.stackexchange.com/a/84",
            body: "<p>Accepted answer</p>",
            owner: {
              display_name: "Answer Author"
            },
            content_license: "CC BY-SA 4.0",
            last_edit_date: 1_785_513_600
          }
        ],
        has_more: false
      }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    candidate = described_class.new.candidates.first

    expect(candidate).to include(
      question_id: 42,
      answer_id: 84,
      answer_html: "<p>Accepted answer</p>",
      answer_author: "Answer Author",
      question_license: "CC BY-SA 4.0",
      answer_license: "CC BY-SA 4.0"
    )
    expect(candidate.fetch(:revised_at)).to eq(Time.zone.at(1_785_513_600))
  end
end

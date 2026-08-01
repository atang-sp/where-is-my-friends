# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImportsController do
  fab!(:user)
  fab!(:admin)

  it "exposes Chinese previews and aggregate controls only to administrators" do
    preview =
      WhereIsMyFriendsLicensedImport.create!(
        source_question_id: 42,
        status: "preview",
        theme: "boundaries",
        translated_title: "[英文精选·译文] 边界",
        translated_body: "只有管理员可见的中文预览",
        token_count: 123
      )

    sign_in(user)
    get "/where-is-my-friends/licensed-imports.json"
    expect(response.status).to eq(403)

    sign_in(admin)
    get "/where-is-my-friends/licensed-imports.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("previews").first).to include(
      "id" => preview.id,
      "translated_body" => "只有管理员可见的中文预览"
    )
    expect(response.parsed_body.keys).not_to include(
      "api_key",
      "openai_api_key",
      "moderation_provider"
    )
  end
end

# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::LicensedImport::Publisher do
  before { SiteSetting.tagging_enabled = true }

  it "creates one transparent system-authored topic with both required tags" do
    post =
      described_class.new.publish!(
        title: "[英文精选·译文] 如何设定边界",
        raw: "本主题由英文精选翻译机器人自动生成。\n\n这是经过复核的完整译文。",
        tags: %w[英文精选 安全与边界],
        source_question_id: 42
      )

    expect(post).to have_attributes(
      user_id: Discourse.system_user.id,
      post_number: 1
    )
    expect(post.topic).to have_attributes(
      archetype: Archetype.default,
      category_id: SiteSetting.uncategorized_category_id
    )
    expect(post.topic.tags.pluck(:name)).to contain_exactly("英文精选", "安全与边界")
    expect(
      post.topic.custom_fields["where_is_my_friends_licensed_import_source_id"]
    ).to eq(42)
  end
end

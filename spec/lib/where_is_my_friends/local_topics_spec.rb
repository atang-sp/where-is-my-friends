# frozen_string_literal: true
# rubocop:disable Discourse/Plugins/NamespaceMethods -- RSpec example-group helper.

RSpec.describe WhereIsMyFriends::LocalTopics do
  fab!(:user)
  fab!(:category) { Fabricate(:category, minimum_required_tags: 2) }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.where_is_my_friends_target_category_id = category.id
  end

  def add_area_group(parent_name, *area_names, target_category: category)
    parent = Tag.find_or_create_by!(name: parent_name)
    areas = area_names.map { |name| Tag.find_or_create_by!(name: name) }
    parent_group = Fabricate(:tag_group, tags: [parent], one_per_topic: true)
    area_group =
      Fabricate(
        :tag_group,
        parent_tag: parent,
        tags: areas,
        one_per_topic: true
      )
    CategoryTagGroup.create!(category: target_category, tag_group: parent_group)
    CategoryTagGroup.create!(category: target_category, tag_group: area_group)
  end

  it "composes Shanghai topics with the category's existing parent and area tags" do
    add_area_group("中国", "上海", "江苏")
    original_tag_count = Tag.count

    expect(described_class.compose_url("上海")).to eq(
      "/new-topic?category_id=#{category.id}&tags=%E4%B8%AD%E5%9B%BD,%E4%B8%8A%E6%B5%B7"
    )
    expect(Tag.count).to eq(original_tag_count)
  end

  it "returns only unambiguous topics in the target category with the required parent tag" do
    add_area_group("中国", "上海", "江苏", "浙江")
    china, shanghai, jiangsu, zhejiang =
      Tag
        .where(name: %w[中国 上海 江苏 浙江])
        .index_by(&:name)
        .values_at("中国", "上海", "江苏", "浙江")
    shanghai_topic =
      Fabricate(
        :topic,
        category: category,
        title: "Shanghai activity",
        tags: [china, shanghai]
      )
    jiangsu_topic =
      Fabricate(
        :topic,
        category: category,
        title: "Jiangsu activity",
        tags: [china, jiangsu]
      )
    Fabricate(
      :topic,
      category: Fabricate(:category),
      title: "Outside category",
      tags: [china, shanghai]
    )
    Fabricate(
      :topic,
      category: category,
      title: "Missing required parent",
      tags: [zhejiang]
    )
    Fabricate(
      :topic,
      category: category,
      title: "Ambiguous activity area",
      tags: [china, shanghai, jiangsu]
    )

    topics = described_class.new(user: user, city_keys: %w[上海 苏州 南京]).call

    expect(topics.pluck(:id)).to contain_exactly(
      shanghai_topic.id,
      jiangsu_topic.id
    )
    expect(topics.pluck(:activity_area)).to contain_exactly("上海", "江苏")
    expect(topics.flat_map(&:keys)).not_to include(:activity_city, :city_tag)
  end

  it "continues past a full page of newer invalid topics" do
    add_area_group("中国", "上海")
    china, shanghai =
      Tag.where(name: %w[中国 上海]).index_by(&:name).values_at("中国", "上海")
    valid_topic =
      Fabricate(
        :topic,
        category: category,
        title: "Older valid Shanghai activity",
        tags: [china, shanghai],
        bumped_at: 2.days.ago
      )
    101.times do |index|
      Fabricate(
        :topic,
        category: category,
        title: "Newer incomplete Shanghai activity #{index}",
        tags: [shanghai],
        bumped_at: 1.day.ago + index.minutes
      )
    end

    topics = described_class.new(user: user, city_keys: ["上海"]).call

    expect(topics.pluck(:id)).to eq([valid_topic.id])
  end

  it "preloads topic tags instead of querying once per topic" do
    add_area_group("中国", "上海")
    china, shanghai =
      Tag.where(name: %w[中国 上海]).index_by(&:name).values_at("中国", "上海")
    3.times do |index|
      Fabricate(
        :topic,
        category: category,
        title: "Shanghai activity #{index}",
        tags: [china, shanghai]
      )
    end

    sql = []
    subscriber =
      ActiveSupport::Notifications.subscribe(
        "sql.active_record"
      ) do |*, payload|
        next if payload[:name] == "SCHEMA" || payload[:cached]

        sql << payload[:sql]
      end

    begin
      described_class.new(user: user, city_keys: ["上海"]).call
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    tag_load_queries = sql.grep(/SELECT .*FROM "topic_tags".*topic_id" IN \(/)
    expect(tag_load_queries.length).to eq(1)
  end

  it "maps Chinese provinces and explicit international aliases to existing tag pairs" do
    add_area_group("中国", "江苏")
    add_area_group("日本", "东京都", "大阪府")
    add_area_group("北美", "美国")
    add_area_group("欧洲", "英国")
    add_area_group("大洋洲", "澳大利亚")

    expect(described_class.area_for("苏州")).to eq(parent: "中国", child: "江苏")
    expect(described_class.area_for("Tokyo")).to eq(parent: "日本", child: "东京都")
    expect(described_class.area_for("osaka")).to eq(parent: "日本", child: "大阪府")
    expect(described_class.area_for("new york")).to eq(
      parent: "北美",
      child: "美国"
    )
    expect(described_class.area_for("london")).to eq(parent: "欧洲", child: "英国")
    expect(described_class.area_for("sydney")).to eq(
      parent: "大洋洲",
      child: "澳大利亚"
    )
  end

  it "falls back to a category-only composer for an unmapped location or disabled tagging" do
    add_area_group("中国", "上海")
    original_tag_count = Tag.count

    expect(described_class.area_for("singapore")).to be_nil
    expect(described_class.compose_url("singapore")).to eq(
      "/new-topic?category_id=#{category.id}"
    )

    SiteSetting.tagging_enabled = false
    expect(described_class.compose_url("上海")).to eq(
      "/new-topic?category_id=#{category.id}"
    )
    expect(described_class.new(user: user, city_keys: ["上海"]).call).to eq([])
    expect(Tag.count).to eq(original_tag_count)
  end

  it "uses the legacy category slug only when the category id is not configured" do
    SiteSetting.where_is_my_friends_target_category_id = ""
    SiteSetting.where_is_my_friends_target_category_slug = category.slug

    expect(described_class.compose_url("singapore")).to eq(
      "/new-topic?category_id=#{category.id}"
    )

    SiteSetting.where_is_my_friends_target_category_slug = ""
    expect(described_class.compose_url("上海")).to be_nil
    expect(described_class.new(user: user, city_keys: ["上海"]).call).to eq([])
  end

  it "does not return topics from a target category the user cannot see" do
    private_category =
      Fabricate(
        :private_category,
        group: Group[:staff],
        permission_type: :full,
        minimum_required_tags: 2
      )
    SiteSetting.where_is_my_friends_target_category_id = private_category.id
    add_area_group("中国", "上海", target_category: private_category)
    china, shanghai =
      Tag.where(name: %w[中国 上海]).index_by(&:name).values_at("中国", "上海")
    Fabricate(
      :topic,
      category: private_category,
      title: "Private Shanghai activity",
      tags: [china, shanghai]
    )

    expect(described_class.new(user: user, city_keys: ["上海"]).call).to eq([])
  end

  it "recognizes only target-category topics with one child and its correct parent" do
    add_area_group("中国", "上海", "江苏")
    china, shanghai, jiangsu =
      Tag.where(name: %w[中国 上海 江苏]).index_by(&:name).values_at("中国", "上海", "江苏")
    valid =
      Fabricate(
        :topic,
        category: category,
        title: "Valid Shanghai activity",
        tags: [china, shanghai]
      )
    incomplete =
      Fabricate(
        :topic,
        category: category,
        title: "Incomplete Shanghai activity",
        tags: [shanghai]
      )
    ambiguous =
      Fabricate(
        :topic,
        category: category,
        title: "Ambiguous Shanghai activity",
        tags: [china, shanghai, jiangsu]
      )
    outside =
      Fabricate(
        :topic,
        category: Fabricate(:category),
        title: "Outside Shanghai activity",
        tags: [china, shanghai]
      )

    expect(described_class.local_topic?(valid)).to eq(true)
    expect(described_class.local_topic?(incomplete)).to eq(false)
    expect(described_class.local_topic?(ambiguous)).to eq(false)
    expect(described_class.local_topic?(outside)).to eq(false)
  end
end

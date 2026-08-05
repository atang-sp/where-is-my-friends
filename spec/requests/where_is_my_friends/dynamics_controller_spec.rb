# frozen_string_literal: true

RSpec.describe WhereIsMyFriends::DynamicsController do
  fab!(:user)

  before do
    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_dynamics_enabled = true
    user.change_trust_level!(TrustLevel[0])
    sign_in(user) unless RSpec.current_example.metadata[:anonymous]
  end

  it "returns an empty member feed when the protected, default-muted category is configured" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s

    expect(category).to be_read_restricted
    expect(category.category_groups.pluck(:group_id, :permission_type)).to eq(
      [[members.id, CategoryGroup.permission_types[:full]]]
    )
    expect(
      SiteSetting.default_categories_muted.split("|").map(&:to_i)
    ).to include(category.id)
    expect(Guardian.new(user).can_see?(category)).to eq(true)

    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to eq(
      "dynamics" => [],
      "has_more" => false,
      "before_id" => nil
    )
  end

  it "fails closed for anonymous viewers, disabled switches, or an unsafe category",
     :anonymous do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s

    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(403)

    sign_in(user)
    SiteSetting.where_is_my_friends_enabled = false
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(404)

    SiteSetting.where_is_my_friends_enabled = true
    SiteSetting.where_is_my_friends_dynamics_enabled = false
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(404)

    SiteSetting.where_is_my_friends_dynamics_enabled = true
    SiteSetting.where_is_my_friends_dynamics_category_id = ""
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(404)

    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = ""
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(404)

    SiteSetting.default_categories_muted = category.id.to_s
    category.update!(read_restricted: false)
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(404)

    category.update!(read_restricted: true)
    category.update!(minimum_required_tags: 1)
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(404)

    category.update!(minimum_required_tags: 0)
    category.category_groups.create!(
      group: Fabricate(:group),
      permission_type: CategoryGroup.permission_types[:full]
    )
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }
    expect(response.status).to eq(404)
  end

  it "creates a marked topic through normal posting validation without client metadata" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    raw = "今天完成了一个小目标，想听听大家最近在忙什么。"

    expect do
      post "/where-is-my-friends/dynamics.json",
           params: {
             raw: raw,
             title: "客户端标题",
             category: Fabricate(:category).id,
             tags: [Fabricate(:tag).name],
             username: Fabricate(:user).username
           }
    end.to change(Topic, :count).by(1)

    expect(response.status).to eq(200)
    topic = Topic.order(:id).last
    expect(topic).to have_attributes(user_id: user.id, category_id: category.id)
    expect(topic.custom_fields[WhereIsMyFriends::DynamicFeed::FIELD]).to eq(
      true
    )
    expect(topic.tags).to be_empty
    expect(topic.title).not_to eq("客户端标题")
    expect(topic.first_post.raw).to eq(raw)
    expect(response.parsed_body).to include(
      "queued" => false,
      "dynamic" =>
        include(
          "id" => topic.id,
          "reply_count" => 0,
          "author" => include("username" => user.username)
        )
    )

    get "/t/#{topic.id}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("where_is_my_friends_dynamic")).to eq(
      true
    )
  end

  it "preserves the dynamic marker when normal moderation queues and approves creation" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    SiteSetting.approve_post_count = 10

    expect do
      post "/where-is-my-friends/dynamics.json",
           params: {
             raw: "这条动态应进入论坛原生审核队列。"
           }
    end.not_to change(Topic, :count)

    expect(response.status).to eq(202)
    expect(response.parsed_body).to eq("queued" => true)
    reviewable = ReviewableQueuedPost.order(:id).last
    expect(reviewable.payload).to include(
      WhereIsMyFriends::DynamicFeed::INTERNAL_CREATION_PARAM.to_s => true
    )

    result =
      reviewable.perform(
        Fabricate(:moderator, refresh_auto_groups: true),
        :approve_post
      )
    expect(result.success?).to eq(true)
    topic = result.created_post.topic
    expect(topic.category_id).to eq(category.id)
    expect(topic.custom_fields[WhereIsMyFriends::DynamicFeed::FIELD]).to eq(
      true
    )
  end

  it "enforces visible length and rejects media while allowing an ordinary link" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    SiteSetting.min_first_post_length = 20

    [
      "七个字符呀呀呀",
      "字" * 501,
      "今天分享图片 ![说明](https://example.com/photo.jpg)",
      "今天分享引用图片 ![说明][photo]\n\n[photo]: https://example.com/photo.jpg",
      "今天分享 BBCode 图片 [img]https://example.com/photo.jpg[/img]",
      "今天分享附件 [文件](upload://abc123.pdf)",
      "今天分享附件 /uploads/default/original/1X/document.pdf",
      "今天分享附件 https://forum.example/uploads/default/document.pdf",
      "今天分享音频 <audio src=\"https://example.com/a.mp3\"></audio>",
      "今天分享嵌入内容 <iframe src=\"https://example.com\"></iframe>"
    ].each do |raw|
      expect do
        post "/where-is-my-friends/dynamics.json", params: { raw: raw }
      end.not_to change(Topic, :count)
      expect(response.status).to eq(422)
    end

    post "/where-is-my-friends/dynamics.json", params: { raw: "动态刚好八个字符" }
    expect(response.status).to eq(200)
    expect(Topic.order(:id).last.first_post.raw).to eq("动态刚好八个字符")

    post "/where-is-my-friends/dynamics.json",
         params: {
           raw: "今天读到一篇文章，链接在 https://example.com，推荐大家看看。"
         }

    expect(response.status).to eq(200)
    expect(Topic.order(:id).last.first_post.raw).to include(
      "https://example.com"
    )

    post "/where-is-my-friends/dynamics.json",
         params: {
           raw: "https://example.com/ordinary-link"
         }

    expect(response.status).to eq(200)
    cooked = Topic.order(:id).last.first_post.reload.cooked
    expect(cooked).to include('href="https://example.com/ordinary-link"')
    expect(cooked).not_to match(/onebox|<(?:img|video|audio|iframe)\b/)
  end

  it "reserves a locale-neutral unique suffix within reduced title limits" do
    SiteSetting.max_topic_title_length = 40
    at = Time.zone.parse("2026-08-03 12:34:56")

    first = WhereIsMyFriends::DynamicFeed.title_for("这是用于生成服务端标题的动态正文", at: at)
    second = WhereIsMyFriends::DynamicFeed.title_for("这是用于生成服务端标题的动态正文", at: at)

    expect(first.length).to be <= 40
    expect(first).to start_with("这是用于生成服务端标题")
    expect(first).to match(/260803\d{6}-[0-9a-f]{6}\z/)
    expect(second).not_to eq(first)
  end

  it "blocks the ordinary composer and protects dynamic edits and replies" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s

    post "/posts.json",
         params: {
           title: "普通发帖流程不能进入个人动态分区",
           raw: "这是一段足够长的普通主题正文。",
           category: category.id
         }
    expect(response.status).to eq(422)
    expect(Topic.where(category_id: category.id)).to be_empty

    post "/where-is-my-friends/dynamics.json",
         params: {
           raw: "这是通过动态发布器创建的正文内容。"
         }
    topic = Topic.order(:id).last
    first_post = topic.first_post
    original_title = topic.title

    expect do
      post "/posts.json", params: { topic_id: topic.id, raw: "这是一条正常的纯文字回复。" }
    end.to change { topic.posts.reload.count }.by(1)
    expect(response.status).to eq(200)

    expect do
      post "/posts.json",
           params: {
             topic_id: topic.id,
             raw: "回复不能包含 /uploads/default/original/1X/file.pdf"
           }
    end.not_to change(Post, :count)
    expect(response.status).to eq(422)

    post "/posts.json",
         params: {
           topic_id: topic.id,
           raw: "https://example.com/photo.jpg"
         }
    expect(response.status).to eq(200)
    cooked_reply = Post.order(:id).last.reload.cooked
    expect(cooked_reply).to include('href="https://example.com/photo.jpg"')
    expect(cooked_reply).not_to match(/onebox|<(?:img|video|audio|iframe)\b/)

    expect do
      post "/posts.json",
           params: {
             topic_id: topic.id,
             raw: "回复中夹带图片 ![说明](https://example.com/photo.jpg)"
           }
    end.not_to change(Post, :count)
    expect(response.status).to eq(422)

    put "/posts/#{first_post.id}.json",
        params: {
          post: {
            raw: "编辑后夹带附件 [文件](upload://abc123.pdf)"
          }
        }
    expect(response.status).to eq(422)
    expect(first_post.reload.raw).to eq("这是通过动态发布器创建的正文内容。")

    other_category = Fabricate(:category)
    attempted_tag = Fabricate(:tag)
    source_topic_count = category.reload.topic_count
    target_topic_count = other_category.reload.topic_count
    SiteSetting.where_is_my_friends_dynamics_enabled = false
    SiteSetting.where_is_my_friends_dynamics_category_id = ""
    put "/posts/#{first_post.id}.json",
        params: {
          title: "这是普通成员试图手动篡改的动态标题",
          tags: [attempted_tag.name],
          post: {
            raw: "这是编辑后的纯文字动态正文。",
            category_id: other_category.id
          }
        }
    expect(response.status).to eq(200)
    expect(topic.reload.category_id).to eq(category.id)
    expect(topic.title).not_to eq(original_title)
    expect(topic.title).to include("这是编辑后的纯文字动态正文")
    expect(topic.tags).to be_empty
    expect(first_post.reload.raw).to eq("这是编辑后的纯文字动态正文。")
    expect(category.reload.topic_count).to eq(source_topic_count)
    expect(other_category.reload.topic_count).to eq(target_topic_count)
    revision = PostRevision.where(post_id: first_post.id).order(:number).last
    if revision
      expect(revision.modifications.keys).not_to include(
        "title",
        "category_id",
        "tags"
      )
    end
  end

  it "paginates a member feed by id without returning hidden or deleted dynamics" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    topics =
      24.times.map do |index|
        create_dynamic.call(
          category: category,
          author: user,
          raw: "第 #{index + 1} 条个人动态正文",
          created_at: index.minutes.ago
        )
      end
    topics[0].update!(deleted_at: Time.current)
    topics[1].first_post.update_columns(hidden: true)

    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }

    first_page = response.parsed_body
    expect(response.status).to eq(200)
    expect(first_page.fetch("dynamics").length).to eq(20)
    expect(first_page.fetch("has_more")).to eq(true)
    expect(first_page.fetch("dynamics").pluck("id")).to eq(
      topics.drop(2).map(&:id).sort.reverse.first(20)
    )

    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username,
          before_id: first_page.fetch("before_id")
        }

    second_page = response.parsed_body
    expect(second_page.fetch("dynamics").pluck("id")).to eq(
      topics.drop(2).map(&:id).sort.reverse.drop(20)
    )
    expect(second_page).to include("has_more" => false, "before_id" => nil)
  end

  it "returns at most one recent dynamic per non-ignored author in strict creation order" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    SiteSetting.where_is_my_friends_dynamics_homepage_enabled = true
    first_author = Fabricate(:user, refresh_auto_groups: true)
    second_author = Fabricate(:user, refresh_auto_groups: true)
    third_author = Fabricate(:user, refresh_auto_groups: true)
    ignored_author = Fabricate(:user, refresh_auto_groups: true)
    newest =
      create_dynamic.call(
        category: category,
        author: first_author,
        raw: "第一位作者最新动态正文",
        created_at: 1.hour.ago
      )
    create_dynamic.call(
      category: category,
      author: first_author,
      raw: "第一位作者较早动态正文",
      created_at: 2.hours.ago
    )
    second =
      create_dynamic.call(
        category: category,
        author: second_author,
        raw: "第二位作者最新动态正文",
        created_at: 3.hours.ago
      )
    third =
      create_dynamic.call(
        category: category,
        author: third_author,
        raw: "第三位作者最新动态正文",
        created_at: 4.hours.ago
      )
    create_dynamic.call(
      category: category,
      author: ignored_author,
      raw: "被忽略作者的动态正文",
      created_at: 30.minutes.ago
    )
    create_dynamic.call(
      category: category,
      author: Fabricate(:user, refresh_auto_groups: true),
      raw: "超过三十天的动态正文",
      created_at: 31.days.ago
    )
    Fabricate(:ignored_user, user: user, ignored_user: ignored_author)

    get "/where-is-my-friends/dynamics/recent.json"

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("dynamics").pluck("id")).to eq(
      [newest.id, second.id, third.id]
    )
  end

  it "returns a paginated, author-diverse feed of other members' recent dynamics" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    authors = Array.new(11) { Fabricate(:user, refresh_auto_groups: true) }
    dynamics =
      authors.each_with_index.map do |author, index|
        create_dynamic.call(
          category: category,
          author: author,
          raw: "推荐流中的第 #{index + 1} 条动态正文",
          created_at: (index + 1).minutes.ago
        )
      end
    own_dynamic =
      create_dynamic.call(
        category: category,
        author: user,
        raw: "当前用户自己的动态不应进入他人推荐流",
        created_at: 30.seconds.ago
      )
    ignored_author = Fabricate(:user, refresh_auto_groups: true)
    ignored_dynamic =
      create_dynamic.call(
        category: category,
        author: ignored_author,
        raw: "被忽略成员的动态不应进入推荐流",
        created_at: 2.minutes.ago
      )
    Fabricate(:ignored_user, user: user, ignored_user: ignored_author)

    get "/where-is-my-friends/dynamics/feed.json"

    first_page = response.parsed_body
    expect(response.status).to eq(200)
    expect(first_page.fetch("dynamics").length).to eq(10)
    expect(first_page.fetch("dynamics").pluck("id")).to eq(
      dynamics
        .first(10)
        .sort_by { |topic| [topic.created_at, topic.id] }
        .reverse
        .pluck(:id)
    )
    expect(
      first_page.fetch("dynamics").pluck("author").pluck("id").uniq.length
    ).to eq(10)
    expect(first_page.fetch("dynamics").pluck("id")).not_to include(
      own_dynamic.id,
      ignored_dynamic.id
    )
    expect(first_page.fetch("has_more")).to eq(true)

    get "/where-is-my-friends/dynamics/feed.json",
        params: {
          before_id: first_page.fetch("before_id")
        }

    expect(response.status).to eq(200)
    expect(response.parsed_body.fetch("dynamics").pluck("id")).to eq(
      [dynamics.last.id]
    )
    expect(response.parsed_body).to include(
      "has_more" => false,
      "before_id" => nil
    )
  end

  it "fails closed when the homepage dynamics feed is disabled" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    SiteSetting.where_is_my_friends_dynamics_feed_enabled = false

    get "/where-is-my-friends/dynamics/feed.json"

    expect(response.status).to eq(404)
  end

  it "keeps marked dynamics out of ordinary latest and user topic lists" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    dynamic =
      create_dynamic.call(
        category: category,
        author: user,
        raw: "只应出现在个人动态专用列表里的正文"
      )
    normal =
      Fabricate(:topic, user: user, title: "A normal visible discussion topic")
    Fabricate(:post, topic: normal, user: user)

    SiteSetting.default_categories_muted = ""
    latest_ids =
      TopicQuery.new(user, per_page: 100).list_latest.topics.map(&:id)
    expect(latest_ids).to include(normal.id)
    expect(latest_ids).not_to include(dynamic.id)

    get "/topics/created-by/#{user.username}.json"
    created_ids = response.parsed_body.dig("topic_list", "topics").pluck("id")
    expect(created_ids).to include(normal.id)
    expect(created_ids).not_to include(dynamic.id)
  end

  it "loads member previews with a query count independent of author count" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    authors = Array.new(3) { Fabricate(:user, refresh_auto_groups: true) }
    authors.each_with_index do |author, index|
      create_dynamic.call(
        category: category,
        author: author,
        raw: "用于验证批量加载的第 #{index + 1} 条动态正文"
      )
    end

    queries_for =
      lambda do |ids|
        feed = WhereIsMyFriends::DynamicFeed.new(viewer: User.find(user.id))
        ActiveRecord::Base.uncached do
          track_sql_queries { feed.latest_by_user_ids(ids) }
        end
      end

    many_queries = queries_for.call(authors.map(&:id))
    fewer_queries = queries_for.call(authors.first(2).map(&:id))
    expect(many_queries.length).to eq(fewer_queries.length)
  end

  it "respects the core name privacy setting in serialized dynamics" do
    members = Group.find(Group::AUTO_GROUPS[:trust_level_0])
    category = Fabricate(:private_category, group: members)
    SiteSetting.where_is_my_friends_dynamics_category_id = category.id
    SiteSetting.default_categories_muted = category.id.to_s
    dynamic =
      create_dynamic.call(
        category: category,
        author: user,
        raw: "用于检查姓名隐私设置的动态正文"
      )

    SiteSetting.enable_names = false
    get "/where-is-my-friends/dynamics.json",
        params: {
          username: user.username
        }

    item =
      response
        .parsed_body
        .fetch("dynamics")
        .find { |entry| entry["id"] == dynamic.id }
    expect(item.fetch("author")).not_to have_key("name")
  end

  let(:create_dynamic) do
    lambda do |category:, author:, raw:, created_at: Time.current|
      topic =
        Fabricate(
          :topic,
          category: category,
          user: author,
          created_at: created_at,
          bumped_at: created_at
        )
      topic.custom_fields[WhereIsMyFriends::DynamicFeed::FIELD] = true
      topic.save_custom_fields
      Fabricate(
        :post,
        topic: topic,
        user: author,
        raw: raw,
        cooked: PrettyText.cook(raw),
        created_at: created_at
      )
      topic.update_columns(posts_count: 1, highest_post_number: 1)
      topic
    end
  end
end

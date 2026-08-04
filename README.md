# Local Friends — Discourse 社区发现插件

Local Friends 帮助成员真正“看见论坛里有哪些人”：新成员可通过私密的兴趣冷启动，立即得到可解释的话题和成员推荐；也可以用“城市”发现同城用户，再按需启用 GPS 或地图位置来显示宽泛的距离范围。

## 核心体验

- 首页常驻社区发现：完成兴趣设置后，话题列表页持续展示 3 个现在值得参与的讨论、3 位拥有共同语境的成员和 2 个兴趣入口；支持换一批和逐项“不感兴趣”。
- 个人动态 MVP：登录会员可在原生个人 Activity 页发布 8–500 字纯文字近况，复用 Discourse 主题完成回复、通知、举报和审核；首页第四栏与成员卡摘要都由独立开关分阶段启用。
- 细分兴趣目录：从互动类型、强度、角色、感受、附加元素、工具、部位、内容和交流方式中选择 3–12 项，立即看到最多 5 个话题和 6 位成员。
- 可参与性排序：新鲜、未读、回复较少、作者活跃和开放式讨论优先；已回复、长期无人参与以及同一作者集中出现会降权，点赞数只作为最后的同分信号。
- 相似兴趣匹配：完全相同的选择优先，也会识别相邻兴趣；参与推荐的成员即使尚未发过相关帖子，也可以互相发现。
- 相关话题映射：目录由插件维护，不依赖论坛当下有多少标签；已有 `spank`、`训诫`、`小说`、`sp飞行棋` 等标签和公开话题可通过别名、标签及标题关键词关联。
- 可解释推荐：话题显示匹配兴趣，成员推荐只引用用户可见的公开贡献和代表话题。
- 一对一实践邀请：从推荐卡或公开兴趣资料页选择共同兴趣，可附建议时间和备注；接受后只创建两人私信。
- 可控收件箱：收件人可接受、拒绝或忽略邀请，也可在通知设置中完全关闭实践邀请。
- 旧数据接管：近 90 天旧实践意向只迁移为私密、待重新确认的书签；既有互选只保留为静默历史。
- 用户控制：可跳过、编辑、“不感兴趣”、退出被推荐、公开兴趣或一键清空个性化数据。
- 城市优先：本地发现只需填写城市，保存后自动加载同城成员。
- 可选精确模式：GPS 或地图只用于生成“约 5 公里内 / 5–20 公里 / 20 公里以上”等距离范围。
- 连接闭环：成员卡片可进入主页、发私信；空状态可搜索本地话题。
- 明确状态：覆盖首次设置、加载、结果、空结果和错误状态。
- 控制权：用户可更新城市或立即删除位置；位置不会由插件自动过期，分析事件仍在 90 天后删除。
- 隐私统计：只记录白名单事件、位置模式和粗粒度结果桶；事件 90 天后删除。
- 许可英文精选：安全地将 Interpersonal Skills Stack Exchange 的一篇完整问答翻译为中文；默认只生成管理员预览，校验未全部通过时绝不发帖。

## 社区发现排序与衡量

`participation_v1` 使用可解释规则作为第一版基线：明确兴趣匹配 32%、最近阅读/点赞/回复行为 18%、可参与性 18%、新鲜度 12%、关系桥接 10%、新成员扶持 5%、相邻探索 5%，再扣除已读、已回复、累计阅读时间较长、长期无人参与和同作者集中等惩罚。五个讨论候选采用“3 个高度相关 + 1 个等待回应 + 1 个相邻探索”的混排；缺少某类安全可见候选时才按总分补位。换一批只在排序靠前的安全候选池内轮换讨论、成员和兴趣入口，不会用低相关结果制造变化。

成员卡展示共同兴趣、最多两篇相关公开内容和当前可用行动；兴趣入口只进入经过标签筛选的公开讨论列表，活跃成员数低于配置的隐私阈值时只显示通用说明。刷新、打开和“不感兴趣”都不会订阅标签、改变通知级别或绕过现有权限、屏蔽、静音与成员 opt-in 边界。

首页和兴趣页会记录 `surface`、`recommendation_group`、`candidate_source`、`rank_bucket`、`algorithm_version` 与 `result_bucket`。这些事件不保存话题、成员或兴趣目标 ID，也不保存内容。推荐北极星指标是“看过推荐的用户中，七日内产生公开发帖或回复的比例”；同时聚合推荐面板展开/收起、分组切换、刷新、各分组展示到打开和不感兴趣，以及同城入口的展示、打开、保存城市和关闭漏斗。

七日参与、首次回复、插件回访和内容响应率只用已经走完整个七日观察窗的成熟 cohort 计算，尚未成熟的用户或话题单独列为 `in_progress`；推荐成熟 cohort 只纳入带 `recommendation_group` 的新版曝光。原有顶层曝光后 24 小时回复率和七日兼容键也映射到同一成熟 cohort，不再混入未成熟样本。24 小时回复率同样只用已走完 24 小时的曝光。旧版插件回访指标仍以本插件记录的 `page_view` 为准，不代表全站回访；新增的动态发布者、回复者、打开者和同期普通公开内容参与者七日回访明确使用 Discourse `UserVisit`，代表全站自然日访问。内容供给统计公开可见、非受限分区的主题，并区分人工原创、许可导入、人工作者/回复者和七日内获得人工回复的成熟主题。

## 隐私边界

- 城市模式的数据库记录不包含经纬度。
- GPS 坐标只在位置 POST 中发送；服务端添加约 ±0.005° 的随机偏移后保存。
- 地图模式保存用户主动选择的点，建议选择公共区域。
- API、HTML、前端状态和日志均不返回或记录任何用户坐标、精确距离或任意自定义字段。
- 查找接口忽略客户端搜索坐标，只使用当前登录用户已保存的服务端记录。
- 用户列表只显示同城用户；两边都有精确模式时才返回粗粒度距离范围。
- 插件不调用 IP 定位或 Nominatim 逆地理编码。
- 活跃人数低于隐私阈值时不会返回精确总数。
- 兴趣、使用目的和“不感兴趣”记录默认私密；只有用户主动勾选后，所选兴趣才显示在资料卡。
- 推荐只使用当前用户原本有权查看的话题；私密分区、静音标签/分区、双方任一方向的忽略或静音关系都会被排除。
- 成员的私密选择不会作为字段返回；推荐理由只展示查看者自己的匹配兴趣。隐藏帖子不会成为成员推荐证据。
- 实践邀请必须有当前可验证的共同兴趣，并同时经过信任等级、每日额度、双方忽略/静音、私信白名单与权限和收件人 opt-out 检查；接受时会再次验证通信安全。
- 每条邀请只有一个发起者和一个收件人；接受时创建的私信只包含这两人。
- 建议时间按发送者浏览器时区转换为 UTC；邀请保留兴趣名称快照，管理员后续删除标签不会破坏历史。
- 旧意向书签只向原意向所有者返回；迁移、重新确认和历史互选导入都不会自动发送邀请或通知。
- 只有明确允许“被推荐”且近期活跃的成员才会出现；不会暴露对方的私密兴趣或使用目的。
- 插件绝不自动订阅标签、分区，也不会改变任何通知级别。
- 个人动态只存在于仅登录会员可读、默认静音的专用分区；功能配置不合格时接口 fail closed。动态及回复在安全上传落地前拒绝图片、音视频和附件，且动态不会进入普通 Latest、用户“主题”页或讨论推荐。
- 七日公开互动率和首次回复率直接从公开帖子按 onboarding 或推荐曝光时间窗聚合；私信、受限分区、内容和目标 ID 均不会进入统计结果。
- 英文原文只在单次任务内存中存在，不写插件数据库或日志；数据库只保存来源、许可、失败代码、token 用量和通过校验的中文内容。模型 API 密钥与 Discourse AI 的 `AiSecret` 一样由数据库保存；管理接口只返回“已配置”状态，绝不返回密钥，日志也会过滤密钥参数。数据库管理员和数据库备份仍可读取密钥。发送给模型供应商的内容已经过许可校验和隐私清理；供应商的数据保留、日志和缓存政策需由管理员单独确认。

管理员调试端点 `/where-is-my-friends/debug-stats.json` 只对管理员开放，且只返回聚合数据。响应包含统计起止时间、原有位置与推荐漏斗、推荐分组和面板操作、同城入口漏斗、成熟 cohort、公开内容供给、动态供给/回复/发现/全站回访，以及按自然日汇总的发现和内容趋势。可通过 `?days=7`、`?days=30` 或 `?days=90` 选择统计窗口；其他值安全回退到 30 天。完整口径和上线观察方法见 [增长可观测性口径](docs/plans/2026-08-02-growth-observability.md)。

## 安装与升级

将仓库放入 Discourse 的 `plugins/where-is-my-friends`，然后在 Discourse 根目录运行：

```bash
bundle exec rake db:migrate
```

重启 Discourse 后，在管理后台确认 `where_is_my_friends_enabled`、`where_is_my_friends_interest_onboarding_enabled` 与 `where_is_my_friends_practice_invitations_enabled` 已启用。插件会安装内置细分兴趣目录；管理员还可额外配置最多 20 个论坛标签。目录关系和话题映射维护在 `config/interest_catalogue.yml`。

个人动态必须先由管理员创建只授予 `trust_level_0` 完整权限、加入 `default_categories_muted` 的受限分区，再设置 `where_is_my_friends_dynamics_category_id`。三个动态开关默认开启，但在分区校验通过前接口仍会 fail closed。上线验收、匿名验证和数据保留回滚见 [个人动态上线手册](docs/plans/2026-08-03-personal-dynamics-rollout.md)。该流程不创建标签。

若数据库仍有旧插件的 `practice_interests` 表，post-migrate 会幂等导入：近 90 天记录成为 `needs_reconfirmation` 私密书签，所有双向记录成为 `notification_suppressed` 历史配对。导入不会创建 `WhereIsMyFriendsPracticeInvitation` 或 `Notification`。部署顺序与回滚检查见 [实践邀请上线手册](docs/plans/2026-07-28-practice-invitations-rollout.md)。

许可英文精选的模型供应商可在插件管理页配置 Responses API 或 OpenAI-compatible Chat Completions 的 Base URL、模型和 API 密钥；Chat Completions 可选择严格 JSON Schema，或供应商兼容性更广的 JSON object 加本地严格校验。同一个模型网关负责范围分类、翻译和独立复核，不需要单独的 OpenAI Moderation 凭据。供应商密钥可直接在后台轮换，无需环境变量或重建；旧的 DeepSeek/OpenAI 供应商密钥环境变量不会被读取。许可来源包括 Interpersonal Skills Stack Exchange 完整问答，以及程序白名单中的 Wikipedia 成人 SP 教育章节；后者会实时验证站点许可并署名到固定修订版本。首次启用必须保持 `licensed_import_dry_run=true`；完整配置、三天预览、人工抽查、公开发布、自动暂停和事故处理步骤见 [英文精选上线手册](docs/plans/2026-07-31-licensed-english-import-rollout.md)。

本版本在 Discourse `2026.7.0-latest`（commit `7c06c152`）上开发和验证，插件元数据要求 Discourse `2026.7.0.beta1` 或更高版本。

## 设置

| 设置 | 默认值 | 说明 |
| --- | --- | --- |
| `where_is_my_friends_enabled` | `true` | 启用插件 |
| `where_is_my_friends_interest_onboarding_enabled` | `true` | 启用一次性兴趣冷启动和个性化推荐 |
| `where_is_my_friends_interest_tags` | 空 | 在内置兴趣目录之外补充的论坛标签，最多 20 个 |
| `where_is_my_friends_dynamics_enabled` | `true` | 启用个人 Activity 动态页和发布接口；分区不合格时仍 fail closed |
| `where_is_my_friends_dynamics_homepage_enabled` | `true` | 启用首页折叠发现面板的第四个“动态”分组 |
| `where_is_my_friends_dynamics_member_preview_enabled` | `true` | 在成员推荐卡上批量附加一条 30 天内动态摘要，不改变排名 |
| `where_is_my_friends_dynamics_category_id` | 空 | 仅 `trust_level_0` 可读写且加入默认静音的专用分区 |
| `where_is_my_friends_practice_invitations_enabled` | `true` | 启用严格一对一实践邀请 |
| `where_is_my_friends_practice_invitation_min_trust_level` | `1` | 允许发送邀请的最低信任等级 |
| `where_is_my_friends_practice_invitation_daily_limit` | `5` | 每位成员每天最多发送的邀请数 |
| `where_is_my_friends_enable_virtual_location` | `true` | 允许可选 GPS/地图距离范围 |
| `where_is_my_friends_map_provider` | `openstreetmap` | `openstreetmap`、`amap` 或 `baidu` |
| `where_is_my_friends_amap_api_key` | 空 | 仅在选择高德时发送到浏览器 |
| `where_is_my_friends_baidu_api_key` | 空 | 仅在选择百度时发送到浏览器 |
| `where_is_my_friends_max_users_display` | `50` | 返回用户上限，服务端限制为 10–200 |
| `where_is_my_friends_aggregate_privacy_threshold` | `3` | 显示精确活跃人数的最低参与者数量 |
| `where_is_my_friends_target_category_id` | 空 | “实践交友”目标分区；本地话题只复用该分区标签组中已有的父子地域标签，且不会创建标签 |
| `where_is_my_friends_target_category_slug` | 空 | 兼容旧配置的分区 slug；仅在目标分区 ID 未配置时使用 |
| `licensed_import_enabled` | `false` | 英文精选总开关；所有失败和暂停条件均以关闭此开关结束 |
| `licensed_import_dry_run` | `true` | 只保存管理员可见中文预览，不创建主题 |
| `licensed_import_category_id` | 空 | 公开英文精选主题的目标分区；公开运行前必须选择成员可读的非“未分类”分区 |
| `licensed_import_interval_hours` | `24` | 两篇之间的最短间隔，后台最小值为 24 小时 |
| `licensed_import_publish_hour` | `20` | 北京时间执行小时 |
| `licensed_import_monthly_token_budget` | `1500000` | 每月生成调用的 token 上限 |
| `licensed_import_max_per_day` | `1` | 每天最多一篇，固定为 1 |

OpenStreetMap 无需密钥，是默认回退。高德和百度 key 是公开的浏览器 key，必须在供应商控制台限制到论坛域名；插件只把当前选中供应商的 key 发给客户端。详见 [VIRTUAL_LOCATION_GUIDE.md](VIRTUAL_LOCATION_GUIDE.md)。

## API

所有端点都要求登录且受插件开关保护：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `GET` | `/where-is-my-friends.json` | 当前状态、无坐标位置元数据和客户端设置 |
| `POST` | `/where-is-my-friends/locations.json` | 保存城市、GPS 或地图模式 |
| `GET` | `/where-is-my-friends/locations/nearby.json` | 使用服务端已保存位置查找同城成员 |
| `DELETE` | `/where-is-my-friends/locations.json` | 删除当前用户位置 |
| `GET` | `/where-is-my-friends/recommendations.json` | 私密偏好、可见兴趣目录、算法版本、讨论/成员推荐和兴趣入口；可传 `refresh` 生成一轮多样性顺序 |
| `GET` | `/where-is-my-friends/dynamics.json?username=...&before_id=...` | 读取某成员的动态，每页 20 条并显式返回较早分页游标 |
| `POST` | `/where-is-my-friends/dynamics.json` | 当前用户通过正常 Discourse 发帖/审核链路创建纯文字动态；只接受 `raw` |
| `GET` | `/where-is-my-friends/dynamics/recent.json` | 首页第四栏读取最近 30 天、作者去重、最多 3 条动态 |
| `PUT` | `/where-is-my-friends/recommendations/profile.json` | 保存兴趣、目的与隐私选项 |
| `DELETE` | `/where-is-my-friends/recommendations/profile.json` | 关闭并清空个性化数据 |
| `POST` | `/where-is-my-friends/recommendations/skip.json` | 跳过一次性引导 |
| `POST` | `/where-is-my-friends/recommendations/dismiss.json` | 对当前可见推荐标记“不感兴趣” |
| `GET` | `/where-is-my-friends/practice-invitations.json` | 当前用户的私密收件箱和发件记录 |
| `GET/POST/PUT/DELETE` | `/where-is-my-friends/admin/ai-provider-profiles...` | 仅管理员可用的供应商配置、测试和激活 API；任何响应都不含密钥 |
| `GET` | `/where-is-my-friends/practice-invitations/availability.json` | 查询某资料页成员当前可用的共同兴趣 |
| `POST` | `/where-is-my-friends/practice-invitations.json` | 创建严格一对一邀请 |
| `PUT` | `/where-is-my-friends/practice-invitations/:id/accept.json` | 收件人接受并创建两人私信 |
| `PUT` | `/where-is-my-friends/practice-invitations/:id/decline.json` | 收件人拒绝邀请 |
| `PUT` | `/where-is-my-friends/practice-invitations/:id/ignore.json` | 收件人忽略邀请 |
| `GET` | `/where-is-my-friends/legacy-practice-bookmarks.json` | 当前用户自己的旧意向书签 |
| `PUT` | `/where-is-my-friends/legacy-practice-bookmarks/:id/reconfirm.json` | 仅重新确认书签，不发送邀请 |
| `PUT` | `/where-is-my-friends/legacy-practice-bookmarks/:id/dismiss.json` | 移除旧意向书签 |
| `POST` | `/where-is-my-friends/events.json` | 写入白名单漏斗或无目标 ID 的粗粒度推荐曝光/行动事件 |
| `GET` | `/where-is-my-friends/debug-stats.json` | 管理员聚合诊断 |
| `GET` | `/where-is-my-friends/licensed-imports.json` | 管理员预览、失败原因、token 用量与互动门槛状态；不返回密钥或英文原文 |

## 开发和验证

把插件放在当前 Discourse checkout 下，然后运行：

```bash
d/rake db:migrate
RAILS_ENV=test d/rake db:migrate
d/rake 'plugin:spec[where-is-my-friends]'
CI=1 d/rake 'plugin:qunit[where-is-my-friends]'
d/exec bin/lint plugins/where-is-my-friends
```

`CI=1` 让容器内的 Chromium 使用无沙箱测试参数。真实浏览器端到端测试见 `e2e/README.md`。

## 主要目录

- `lib/where_is_my_friends/recommendation_engine.rb`：权限安全、可解释、以参与为目标的话题/成员/兴趣入口推荐。
- `lib/where_is_my_friends/dynamic_feed.rb`：个人动态的配置校验、创建、权限过滤、分页、最近作者去重、批量成员摘要和序列化唯一策略入口。
- `lib/where_is_my_friends/dynamic_metrics.rb`：动态成熟作者、七日回复、入口漏斗和基于 `UserVisit` 的全站回访聚合。
- `lib/where_is_my_friends/growth_report.rb`：管理员可见的漏斗、成熟 cohort、内容供给和按日趋势聚合。
- `lib/where_is_my_friends/licensed_import/`：许可校验、内容清理、安全分类、忠实翻译、独立复核、发布和自动停发。
- `lib/where_is_my_friends/practice_invitation_eligibility.rb`：共同兴趣、信任、屏蔽、opt-out 和私信权限策略。
- `app/models/where_is_my_friends_practice_invitation.rb`：严格一对一邀请与接受后的私信引用。
- `app/models/where_is_my_friends_legacy_practice_bookmark.rb`：仅所有者可见、需要重新确认的迁移书签。
- `app/models/where_is_my_friends_interest_profile.rb`：私密兴趣、目的与用户控制。
- `app/models/user_location.rb`：城市标准化、有效期和距离范围。
- `app/controllers/where_is_my_friends/`：认证后的发现和事件 API。
- `assets/javascripts/discourse/components/`：原生 Glimmer/GJS 页面和模态框。
- `spec/`：模型、请求和定时任务测试。
- `test/javascripts/`：QUnit 验收和单元测试。

## 许可证

插件代码采用 MIT License。随插件分发的 Leaflet 1.9.4 使用其 BSD-2-Clause 风格许可证，文本见 `public/leaflet-LICENSE.txt`。

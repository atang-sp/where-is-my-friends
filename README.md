# Local Friends — Discourse 社区发现插件

Local Friends 帮助成员真正“看见论坛里有哪些人”：新成员可通过私密的兴趣冷启动，立即得到可解释的话题和成员推荐；也可以用“城市”发现同城用户，再按需启用 GPS 或地图位置来显示宽泛的距离范围。

## 核心体验

- 首页“今天可以做什么”：登录成员每次只看到一个适合当前阶段的主要行动；完整的话题、成员、兴趣和动态推荐仍可从兴趣推荐页查看、换一批和逐项“不感兴趣”。
- 个人动态 MVP：登录会员可在原生个人 Activity 页发布 8–500 字文字近况并使用 Discourse 原生表情选择器，复用主题完成回复、通知、举报和审核；“今日行动”可以指向一条安全可见的近期动态，关闭新入口后恢复原首页动态推荐流，完整动态页和成员卡摘要仍由独立开关控制。
- 细分兴趣目录：从互动类型、强度、角色、感受、附加元素、工具、部位、内容和交流方式中选择 3–20 项，立即看到最多 5 个话题和 6 位成员。
- 可参与性排序：新鲜、未读、回复较少、作者活跃和开放式讨论优先；已回复、长期无人参与以及同一作者集中出现会降权，点赞数只作为最后的同分信号。
- 相似兴趣匹配：完全相同的选择优先，也会识别相邻兴趣；参与推荐的成员即使尚未发过相关帖子，也可以互相发现。
- 相关话题映射：目录由插件维护，不依赖论坛当下有多少标签；已有 `spank`、`训诫`、`小说`、`sp飞行棋` 等标签和公开话题可通过别名、标签及标题关键词关联。
- 可解释推荐：话题显示匹配兴趣，成员推荐只引用用户可见的公开贡献和代表话题。
- 一对一实践邀请：从推荐卡或公开兴趣资料页选择共同兴趣，可附建议时间和备注；接受后只创建两人私信。
- 印象标签：成员可向他人提议自由文本标签，被标签人批准后才公开，其他成员可公开赞同；提议人匿名，被标签人可移除或关闭接收；入口覆盖同城发现、首页社区发现与兴趣推荐三处成员卡片。
- 可控收件箱：收件人可接受、拒绝或忽略邀请，也可在通知设置中完全关闭实践邀请。
- 旧数据接管：近 90 天旧实践意向只迁移为私密、待重新确认的书签；既有互选只保留为静默历史。
- 用户控制：可跳过、编辑、“不感兴趣”、退出被推荐、公开兴趣或一键清空个性化数据。
- 城市优先：本地发现只需填写城市，保存后自动加载同城成员。
- 可选精确模式：GPS 或地图只用于生成“约 5 公里内 / 5–20 公里 / 20 公里以上”等距离范围。
- 连接闭环：成员卡片可进入主页、发私信；空状态可发起本地话题，也可浏览已有本地话题。
- 飞行棋成就：房间服务签发完成凭证，登录成员可选择是否认领并控制成就是否显示在论坛资料中；子功能关闭时认领和资料更新接口均不可用。
- 明确状态：覆盖首次设置、加载、结果、空结果和错误状态。
- 控制权：用户可更新城市或立即删除位置；位置不会由插件自动过期，分析事件仍在 90 天后删除。
- 隐私统计：只记录白名单事件、位置模式和粗粒度结果桶；事件 90 天后删除。
- 许可英文精选：新发布严格限制为五个已经核对的 Spanking Art Wiki 固定条目；默认只生成管理员预览，三篇干跑和单独人工授权未完成前绝不公开发帖。

## 首页首次连接入口

`where_is_my_friends_first_connection_enabled` 默认开启。首页会延迟请求 `/where-is-my-friends/next-action.json`，按以下顺序短路选择一个行动：当前用户收到的待处理邀请；最近七天内已接受、但原发送者尚未在两人私信中回复的邀请；尚未完成的兴趣设置；依据最近 30 天公开互动阶段选择的话题或成员；可见的近期动态；城市优先的同城发现。话题和成员行动都提供原兴趣推荐页作为次级入口，因此首页不再复制四组推荐，完整面板仍然可用。

关闭卡片只会在当前浏览器保存一个时间戳，并在七天内隐藏该入口；它不会关闭或清空个性化设置，也不会把推荐目标写入浏览器存储。API 只返回 locale key、行动类型和当前用户有权打开的站内 URL，不返回私密兴趣、邀请备注、私信内容、位置或精确距离；本地冷却和新埋点不保存话题、成员、邀请、私信的目标 ID 或内容。

每个候选继续服从原子功能边界：兴趣引导关闭时跳过 onboarding，实践邀请关闭时跳过邀请和会话行动，个性化关闭时不调用推荐器，动态关闭或专用分区不安全时跳过动态。同城发现保持城市模式始终可用的现有合同；总开关、新入口开关关闭或用户未登录时 endpoint fail closed。卡片只在 loading 或成功状态占用首页；`empty`、请求失败、七天本地关闭或关闭功能开关时会恢复旧首页模块，避免留下空白并便于独立回退。

## 社区发现排序与衡量

`participation_v1` 使用可解释规则作为第一版基线：明确兴趣匹配 32%、最近阅读/点赞/回复行为 18%、可参与性 18%、新鲜度 12%、关系桥接 10%、新成员扶持 5%、相邻探索 5%，再扣除已读、已回复、累计阅读时间较长、长期无人参与和同作者集中等惩罚。五个讨论候选采用“3 个高度相关 + 1 个等待回应 + 1 个相邻探索”的混排；缺少某类安全可见候选时才按总分补位。换一批只在排序靠前的安全候选池内轮换讨论、成员和兴趣入口，不会用低相关结果制造变化。

成员卡展示共同兴趣、最多两篇相关公开内容和当前可用行动；兴趣入口只进入经过标签筛选的公开讨论列表，活跃成员数低于配置的隐私阈值时只显示通用说明。刷新、打开和“不感兴趣”都不会订阅标签、改变通知级别或绕过现有权限、屏蔽、静音与成员 opt-in 边界。

首页和兴趣页会记录 `surface`、`recommendation_group`、`candidate_source`、`rank_bucket`、`algorithm_version` 与 `result_bucket`。这些事件不保存话题、成员或兴趣目标 ID，也不保存内容。推荐北极星指标是“看过推荐的用户中，七日内产生公开发帖或回复的比例”；同时聚合推荐面板展开/收起、分组切换、刷新、各分组展示到打开和不感兴趣，以及同城入口的展示、打开、保存城市和关闭漏斗。

七日参与、首次回复、插件回访和内容响应率只用已经走完整个七日观察窗的成熟 cohort 计算，尚未成熟的用户或话题单独列为 `in_progress`；推荐成熟 cohort 只纳入带 `recommendation_group` 的新版曝光。原有顶层曝光后 24 小时回复率和七日兼容键也映射到同一成熟 cohort，不再混入未成熟样本。24 小时回复率同样只用已走完 24 小时的曝光。旧版插件回访指标仍以本插件记录的 `page_view` 为准，不代表全站回访；新增的动态发布者、回复者、打开者和同期普通公开内容参与者七日回访明确使用 Discourse `UserVisit`，代表全站自然日访问。内容供给统计公开可见、非受限分区的主题，并区分人工原创、许可导入、人工作者/回复者和七日内获得人工回复的成熟主题。

管理员报告中的 `connections` 直接聚合实践邀请表：按来源分别提供窗口状态快照、创建后七日响应成熟 cohort，以及“接受后原发送者在该两人 PM 中七日内发布一篇合格回复”的双向会话代理指标。前两项按邀请创建时间入窗；双向会话按 `responded_at ∈ [since, as_of]` 入窗，因此不会漏掉更早创建、但在报告期内接受的邀请。`native` 不与 `legacy_reconfirmed` 混入同一转化率；未走完观察窗的邀请或接受记录只进入 `in_progress`，七日后响应只计为 late response。该代理只说明插件创建的 PM 出现了往返，不能证明线下见面、实践成功或关系建立。

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
- 首页首次连接服务只返回当前用户自己的邀请状态，并复用相同的 Guardian、ignore/mute、成员可推荐资格和动态分区安全检查；邀请卡不显示发送者、备注或时间，会话卡不显示私信内容。
- 成员的私密选择不会作为字段返回；推荐理由只展示查看者自己的匹配兴趣。隐藏帖子不会成为成员推荐证据。
- 实践邀请必须有当前可验证的共同兴趣，并同时经过信任等级、每日额度、双方忽略/静音、私信白名单与权限和收件人 opt-out 检查；接受时会再次验证通信安全。
- 每条邀请只有一个发起者和一个收件人；接受时创建的私信只包含这两人。
- 建议时间按发送者浏览器时区转换为 UTC；邀请保留兴趣名称快照，管理员后续删除标签不会破坏历史。
- 旧意向书签只向原意向所有者返回；迁移、重新确认和历史互选导入都不会自动发送邀请或通知。
- 只有明确允许“被推荐”且近期活跃的成员才会出现；不会暴露对方的私密兴趣或使用目的。
- 印象标签：提议在批准前只对被标签人与提议人可见，任何第三方接口都不返回 pending 标签；已批准标签只展示给双方无屏蔽/静音关系且可查看资料的用户，提议人身份从不公开，被标签人可移除任意标签并一键关闭接收；赞同者公开，但不能赞同自己或提议人的标签。
- 插件绝不自动订阅标签、分区，也不会改变任何通知级别。
- 个人动态只存在于仅登录会员可读、默认静音的专用分区；功能配置不合格时接口 fail closed。动态及回复在安全上传落地前拒绝图片、音视频和附件，但正文可使用论坛已有表情；推荐流只展示其他成员最近 30 天的一条动态，排除当前用户和忽略关系，不引入关注、点赞或公开热度排名，且动态不会进入普通 Latest、用户“主题”页或讨论推荐。
- 七日公开互动率和首次回复率直接从公开帖子按 onboarding 或推荐曝光时间窗聚合；私信、受限分区、内容和目标 ID 均不会进入统计结果。
- 邀请连接统计复用统一的 aggregate privacy policy；任一来源或状态细分不足阈值时原子隐藏整个细分，不返回精确数量、比例或中位响应时间，也不提供可通过总数相减恢复小分组的合并总计。接受后缺少 PM 的记录同样参与原子抑制判断，但不返回该小组的精确数量。
- 英文原文只在单次任务内存中存在，不写插件数据库或日志；数据库只保存来源、许可、失败代码、token 用量和通过校验的中文内容。模型 API 密钥与 Discourse AI 的 `AiSecret` 一样由数据库保存；管理接口只返回“已配置”状态，绝不返回密钥，日志也会过滤密钥参数。数据库管理员和数据库备份仍可读取密钥。发送给模型供应商的内容已经过许可校验和隐私清理；供应商的数据保留、日志和缓存政策需由管理员单独确认。

管理员调试端点 `/where-is-my-friends/debug-stats.json` 只对管理员开放，且只返回聚合数据。响应包含统计起止时间、原有位置与推荐漏斗、推荐分组和面板操作、同城入口漏斗、成熟 cohort、`connections` 邀请连接结果、公开内容供给、动态供给/回复/发现/全站回访，以及按自然日汇总的发现和内容趋势。可通过 `?days=7`、`?days=30` 或 `?days=90` 选择统计窗口；其他值安全回退到 30 天。完整口径见 [增长可观测性口径](docs/plans/2026-08-02-growth-observability.md)，部署基线、观察时间点和决策矩阵见 [v1.20 生产闭环协议](docs/plans/2026-08-08-v1.20-production-closure.md)。

## 安装与升级

将仓库放入 Discourse 的 `plugins/where-is-my-friends`，然后在 Discourse 根目录运行：

```bash
bundle exec rake db:migrate
```

重启 Discourse 后，在管理后台确认 `where_is_my_friends_enabled`、`where_is_my_friends_interest_onboarding_enabled` 与 `where_is_my_friends_practice_invitations_enabled` 已启用。插件会安装内置细分兴趣目录；管理员还可额外配置最多 20 个论坛标签。目录关系和话题映射维护在 `config/interest_catalogue.yml`。

飞行棋成就默认关闭。启用前需把房间服务和论坛配置为同一个至少 32 字节的 `where_is_my_friends_flying_chess_claim_secret`，再启用 `where_is_my_friends_flying_chess_achievements_enabled`；只开放静态游戏页面并不会产生可认领的服务端完成凭证。论坛只接受房间服务在权威完赛后签发的短期凭证，玩家不能用浏览器自行声明完成记录。

个人动态必须先由管理员创建只授予 `trust_level_0` 完整权限、加入 `default_categories_muted` 的受限分区，再设置 `where_is_my_friends_dynamics_category_id`。四个动态入口开关默认开启，但在分区校验通过前接口仍会 fail closed。上线验收、匿名验证和数据保留回滚见 [个人动态上线手册](docs/plans/2026-08-03-personal-dynamics-rollout.md)。该流程不创建标签。

若数据库仍有旧插件的 `practice_interests` 表，post-migrate 会幂等导入：近 90 天记录成为 `needs_reconfirmation` 私密书签，所有双向记录成为 `notification_suppressed` 历史配对。导入不会创建 `WhereIsMyFriendsPracticeInvitation` 或 `Notification`。部署顺序与回滚检查见 [实践邀请上线手册](docs/plans/2026-07-28-practice-invitations-rollout.md)。

许可英文精选的模型供应商可在插件管理页配置 Responses API 或 OpenAI-compatible Chat Completions 的 Base URL、模型和 API 密钥；Chat Completions 可选择严格 JSON Schema，或供应商兼容性更广的 JSON object 加本地严格校验。同一个模型网关负责范围分类、翻译和独立复核，不需要单独的 OpenAI Moderation 凭据。供应商密钥可直接在后台轮换，无需环境变量或重建；旧的 DeepSeek/OpenAI 供应商密钥环境变量不会被读取。新发布候选只有五个固定 Spanking Art Wiki 条目；参与度门禁也只按这五个 catalogue identity 统计，Wikipedia、Stack Exchange 和其他历史记录仅用于核验旧记录，不会扩充或满足试点样本。首次启用必须保持 `licensed_import_dry_run=true`；三篇预览全部人工通过后仍需单独授权，最多公开五篇。30 日时不足五篇成熟样本会 fail closed，成熟样本不会在 30 日周年后因滚动窗口滑出；五篇中至少三篇获得七日真人回复才通过回复率门槛。本次代码合并不授权开启生产导入。完整步骤见 [英文精选上线手册](docs/plans/2026-07-31-licensed-english-import-rollout.md)。

插件元数据要求 Discourse `2026.7.0-latest` 或更高版本。持续集成会完整运行官方插件工作流两次：受保护分支已强制的 `ci / …` 状态固定到已验证的最低支持核心快照 `7c06c1528ed9571d7407fa32259d77e1853c64d5`（该快照自身版本即为 `2026.7.0-latest`），另一个 `latest` job 跟随最新核心。仓库内的 `spec/system` 会被 reusable workflow 自动发现，并在 minimum 和 latest 两个矩阵中运行真实浏览器系统测试；现有 RSpec、QUnit、lint 和 annotations 门禁保持不变。由于这一版本线没有对应的 beta Git 标签，CI 使用不可变提交来定义可重现的兼容性下限。

## 设置

| 设置 | 默认值 | 说明 |
| --- | --- | --- |
| `where_is_my_friends_enabled` | `true` | 启用插件 |
| `where_is_my_friends_flying_chess_achievements_enabled` | `false` | 启用服务端验证的飞行棋完成记录认领、资料展示和徽章同步；关闭时两个写接口均返回不可用 |
| `where_is_my_friends_flying_chess_claim_secret` | 空 | 房间服务与论坛共享的凭证验证密钥，至少 32 字节且不会发送到浏览器 |
| `where_is_my_friends_flying_chess_game_url` | `https://atang-sp.github.io/flying-chess/online.html` | 论坛资料卡中的飞行棋入口 URL |
| `where_is_my_friends_interest_onboarding_enabled` | `true` | 启用一次性兴趣冷启动和个性化推荐 |
| `where_is_my_friends_first_connection_enabled` | `true` | 在首页延迟加载一个阶段感知的“今天可以做什么”行动；关闭后恢复旧首页模块 |
| `where_is_my_friends_interest_tags` | 空 | 在内置兴趣目录之外补充的论坛标签，最多 20 个 |
| `where_is_my_friends_dynamics_enabled` | `true` | 启用个人 Activity 动态页和发布接口；分区不合格时仍 fail closed |
| `where_is_my_friends_dynamics_homepage_enabled` | `true` | 启用首页折叠发现面板的第四个“动态”分组 |
| `where_is_my_friends_dynamics_feed_enabled` | `true` | 启用首页近期动态推荐流、查看全部动态页和社区入口 |
| `where_is_my_friends_dynamics_member_preview_enabled` | `true` | 在成员推荐卡上批量附加一条 30 天内动态摘要，不改变排名 |
| `where_is_my_friends_dynamics_category_id` | 空 | 仅 `trust_level_0` 可读写且加入默认静音的专用分区 |
| `where_is_my_friends_practice_invitations_enabled` | `true` | 启用严格一对一实践邀请 |
| `where_is_my_friends_practice_invitation_min_trust_level` | `1` | 允许发送邀请的最低信任等级 |
| `where_is_my_friends_practice_invitation_daily_limit` | `5` | 每位成员每天最多发送的邀请数 |
| `where_is_my_friends_user_tags_enabled` | `false` | 启用成员印象标签：提议须经被标签人批准后才公开，可赞同 |
| `where_is_my_friends_user_tag_max_length` | `20` | 印象标签文本的最大字符数 |
| `where_is_my_friends_user_tag_daily_proposal_limit` | `20` | 每位成员每天最多向他人提议的印象标签数 |
| `where_is_my_friends_user_tag_max_displayed` | `5` | 成员卡片最多展示的已批准印象标签数，按赞同数排序 |
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
| `GET` | `/where-is-my-friends/next-action.json` | 只返回当前用户当前阶段的一个隐私安全行动，或显式 `empty`；不写数据库 |
| `GET` | `/where-is-my-friends/dynamics.json?username=...&before_id=...` | 读取某成员的动态，每页 20 条并显式返回较早分页游标 |
| `POST` | `/where-is-my-friends/dynamics.json` | 当前用户通过正常 Discourse 发帖/审核链路创建纯文字动态；只接受 `raw` |
| `GET` | `/where-is-my-friends/dynamics/recent.json` | 首页第四栏读取最近 30 天、作者去重、最多 3 条动态 |
| `GET` | `/where-is-my-friends/dynamics/feed.json?before_id=...` | 首页推荐流和“查看全部动态”页读取其他成员最近 30 天动态；每页 10 条、作者去重并支持较早分页 |
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
| `GET` | `/where-is-my-friends/user-tags.json?username=...` | 某成员已批准的印象标签（含赞同数与本人是否已赞同） |
| `POST` | `/where-is-my-friends/user-tags.json` | 向某成员提议一条自由文本印象标签 |
| `GET` | `/where-is-my-friends/user-tags/mine.json` | 我的印象标签收件箱：待确认提议（含提议人身份）与已处理标签 |
| `PUT` | `/where-is-my-friends/user-tags/:id/approve.json` | 被标签人批准提议并使其公开 |
| `PUT` | `/where-is-my-friends/user-tags/:id/reject.json` | 被标签人拒绝提议 |
| `PUT` | `/where-is-my-friends/user-tags/:id/remove.json` | 被标签人移除已公开的标签 |
| `POST` | `/where-is-my-friends/user-tags/:id/endorse.json` | 赞同一条已公开的标签 |
| `DELETE` | `/where-is-my-friends/user-tags/:id/endorse.json` | 取消赞同 |
| `POST` | `/where-is-my-friends/flying-chess/claims.json` | 认领房间服务签发的单次完成凭证；需要主插件、成就子功能和有效共享密钥均已启用 |
| `PUT` | `/where-is-my-friends/flying-chess/profile.json` | 当前用户设置自己的飞行棋成就资料是否公开；成就子功能关闭时不可用 |
| `GET` | `/where-is-my-friends/debug-stats.json` | 管理员聚合诊断 |
| `GET` | `/where-is-my-friends/licensed-imports.json` | 管理员预览、失败原因、token 用量与互动门槛状态；不返回密钥或英文原文 |

## 开发和验证

把插件放在当前 Discourse checkout 下，然后运行：

```bash
d/rake db:migrate
RAILS_ENV=test d/rake db:migrate
d/rake 'plugin:spec[where-is-my-friends]'
CI=1 d/rake 'plugin:qunit[where-is-my-friends]'
d/exec env LOAD_PLUGINS=1 bin/rspec plugins/where-is-my-friends/spec/system
d/exec bin/lint plugins/where-is-my-friends
```

`spec/system` 是官方 PR/release system-test 门禁，覆盖四条关键纵向流程。完整的真实 Rails/Ember Playwright 套件仍保留在 `e2e/`；运行方法见 `e2e/README.md`。Playwright 默认保留浏览器沙箱，只有执行环境明确禁用 browser user namespace 时才显式设置 `DISCOURSE_DISABLE_BROWSER_SANDBOX=1`。

## 主要目录

- `lib/where_is_my_friends/recommendation_engine.rb`：权限安全、可解释、以参与为目标的话题/成员/兴趣入口推荐。
- `lib/where_is_my_friends/next_action.rb`：按阶段短路选择一个首页行动，并协调邀请、推荐、动态与同城降级。
- `lib/where_is_my_friends/dynamic_feed.rb`：个人动态的配置校验、创建、权限过滤、分页、最近作者去重、批量成员摘要和序列化唯一策略入口。
- `lib/where_is_my_friends/dynamic_metrics.rb`：动态成熟作者、七日回复、入口漏斗和基于 `UserVisit` 的全站回访聚合。
- `lib/where_is_my_friends/connection_metrics.rb`：按邀请来源隔离的状态快照、七日响应 cohort、双向会话代理和原子隐私抑制。
- `lib/where_is_my_friends/growth_report.rb`：管理员可见的漏斗、成熟 cohort、内容供给和按日趋势聚合。
- `lib/where_is_my_friends/licensed_import/`：许可校验、内容清理、安全分类、忠实翻译、独立复核、发布和自动停发。
- `lib/where_is_my_friends/practice_invitation_eligibility.rb`：共同兴趣、信任、屏蔽、opt-out 和私信权限策略。
- `lib/where_is_my_friends/user_tag_visibility.rb`：印象标签的公共可见性、屏蔽边界与赞同序列化唯一入口。
- `app/models/where_is_my_friends_practice_invitation.rb`：严格一对一邀请与接受后的私信引用。
- `app/models/where_is_my_friends_user_tag.rb`：提议、批准、拒绝、移除与赞同的印象标签状态机。
- `app/models/where_is_my_friends_legacy_practice_bookmark.rb`：仅所有者可见、需要重新确认的迁移书签。
- `app/models/where_is_my_friends_interest_profile.rb`：私密兴趣、目的与用户控制。
- `app/models/user_location.rb`：城市标准化、有效期和距离范围。
- `app/controllers/where_is_my_friends/`：认证后的发现和事件 API。
- `assets/javascripts/discourse/components/`：原生 Glimmer/GJS 页面和模态框。
- `spec/`：模型、请求和定时任务测试。
- `spec/system/`：官方 Discourse reusable workflow 自动发现的真实 Rails/Ember 浏览器门禁。
- `test/javascripts/`：QUnit 验收和单元测试。

## 许可证

插件代码采用 MIT License。随插件分发的 Leaflet 1.9.4 使用其 BSD-2-Clause 风格许可证，文本见 `public/leaflet-LICENSE.txt`。

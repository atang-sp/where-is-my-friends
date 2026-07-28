# Local Friends — Discourse 社区发现插件

Local Friends 帮助成员真正“看见论坛里有哪些人”：新成员可通过私密的兴趣冷启动，立即得到可解释的话题和成员推荐；也可以用“城市”发现同城用户，再按需启用 GPS 或地图位置来显示宽泛的距离范围。

## 核心体验

- 兴趣冷启动：首次或升级后选择 3–5 个兴趣和一个当前目的，立即看到最多 5 个话题和 3 位成员。
- 可解释推荐：话题显示匹配兴趣，成员推荐只引用用户可见的公开贡献和代表话题。
- 一对一实践邀请：从推荐卡或公开兴趣资料页选择共同兴趣，可附建议时间和备注；接受后只创建两人私信。
- 可控收件箱：收件人可接受、拒绝或忽略邀请，也可在通知设置中完全关闭实践邀请。
- 旧数据接管：近 90 天旧实践意向只迁移为私密、待重新确认的书签；既有互选只保留为静默历史。
- 用户控制：可跳过、编辑、“不感兴趣”、退出被推荐、公开兴趣或一键清空个性化数据。
- 城市优先：本地发现只需填写城市，保存后自动加载同城成员。
- 可选精确模式：GPS 或地图只用于生成“约 5 公里内 / 5–20 公里 / 20 公里以上”等距离范围。
- 连接闭环：成员卡片可进入主页、发私信；空状态可搜索本地话题。
- 明确状态：覆盖首次设置、加载、结果、空结果、过期和错误状态。
- 控制权：用户可更新城市或立即删除位置；位置默认 30 天后由定时任务删除。
- 隐私统计：只记录白名单事件、位置模式和粗粒度结果桶；事件 90 天后删除。

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
- 实践邀请必须有当前可验证的共同兴趣，并同时经过信任等级、每日额度、双方忽略/静音、私信白名单与权限和收件人 opt-out 检查；接受时会再次验证通信安全。
- 每条邀请只有一个发起者和一个收件人；接受时创建的私信只包含这两人。
- 建议时间按发送者浏览器时区转换为 UTC；邀请保留兴趣名称快照，管理员后续删除标签不会破坏历史。
- 旧意向书签只向原意向所有者返回；迁移、重新确认和历史互选导入都不会自动发送邀请或通知。
- 只有明确允许“被推荐”且近期活跃的成员才会出现；不会暴露对方的私密兴趣或使用目的。
- 插件绝不自动订阅标签、分区，也不会改变任何通知级别。
- 七日公开互动率和首次回复率直接从公开帖子按 onboarding 时间窗聚合；私信、受限分区、内容和目标 ID 均不会进入统计结果。

管理员调试端点 `/where-is-my-friends/debug-stats.json` 只对管理员开放，且只返回聚合数据，包括兴趣引导完成率、推荐打开率、七日公开互动率和七日首次回复率。可通过 `?days=7`、`?days=30` 或 `?days=90` 选择统计窗口；其他值安全回退到 30 天。

## 安装与升级

将仓库放入 Discourse 的 `plugins/where-is-my-friends`，然后在 Discourse 根目录运行：

```bash
bundle exec rake db:migrate
```

重启 Discourse 后，在管理后台确认 `where_is_my_friends_enabled`、`where_is_my_friends_interest_onboarding_enabled` 与 `where_is_my_friends_practice_invitations_enabled` 已启用。管理员可配置最多 20 个兴趣标签；留空时会从每位成员可见的近期话题中生成候选。

若数据库仍有旧插件的 `practice_interests` 表，post-migrate 会幂等导入：近 90 天记录成为 `needs_reconfirmation` 私密书签，所有双向记录成为 `notification_suppressed` 历史配对。导入不会创建 `WhereIsMyFriendsPracticeInvitation` 或 `Notification`。部署顺序与回滚检查见 [实践邀请上线手册](docs/plans/2026-07-28-practice-invitations-rollout.md)。

本版本在 Discourse `2026.7.0-latest`（commit `7c06c152`）上开发和验证，插件元数据要求 Discourse `2026.7.0.beta1` 或更高版本。

## 设置

| 设置 | 默认值 | 说明 |
| --- | --- | --- |
| `where_is_my_friends_enabled` | `true` | 启用插件 |
| `where_is_my_friends_interest_onboarding_enabled` | `true` | 启用一次性兴趣冷启动和个性化推荐 |
| `where_is_my_friends_interest_tags` | 空 | 管理员选择的兴趣标签，最多 20 个；空时从用户可见近期话题生成 |
| `where_is_my_friends_practice_invitations_enabled` | `true` | 启用严格一对一实践邀请 |
| `where_is_my_friends_practice_invitation_min_trust_level` | `1` | 允许发送邀请的最低信任等级 |
| `where_is_my_friends_practice_invitation_daily_limit` | `5` | 每位成员每天最多发送的邀请数 |
| `where_is_my_friends_enable_virtual_location` | `true` | 允许可选 GPS/地图距离范围 |
| `where_is_my_friends_map_provider` | `openstreetmap` | `openstreetmap`、`amap` 或 `baidu` |
| `where_is_my_friends_amap_api_key` | 空 | 仅在选择高德时发送到浏览器 |
| `where_is_my_friends_baidu_api_key` | 空 | 仅在选择百度时发送到浏览器 |
| `where_is_my_friends_max_users_display` | `50` | 返回用户上限，服务端限制为 10–200 |
| `where_is_my_friends_location_ttl_days` | `30` | 位置有效期，服务端限制为 1–365 天 |
| `where_is_my_friends_aggregate_privacy_threshold` | `3` | 显示精确活跃人数的最低参与者数量 |

OpenStreetMap 无需密钥，是默认回退。高德和百度 key 是公开的浏览器 key，必须在供应商控制台限制到论坛域名；插件只把当前选中供应商的 key 发给客户端。详见 [VIRTUAL_LOCATION_GUIDE.md](VIRTUAL_LOCATION_GUIDE.md)。

## API

所有端点都要求登录且受插件开关保护：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| `GET` | `/where-is-my-friends.json` | 当前状态、无坐标位置元数据和客户端设置 |
| `POST` | `/where-is-my-friends/locations.json` | 保存城市、GPS 或地图模式 |
| `GET` | `/where-is-my-friends/locations/nearby.json` | 使用服务端已保存位置查找同城成员 |
| `DELETE` | `/where-is-my-friends/locations.json` | 删除当前用户位置 |
| `GET` | `/where-is-my-friends/recommendations.json` | 私密偏好、可见兴趣目录和当前推荐 |
| `PUT` | `/where-is-my-friends/recommendations/profile.json` | 保存兴趣、目的与隐私选项 |
| `DELETE` | `/where-is-my-friends/recommendations/profile.json` | 关闭并清空个性化数据 |
| `POST` | `/where-is-my-friends/recommendations/skip.json` | 跳过一次性引导 |
| `POST` | `/where-is-my-friends/recommendations/dismiss.json` | 对当前可见推荐标记“不感兴趣” |
| `GET` | `/where-is-my-friends/practice-invitations.json` | 当前用户的私密收件箱和发件记录 |
| `GET` | `/where-is-my-friends/practice-invitations/availability.json` | 查询某资料页成员当前可用的共同兴趣 |
| `POST` | `/where-is-my-friends/practice-invitations.json` | 创建严格一对一邀请 |
| `PUT` | `/where-is-my-friends/practice-invitations/:id/accept.json` | 收件人接受并创建两人私信 |
| `PUT` | `/where-is-my-friends/practice-invitations/:id/decline.json` | 收件人拒绝邀请 |
| `PUT` | `/where-is-my-friends/practice-invitations/:id/ignore.json` | 收件人忽略邀请 |
| `GET` | `/where-is-my-friends/legacy-practice-bookmarks.json` | 当前用户自己的旧意向书签 |
| `PUT` | `/where-is-my-friends/legacy-practice-bookmarks/:id/reconfirm.json` | 仅重新确认书签，不发送邀请 |
| `PUT` | `/where-is-my-friends/legacy-practice-bookmarks/:id/dismiss.json` | 移除旧意向书签 |
| `POST` | `/where-is-my-friends/events.json` | 写入白名单漏斗事件 |
| `GET` | `/where-is-my-friends/debug-stats.json` | 管理员聚合诊断 |

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

- `lib/where_is_my_friends/recommendation_engine.rb`：权限安全、可解释的话题与成员推荐。
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

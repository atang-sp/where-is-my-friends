# 个人动态上线与回滚手册

## 边界

本文只定义未来发布后的生产操作顺序；提交本功能分支不等于授权发布或部署。上线不得用自动化测试账号或测试动态污染生产。动态复用 Topic/Post，回滚只关入口和开关，不删除用户内容，也不创建任何标签。

## 部署前快照

1. 分别保存 `/where-is-my-friends/debug-stats.json?days=7|30|90` 的聚合响应。2026-08-03 的近 30 天试点前快照是 16 个真人主题、16 位作者、3 位回复者、成熟主题七日人工回复率 40%，以及 16 位成员推荐曝光用户、综合打开率 31.25%；这些数字只用于本次试点对照，不写入代码阈值。
2. 完成 Discourse 数据库备份，记录备份路径、SHA256、当前插件不可变版本、`app.yml` 和全部 `where_is_my_friends_*` 设置值。
3. 确认 S3 与 `secure_uploads` 仍未同时满足时，动态正文和回复必须继续拒绝图片、音视频和附件。

## 分区准备

在管理后台创建「个人动态」分区，并同时满足以下四项：

- `read_restricted=true`；
- 分区权限只有自动组 `trust_level_0` 的 `full`，没有 `everyone`、staff 或其他额外条目；管理员仍通过核心职权审核；
- 分区 ID 已加入 `default_categories_muted`；
- 将 ID 写入 `where_is_my_friends_dynamics_category_id`，不配置 minimum tags，不添加或创建标签。

部署前可在容器内用只读 Rails runner 核对；把 `<ID>` 替换为实际分区 ID：

```ruby
category = Category.find(<ID>)
expected = [[Group::AUTO_GROUPS.fetch(:trust_level_0), CategoryGroup.permission_types.fetch(:full)]]
actual = category.category_groups.order(:group_id, :permission_type).pluck(:group_id, :permission_type)
muted = SiteSetting.default_categories_muted.split("|").map(&:to_i)
raise "invalid dynamics category" unless category.read_restricted? && category.minimum_required_tags.to_i.zero? && actual == expected && muted.include?(category.id)
puts({ id: category.id, slug: category.slug, permissions: actual, muted: true }.inspect)
```

任何一项不满足时接口应返回 404；不要通过放宽插件校验来继续上线。

## 首次部署与启用

1. 保持 `where_is_my_friends_dynamics_enabled`、`where_is_my_friends_dynamics_homepage_enabled`、`where_is_my_friends_dynamics_member_preview_enabled` 全部为 `false`，完成迁移、服务重启和资产编译。
2. 验证匿名访问动态 API 与动态主题失败；验证登录会员在三个开关关闭时看不到 Activity 标签；检查错误日志和迁移状态。
3. 只打开总开关。由真实会员自然发布，确认普通 composer 不能向专用分区发主题、个人页发布走正常审核、普通 Latest 和用户“主题”页均不出现动态、原生回复和通知可用。
4. 至少累计 3 条动态、2 位作者且 24 小时内没有隐私、审核或错误异常后，打开首页开关。验证面板收起时动态接口零请求、选择第四栏后才请求且最多显示 3 位作者。
5. 至少累计 5 位拥有 30 天内动态的可推荐作者后，打开成员预览开关。确认有预览和无预览卡片原有理由、讨论、资料、邀请与“不感兴趣”行为均不变，排名不因动态改变。

## 观察与决策

- 24 小时：检查匿名访问、媒体绕过、审核队列、5xx、日志和动态没有进入普通列表。
- 7 天：只检查首批已成熟动态的人工回复；仍在 `in_progress` 的样本不进入失败分母。
- 30 天：持续发布至少 10 位非员工作者，成熟作者跨日再发布率至少 30%；至少 30 条成熟动态后，七日回复率 40% 以上通过、25%–39.9% 调整提示与分发、低于 25% 判为日记化失败。
- 发现至少需要 30 位看到动态预览的成员卡用户；动态打开率至少 10%，成员卡综合打开率不能比 31.25% 基线低超过 5 个百分点。
- 使用 `UserVisit` 比较动态参与者与同期普通公开内容参与者的七日全站回访；差距不能低 5 个百分点以上，并且只能报告方向性关联。
- 样本未成熟可延长到第 60 天；不得用小样本宣称成功。

只有持续发布和产生回复同时通过，且发现与回访没有明显倒退，才扩大入口。供给通过但回复处于中间区间时只迭代提示。作者不足或回复率低于 25% 时关闭首页和成员卡入口，保留个人页供复盘。

## 回滚

1. 先关闭 `where_is_my_friends_dynamics_member_preview_enabled`。
2. 再关闭 `where_is_my_friends_dynamics_homepage_enabled`。
3. 最后关闭 `where_is_my_friends_dynamics_enabled`。
4. 复查普通主题列表、HTTP、日志和分区权限。不删除 Topic/Post、不清空自定义字段、不移动分区，也不删除迁移列；已有动态继续留在会员受限分区，后续可以恢复。

只有代码本身造成站点异常时才按已保存的不可变版本和时间戳 `app.yml` 重建回滚。应用预热或单次 SSH 中断本身不是数据回滚信号。

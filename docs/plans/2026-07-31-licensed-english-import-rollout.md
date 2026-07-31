# 许可英文精选上线手册

## 安全默认值

部署 1.7.0 不会自动开始翻译或发帖：`licensed_import_enabled=false`，且
`licensed_import_dry_run=true`。唯一允许的来源是 Interpersonal Skills Stack
Exchange API 返回、问题和选定回答均明确标记为 CC BY-SA 3.0 或 4.0 的完整问答。

OpenAI 密钥只能通过 Discourse 进程环境变量注入：

```text
WHERE_IS_MY_FRIENDS_OPENAI_API_KEY
```

不得把值写入 `app.yml` 的 Git 仓库副本、Discourse SiteSetting、数据库、日志或
管理员接口。生产环境应通过现有的秘密管理方式向容器注入，并在重建后验证进程能
看到变量名；验证时不要输出变量值。

## 三天干跑

1. 完成数据库迁移和 Discourse 重建，保持 `licensed_import_dry_run=true`。
2. 确认模型为 `gpt-5.6-terra`、北京时间发布小时为 `20`、间隔为 `24`、每日上限为
   `1`、月度预算为 `1500000`。
3. 打开 `licensed_import_enabled`。任务每小时检查一次，只会在配置的北京时间小时
   生成一篇预览。
4. 每天由管理员访问 `/where-is-my-friends/licensed-imports.json`，检查译文、问题和
   回答作者、两个原文链接、两个许可链接、修改说明、段落完整性及讨论问题边界。
5. 第三篇预览生成后任务会自动关闭总开关并通知管理员。三篇必须全部一次通过；
   任一篇需要返工都不得进入公开阶段。

预览只保存中文成品和来源元数据。英文正文不会保存，因此人工抽查应通过返回的原文
链接与中文预览逐项核对。

## 公开运行 30 天

三篇均通过后，将 `licensed_import_dry_run` 改为 `false`，再打开
`licensed_import_enabled`。系统使用透明的 Discourse 系统用户创建主题，标题带
`[英文精选·译文]`，并添加 `英文精选`、`安全与边界` 标签；任一程序校验失败都只
保存失败代码，不创建主题。

运行期间每天检查管理员接口。以下情况会自动关闭总开关：

- API 密钥缺失、月度 token 预算不足或未处理异常；
- 连续七篇已满七天的译文均未在各自发布后七天内获得真人回复；
- 30 天检查中，成熟译文的七天真人回复率低于 50%；
- 最近 30 天真人原创主题数低于此前 30 天基线。

公开阶段仍保持每天最多一篇、至少 24 小时间隔和主题不连续重复。来源每天重新检查；
原问答被删除、改写、换回答、变更署名或许可时，相关主题会隐藏，等待重新处理。

## 事故停发

确认版权投诉、严重安全漏检或错误署名时，立即运行：

```bash
bundle exec rake "where_is_my_friends:licensed_import:halt[来源问题ID,copyright_complaint]"
bundle exec rake "where_is_my_friends:licensed_import:halt[来源问题ID,serious_safety_miss]"
bundle exec rake "where_is_my_friends:licensed_import:halt[来源问题ID,attribution_error]"
```

任务会关闭总开关、隐藏该来源的预览或已发布主题并通知管理员。调查、修复和复核完成
前不要重新开启。主题隐藏不等于删除，便于保留审计记录和恢复判断。

## 30 天决策

只有当至少 50% 的成熟译文在发布后七天内获得真人回复，且最近 30 天真人原创主题数
没有低于此前 30 天时，才继续公开运行。否则保持暂停。之后可在后台增大
`licensed_import_interval_hours` 降低频率，或直接关闭总开关；不需要重新部署。

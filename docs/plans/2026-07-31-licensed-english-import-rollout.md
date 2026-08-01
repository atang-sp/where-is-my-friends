# 许可英文精选上线手册

## 安全默认值

部署 1.8.0 不会自动开始翻译或发帖：`licensed_import_enabled=false`，且
`licensed_import_dry_run=true`。唯一允许的来源是 Interpersonal Skills Stack
Exchange API 返回、问题和选定回答均明确标记为 CC BY-SA 3.0 或 4.0 的完整问答。

部署时只注入一个长期稳定的凭据加密主密钥：

```bash
openssl rand -base64 32
# 将结果通过生产环境的秘密管理方式注入：
WHERE_IS_MY_FRIENDS_CREDENTIALS_MASTER_KEY
```

不得把值提交到 Git、日志或管理接口。生产环境应通过现有的秘密管理方式将它注入
Discourse 容器，并在重建后只验证变量存在，不输出变量值。该主密钥用于 AES-256-GCM
加密后台保存的供应商密钥；日常只在后台轮换供应商密钥，不要轮换主密钥。丢失或替换
主密钥会让已有供应商凭据无法解密，需要逐个重新录入。

重建后进入“管理后台 → 插件 → Where is my friends → AI 供应商”：

1. 添加“分类、翻译与复核”供应商，选择 `Responses API` 或
   `Chat Completions`，填写 HTTPS Base URL、模型名和 API 密钥。Chat Completions
   若不支持 strict JSON Schema，可选择 `JSON object + local validation`；程序仍会按
   完整 schema 在本地拒绝缺字段、增字段或类型错误的结果。
2. 添加“安全审核”凭据。端点和模型固定为 OpenAI 官方
   `https://api.openai.com/v1` 与 `omni-moderation-latest`，只需填写密钥。
3. 分别点击“测试”。生成测试会验证真实鉴权、模型可用性和严格 JSON Schema 输出；
   安全审核测试会调用一条无害文本。
4. 测试通过后分别激活。两个用途都必须有一个活动配置，任务才会运行。

Base URL 只允许 HTTPS、公网 DNS/IP、无 URL 凭据、查询参数或片段；连接固定到校验过的
IP，且不跟随重定向。程序不会在失败时自动切换供应商，也不会读取旧的
`WHERE_IS_MY_FRIENDS_DEEPSEEK_API_KEY` 或
`WHERE_IS_MY_FRIENDS_OPENAI_API_KEY`。编辑 Base URL、模型、协议或密钥会立即取消验证、
停用该配置并关闭 `licensed_import_enabled`，必须重新测试和激活。

中转站会接触已清理的公开英文原文及中文译文。使用前仍需确认其运营主体、数据留存、
日志、训练、跨境传输、计费和服务条款；无法确认时优先使用模型厂商官方 API。

## 三天干跑

1. 完成数据库迁移和 Discourse 重建，保持 `licensed_import_dry_run=true`。
2. 确认生成与安全审核配置均已测试和激活、北京时间发布小时为 `20`、间隔为 `24`、
   每日上限为 `1`、月度预算为 `1500000`。
3. 打开 `licensed_import_enabled`。任务每分钟做一次轻量检查，只会在配置的北京时间
   整点进入处理并生成一篇预览。
4. 每天由管理员访问 `/where-is-my-friends/licensed-imports.json`，检查译文、问题和
   回答作者、两个原文链接、两个许可链接、修改说明、段落完整性及讨论问题边界。
5. 第三篇预览生成后任务会自动关闭总开关并通知管理员。三篇必须全部一次通过；
   任一篇需要返工都不得进入公开阶段。

若三篇预览无法全部一次通过，可在 AI 供应商页新增或修改生成配置，测试并激活后重新
开始干跑；切换不需要重新部署。生成供应商切换不会替换独立的 OpenAI Moderation。

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

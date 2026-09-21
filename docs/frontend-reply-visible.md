# 前端回复可见功能 (Frontend Reply-To-See) 与 Bug 修复记录

## 1. 功能简介

在当前项目的论坛环境中，有一个名为 **“回复可见（前端版）”** 的 Discourse 主题（Theme Component），用于实现“前端回复可见”功能。
该功能主要通过在帖子中添加 `[reply-visible]` 和 `[/reply-visible]` 标签（Marker）来标记需要隐藏的内容。

前端会通过脚本拦截这些标签，判断当前用户是否已经回复过该帖子。
- 如果**已回复**、是**帖子作者**、或者是**管理员（Staff）**，则展示内容。
- 如果**未回复**，则为这些内容块添加 `is-hidden` 类，在 CSS 中将其隐藏（`display: none`）。

## 2. 之前存在的 Bug 描述

有些用户（如 `le3441`）反馈：在拥有较多回复的帖子中，他们在回复后，依然无法看到被隐藏的内容。

### Bug 根源排查：
该前端组件为了判断用户是否回复过，不仅会检查加载出的前 20 楼回复，还会向后端发送请求，拉取所有跟帖记录。
原来的代码逻辑是：
1. 通过 `topic.post_stream.stream` 拿到该帖子的**所有回复的 post_id**。
2. 按照每 100 个 ID 为一批，使用**正序循环**发送 API 请求 `/t/{topicId}/posts.json?post_ids[]=...` 去拿数据。
3. 对返回的数据检查是否有当前用户的 ID。如果找到则返回 `true`（已回复）。

**这里存在两个致命缺陷：**
1. **API 返回结构判断错误（主要原因）：** 
   Discourse `/t/{topicId}/posts.json` 的响应结构是将内容包裹在 `post_stream.posts` 中（即 `{ post_stream: { posts: [...] } }`），但旧代码错误地使用了 `data.posts`。这导致 `data.posts` 永远是 `undefined`，代码直接忽略了请求结果，永远返回 `false`。
2. **并发请求导致速率限制（次要原因）：** 
   旧代码使用了正序的 `for` 循环（从第 1 楼向后查）。如果帖子有几百楼，刚回复的用户排在最后。前端会立刻发起连续的 `/posts.json` 请求。这极易触发 Discourse 的 API Rate Limit（请求频率限制），导致后面的请求直接失败。

综上，只要用户的回复不是在帖子的前 20 楼（即没有被页面首次加载出来），他们在回复后就永远无法通过分页请求被检测到，从而触发了“回复了也看不到内容”的 Bug。

## 3. 修复方案

我们在服务器（`atang-sp.run.place`）上，直接进入 Discourse Docker 容器内，修改了该 Theme Component 的 `discourse/initializers/reply-visible.js` 文件。

**具体修复点：**
1. **修正 JSON 结构读取：**
   将 `data.posts` 修正为优先读取 `data.post_stream.posts`。
   ```javascript
   // 旧代码：
   if ((data.posts || []).some((p) => p.user_id === userId)) return true;
   // 新代码：
   if (((data.post_stream && data.post_stream.posts) || data.posts || []).some((p) => p.user_id === userId)) return true;
   ```
2. **将正序查询改为倒序查询：**
   用户刚回复完时，其楼层一定在最后。因此将 `for` 循环改为倒序查询，通常发送第 1 个批次请求就能立刻找到用户的最新回复。大幅降低了命中 Rate Limit 的风险和服务器压力。
   ```javascript
   // 旧代码：
   for (let i = 0; i < stream.length; i += FETCH_BATCH) {
       const chunk = stream.slice(i, i + FETCH_BATCH);
       ...
   // 新代码：
   for (let i = stream.length; i > 0; i -= FETCH_BATCH) {
       const chunk = stream.slice(Math.max(0, i - FETCH_BATCH), i);
       ...
   ```

3. **重新编译主题 JS 缓存（关键步骤）：**
   在 Rails 控制台中直接通过 `ThemeField#save!` 修改 JS 代码并不会自动触发打包编译。Discourse 会继续从 `javascript_caches` 表中下发旧的编译后 bundle。必须显式执行重新编译与缓存清理：
   ```ruby
   t = Theme.find_by(name: "回复可见（前端版）")
   t.update_javascript_cache!
   Theme.clear_cache!
   ```
   执行后，Discourse 会重新生成 `javascript_caches` 并更新 bundle digest，前端刷新时即可获取最新的修复逻辑。

## 4. 总结与后续建议
目前“前端回复可见”代码并未直接保存在当前的 `where-is-my-friends` 仓库中，而是作为环境里的独立 Theme Component 存在。本次 Bug 已在服务器端热修复。如果未来需要重建 Discourse 环境，请确保同步更新备份在服务器上的该 Theme Component 代码，或将其单独放入版本库管理。

## 5. 经验与教训总结

本次问题的排查和修复过程较为曲折，经历了“定位偏离 -> 治标不治本 -> 找到真因 -> 缓存机制阻碍 -> 彻底解决”的完整流程。从中可沉淀出以下关键经验与教训：

### 1. 警惕先入为主的主观臆测，先对齐复现上下文
- **教训**：排查初期在数据库看到 `le3441` 用户曾回复过 Topic 58（409 楼长帖），便主观推测是长帖的接口频率限制（Rate Limit）导致失败；但用户实际测试的是只有 38 楼的 Topic 5280，完全不存在频率限制问题。
- **经验**：排查问题时，第一步必须与用户或日志精确对齐复现环境（具体是哪一个 `topic_id`、具体的帖子内容与楼层），先确立唯一的目标样本，再展开追踪，避免在错误分支上浪费精力。

### 2. 区分“局部优化”与“根本原因”，杜绝治标不治本
- **教训**：初次修复尝试将正序循环改为倒序循环，虽然提升了近期回复的查询效率，但对于更早回复的用户或者根本性取值错误没有任何帮助，属于典型的“治标不治本”。
- **经验**：面对“某类用户成功、某类用户失败”的规律，要追查其分水岭背后的逻辑断层（例如本例中：前 20 楼走初始帖子列表、20 楼之后走分批接口）。在没有查清数据流和接口返回值契约之前，任何算法上的调整（如排序、倒序）都不能替代根因修复。

### 3. 深入理解宿主系统底层架构，警惕多层缓存掩盖真因
- **教训**：在 Rails 控制台直接修改 `ThemeField` 记录后，即使代码完全正确，客户端依然反馈未生效。这是因为误将数据库的“源码存储层”当成了“运行时分发层”。
- **经验**：Discourse 对主题 JS 拥有完整的编译打包链（写入 `javascript_caches` 表并生成带指纹的静态资源）。直接修改数据库记录**不会**自动触发编译打包。在进行服务器端热修时：
  - 必须调用系统生命周期方法（`theme.update_javascript_cache!` 和 `Theme.clear_cache!`）；
  - 必须以“客户端实际加载的 JS 文件内容 / Digest”作为验证标准，做到端到端的闭环验证。

### 4. 前端接口依赖需做好防御性编程
- **教训**：前端直接依赖未加保护的 `data.posts`，在 Discourse 接口结构为 `{ post_stream: { posts: [...] } }` 时静默失败（返回 `undefined` 并回退为空数组），没有任何报错日志，极难通过表面现象发现。
- **经验**：对于非自己维护的后端/平台接口，前端解析响应时应做好兼容与容错（如 `(data.post_stream?.posts || data.posts || [])`），并在关键条件不满足时在控制台打出诊断 log，降低排查成本。


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

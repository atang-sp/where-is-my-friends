# Where-Is-My-Friends 插件路由修复总结

## 问题分析

通过对比 `discourse-plugin-matching` 和 `where-is-my-friends` 两个插件，发现后者缺少以下关键的前端文件，导致路由无法正常工作：

## 修复内容

### 1. 创建路由映射文件
**文件**: `assets/javascripts/discourse/where-is-my-friends-route-map.js`
- 定义了前端路由映射
- 参考了 discourse-plugin-matching 的实现

### 2. 创建初始化文件
**文件**: `assets/javascripts/initializers/where-is-my-friends.js`
- 使用 `withPluginApi` 添加导航栏项目
- 替代了后端 serializer 的菜单配置方式

### 3. 更新路由文件
**文件**: `assets/javascripts/discourse/routes/where-is-my-friends.js`
- 添加了数据加载逻辑
- 添加了控制器设置
- 使用 `ajax` 调用后端 API

### 4. 创建控制器文件
**文件**: `assets/javascripts/discourse/controllers/where-is-my-friends.js`
- 实现了位置分享功能
- 实现了查找附近用户功能
- 实现了移除位置功能
- 使用现代 Ember.js 语法（@action 装饰器）

### 5. 创建模板文件
**文件**: `assets/javascripts/discourse/templates/where-is-my-friends.hbs`
- 提供了完整的用户界面
- 包含错误处理
- 包含用户列表显示

### 6. 更新后端控制器
**文件**: `app/controllers/where_is_my_friends/locations_controller.rb`
- 移除了 `skip_before_action :check_xhr`（因为现在使用 /api 前缀）

### 7. 更新国际化文件
**文件**: `config/locales/client.zh_CN.yml`
- 添加了缺失的翻译键
- 确保前端显示正确的文本

### 8. 清理后端配置
**文件**: `plugin.rb`
- 移除了重复的导航菜单配置
- 现在由前端初始化器统一处理

### 9. 修复路由分离问题 ⭐ 重要修复
**文件**: `plugin.rb`
- **前端路由**: `/where-is-my-friends` → `list#where_is_my_friends` (返回 HTML)
- **API 路由**: `/api/where-is-my-friends` → `where_is_my_friends/locations#index` (返回 JSON)
- 添加了 ListController 扩展来处理前端路由
- 更新了所有前端 API 调用使用 `/api` 前缀

## 关键差异

### discourse-plugin-matching (正常工作的插件)
- ✅ 有路由映射文件
- ✅ 有初始化文件
- ✅ 有完整的控制器和模板
- ✅ 后端控制器支持前端路由
- ✅ **前后端路由分离**：前端返回 HTML，API 返回 JSON

### where-is-my-friends (修复前)
- ❌ 缺少路由映射文件
- ❌ 缺少初始化文件
- ❌ 路由文件过于简单
- ❌ 缺少控制器和模板
- ❌ 后端控制器不支持前端路由
- ❌ **前后端路由混淆**：都返回 JSON

### where-is-my-friends (修复后)
- ✅ 有路由映射文件
- ✅ 有初始化文件
- ✅ 有完整的控制器和模板
- ✅ 后端控制器支持前端路由
- ✅ **前后端路由分离**：前端返回 HTML，API 返回 JSON

## 路由结构对比

### discourse-plugin-matching
```
前端: /practice-matching → list#practice_matching (HTML)
API:  /api/practice-matching → practice_matching#index (JSON)
```

### where-is-my-friends (修复后)
```
前端: /where-is-my-friends → list#where_is_my_friends (HTML)
API:  /api/where-is-my-friends → where_is_my_friends/locations#index (JSON)
```

## 测试

创建了 `test-fixed-routes.sh` 脚本来验证路由是否正常工作。

## 建议

1. 重启 Discourse 服务器以确保所有更改生效
2. 清除浏览器缓存
3. 检查浏览器控制台是否有 JavaScript 错误
4. 验证导航栏是否显示新的菜单项
5. 测试前端路由是否返回 HTML 页面
6. 测试 API 路由是否返回 JSON 数据

## 参考

修复过程参考了 `discourse-plugin-matching` 插件的实现，该插件的前端路由工作正常。 
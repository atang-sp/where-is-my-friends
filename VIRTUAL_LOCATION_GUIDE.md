# 虚拟定位功能使用指南

## 功能概述

虚拟定位功能允许用户在地图上选择一个虚拟位置，而不是使用真实的地理位置。这个功能是为了解决用户对隐私保护的担忧而设计的。

## 功能特点

### 1. 隐私保护
- **真实定位**：使用真实位置但添加500米内的随机偏移来保护隐私
- **虚拟定位**：用户可以在地图上自由选择任意位置，完全保护真实位置

### 2. 地图支持
支持三种地图服务：
- **高德地图** (`amap`)：适合中国用户，需要API密钥
- **百度地图** (`baidu`)：适合中国用户，需要API密钥  
- **OpenStreetMap** (`openstreetmap`)：开源地图，无需API密钥（默认）

### 3. 用户体验
- 直观的地图选择界面
- 拖拽标记精确定位
- 地址解析和显示
- 响应式设计支持移动设备

## 配置说明

### 1. 插件设置

在Discourse管理后台的插件设置中配置以下选项：

```yaml
where_is_my_friends_enable_virtual_location: true  # 启用虚拟定位功能
where_is_my_friends_map_provider: "amap"           # 地图服务提供商
where_is_my_friends_amap_api_key: "YOUR_KEY"      # 高德地图API密钥
where_is_my_friends_baidu_api_key: "YOUR_KEY"     # 百度地图API密钥
```

### 2. 地图服务配置

#### 高德地图配置
1. 访问 [高德开放平台](https://lbs.amap.com/)
2. 注册开发者账号
3. 创建应用获取API密钥
4. 在插件设置中填入API密钥

#### 百度地图配置
1. 访问 [百度地图开放平台](https://lbsyun.baidu.com/)
2. 注册开发者账号
3. 创建应用获取API密钥
4. 在插件设置中填入API密钥

#### OpenStreetMap
- 无需配置，开箱即用
- 适合国际用户和不需要API密钥的场景

## 数据库变更

虚拟定位功能增加了以下数据库字段：

```ruby
# user_locations表新增字段
add_column :user_locations, :is_virtual, :boolean, default: false, null: false
add_column :user_locations, :virtual_address, :text
add_column :user_locations, :location_type, :string, default: 'real', null: false
```

## 使用流程

### 1. 用户操作流程
1. 用户访问"附近的朋友"页面
2. 点击"选择定位方式"按钮
3. 选择"真实定位"或"虚拟定位"
4. 如果选择虚拟定位：
   - 打开地图选择器
   - 在地图上点击或拖拽选择位置
   - 确认选择
5. 系统保存位置信息
6. 用户可以查找附近的朋友

### 2. 技术实现流程
1. 前端显示位置模式选择对话框
2. 根据用户选择加载相应的定位方法
3. 虚拟定位使用地图组件进行位置选择
4. 位置数据通过API发送到后端
5. 后端保存位置信息并标记位置类型
6. 查找附近用户时包含虚拟位置信息

## API接口

### 创建/更新位置
```javascript
POST /api/where-is-my-friends/locations
{
  "latitude": 39.9042,
  "longitude": 116.4074,
  "is_virtual": true,
  "virtual_address": "北京市朝阳区"
}
```

### 查找附近用户
```javascript
GET /api/where-is-my-friends/locations/nearby?latitude=39.9042&longitude=116.4074&distance=50
```

返回数据包含虚拟位置标识：
```json
{
  "users": [
    {
      "username": "user1",
      "distance": 2.5,
      "is_virtual": true,
      "virtual_address": "北京市朝阳区",
      "location_type": "virtual"
    }
  ]
}
```

## 隐私保护策略

### 1. 真实位置保护
- 添加±500米的随机噪声
- 不存储精确的GPS坐标

### 2. 虚拟位置优势
- 用户完全控制位置信息
- 可以选择公共场所作为定位点
- 不泄露任何真实位置信息

### 3. 数据显示
- 在用户列表中显示虚拟位置标识 🛡️
- 明确标注使用虚拟定位的用户

## 故障排除

### 1. 地图不显示
- 检查API密钥是否正确配置
- 确认网络连接正常
- 查看浏览器控制台错误信息

### 2. 定位失败
- 检查浏览器位置权限设置
- 确认设备GPS服务开启
- 尝试使用虚拟定位作为替代方案

### 3. 样式问题
- 确认CSS文件正确加载
- 检查响应式设计在移动设备上的表现

## 升级和迁移

### 从旧版本升级
1. 运行数据库迁移：
   ```bash
   rails db:migrate
   ```
2. 重启Discourse服务
3. 在管理后台启用虚拟定位功能
4. 配置地图服务提供商和API密钥

### 数据迁移
现有用户的位置数据会自动标记为`location_type: 'real'`，无需手动处理。

## 开发说明

### 前端组件
- `VirtualLocationPicker`：地图选择器组件
- `MapManager`：地图管理类，支持多种地图服务
- `GeocodingHelper`：地址解析工具类

### 后端模型
- `UserLocation`：用户位置模型，支持虚拟和真实位置
- `LocationsController`：位置API控制器

### 样式文件
- 模态对话框样式
- 地图容器样式
- 响应式设计适配

## 未来计划

1. **地图服务扩展**：支持更多地图服务提供商
2. **位置收藏**：允许用户收藏常用的虚拟位置
3. **群组定位**：支持群组内的虚拟位置共享
4. **位置历史**：记录用户的位置使用历史（可选）

## 支持与反馈

如果您在使用虚拟定位功能时遇到问题，请：
1. 查看本文档的故障排除部分
2. 检查Discourse日志文件
3. 在项目仓库提交Issue

---

**注意**：虚拟定位功能需要用户的理解和正确使用。建议在社区规则中说明虚拟定位的使用场景和限制。 
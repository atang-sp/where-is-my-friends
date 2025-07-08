# Where Is My Friends - Discourse Plugin

一个Discourse插件，允许用户发现附近的朋友，同时保护用户隐私。

## 功能特性

- 🔒 **隐私保护**: 用户位置信息会被模糊化处理（±500米随机偏移）
- 📍 **位置分享**: 用户可以主动分享自己的位置
- 🔍 **附近搜索**: 搜索指定距离内的其他用户
- 🎯 **距离选择**: 支持1km到50km的搜索范围
- 📱 **响应式设计**: 支持移动端和桌面端
- 🌐 **国际化**: 支持中文界面

## 安装

1. 将插件文件夹复制到 `plugins/` 目录
2. 在Discourse管理后台启用插件
3. 运行数据库迁移：`bundle exec rake db:migrate`

## 使用方法

1. 用户访问 `/where-is-my-friends` 页面
2. 点击"分享我的位置"按钮，允许浏览器获取位置
3. 选择搜索距离（1-50公里）
4. 查看附近的朋友列表

## 隐私保护

- 位置坐标会添加随机偏移（±500米）
- 只显示模糊距离，不显示精确坐标
- 用户可以随时移除位置信息
- 位置信息仅用于匹配附近用户

## 技术实现

- **后端**: Ruby on Rails, PostgreSQL
- **前端**: Ember.js, SCSS
- **位置计算**: Haversine公式
- **API**: RESTful API设计

## 配置

在Discourse管理后台可以配置：
- 插件启用/禁用
- 最大搜索距离限制
- 位置模糊化程度

## 开发

### 目录结构
```
where-is-my-friends/
├── plugin.rb                    # 插件主文件
├── README.md                    # 说明文档
├── app/                         # 后端代码
│   ├── controllers/            # 控制器
│   ├── models/                 # 模型
│   └── serializers/            # 序列化器
├── assets/                      # 前端资源
│   ├── javascripts/            # JavaScript文件
│   └── stylesheets/            # 样式文件
├── config/                      # 配置文件
│   └── locales/                # 国际化文件
└── db/                         # 数据库迁移
    └── migrate/
```

### 开发命令
```bash
# 运行迁移
bundle exec rake db:migrate

# 重启Discourse
./launcher restart app

# 查看日志
./launcher logs app
```

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request！

## 更新日志

### v0.1.0
- 初始版本
- 基础位置分享功能
- 附近用户搜索
- 隐私保护机制 # where-is-my-friends

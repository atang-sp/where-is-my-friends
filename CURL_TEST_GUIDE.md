# Where-Is-My-Friends API 测试指南

本指南提供使用curl命令测试where-is-my-friends插件API的方法。

## 🚨 重要：CSRF令牌

Discourse要求所有POST、PUT、DELETE请求包含CSRF令牌以防止跨站请求伪造攻击。如果遇到"BAD CSRF"错误，请按照以下步骤获取和使用CSRF令牌。

## 📋 测试脚本

### 1. 快速测试脚本
```bash
chmod +x quick-curl-test.sh
./quick-curl-test.sh
```

### 2. 完整测试脚本
```bash
chmod +x test-api-with-curl.sh
./test-api-with-curl.sh
```

### 3. 手动测试指南
```bash
chmod +x manual-curl-test.sh
./manual-curl-test.sh
```

## 🔧 手动curl测试步骤

### 步骤1: 获取CSRF令牌
```bash
# 获取会话和CSRF令牌
curl -s -c cookies.txt http://localhost:3000

# 从响应中提取CSRF令牌
CSRF_TOKEN=$(curl -s http://localhost:3000 | grep -o 'name="csrf-token" content="[^"]*"' | cut -d'"' -f4)
echo "CSRF Token: $CSRF_TOKEN"
```

### 步骤2: 测试GET请求（不需要CSRF）
```bash
curl -s -b cookies.txt http://localhost:3000/api/where-is-my-friends
```

### 步骤3: 测试POST请求（需要CSRF令牌）
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt \
  -d '{"latitude": 39.9042, "longitude": 116.4074}' \
  http://localhost:3000/api/where-is-my-friends/locations
```

### 步骤4: 测试附近用户查找
```bash
curl -s -b cookies.txt "http://localhost:3000/api/where-is-my-friends/locations/nearby?latitude=39.9042&longitude=116.4074&distance=50"
```

### 步骤5: 测试DELETE请求（需要CSRF令牌）
```bash
curl -X DELETE \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -b cookies.txt \
  http://localhost:3000/api/where-is-my-friends/locations
```

## 🐛 常见问题

### CSRF令牌获取失败
- 确保Discourse服务正在运行
- 检查服务URL是否正确
- 某些配置可能需要先登录Discourse

### 权限错误
- 某些API端点可能需要用户登录
- 检查Discourse的权限设置

### 连接错误
- 确保Discourse服务在localhost:4200运行
- 检查防火墙设置

## 📊 预期响应

### 成功响应示例
```json
{
  "location": {
    "latitude": 39.9042,
    "longitude": 116.4074,
    "updated_at": "2024-01-01T12:00:00Z"
  }
}
```

### 错误响应示例
```json
{
  "error": "Invalid coordinates"
}
```

## 🔍 诊断脚本

如果curl测试失败，运行诊断脚本检查系统状态：

```bash
chmod +x linux-geolocation-diagnostic.sh
./linux-geolocation-diagnostic.sh
```

## 💡 测试建议

1. **先测试GET请求** - 确认API端点可访问
2. **检查CSRF令牌** - 确保正确获取和使用
3. **验证坐标格式** - 使用有效的经纬度值
4. **测试错误处理** - 尝试无效数据
5. **检查响应格式** - 确认JSON格式正确

## 🎯 测试目标

- ✅ API端点可访问
- ✅ CSRF令牌正常工作
- ✅ 位置创建功能正常
- ✅ 位置查询功能正常
- ✅ 附近用户查找功能正常
- ✅ 位置删除功能正常
- ✅ 错误处理正常

如果curl测试全部通过，说明后端API功能正常，问题可能在于前端浏览器环境。 
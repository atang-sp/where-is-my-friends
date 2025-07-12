#!/bin/bash

# 快速API测试脚本（带CSRF支持）
echo "🚀 快速API测试（带CSRF支持）"

BASE_URL="http://localhost:3000"
API_BASE="$BASE_URL/api/where-is-my-friends"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 创建临时cookie文件
COOKIE_FILE=$(mktemp)
CSRF_TOKEN=""

echo -e "${BLUE}🔍 获取CSRF令牌...${NC}"

# 获取会话和CSRF令牌
SESSION_RESPONSE=$(curl -s -c "$COOKIE_FILE" "$BASE_URL")
CSRF_TOKEN=$(echo "$SESSION_RESPONSE" | grep -o 'name="csrf-token" content="[^"]*"' | cut -d'"' -f4)

if [ -z "$CSRF_TOKEN" ]; then
    echo -e "${YELLOW}⚠️ 无法获取CSRF令牌，尝试使用默认会话${NC}"
    # 尝试从cookie中获取
    CSRF_TOKEN=$(grep -o 'csrf-token=[^;]*' "$COOKIE_FILE" | cut -d'=' -f2 | head -1)
fi

if [ -z "$CSRF_TOKEN" ]; then
    echo -e "${RED}❌ 无法获取CSRF令牌，测试可能失败${NC}"
    echo -e "${YELLOW}💡 提示：确保Discourse服务正在运行且可访问${NC}"
else
    echo -e "${GREEN}✅ CSRF令牌获取成功${NC}"
fi

echo "测试基础连接..."
curl -s "$BASE_URL" > /dev/null && echo "✅ 服务连接正常" || echo "❌ 服务连接失败"

echo -e "\n测试API端点..."
curl -s -b "$COOKIE_FILE" "$API_BASE" && echo "✅ API端点正常" || echo "❌ API端点失败"

echo -e "\n测试位置创建..."
if [ -n "$CSRF_TOKEN" ]; then
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: $CSRF_TOKEN" \
        -b "$COOKIE_FILE" \
        -d '{"latitude": 39.9042, "longitude": 116.4074}' \
        "$API_BASE/locations" && echo "✅ 位置创建正常" || echo "❌ 位置创建失败"
else
    echo -e "${YELLOW}⚠️ 跳过位置创建测试（无CSRF令牌）${NC}"
fi

echo -e "\n测试附近用户查找..."
curl -s -b "$COOKIE_FILE" "$API_BASE/locations/nearby?latitude=39.9042&longitude=116.4074&distance=50" && echo "✅ 附近用户查找正常" || echo "❌ 附近用户查找失败"

echo -e "\n测试位置删除..."
if [ -n "$CSRF_TOKEN" ]; then
    curl -s -X DELETE \
        -H "X-CSRF-Token: $CSRF_TOKEN" \
        -b "$COOKIE_FILE" \
        "$API_BASE/locations" && echo "✅ 位置删除正常" || echo "❌ 位置删除失败"
else
    echo -e "${YELLOW}⚠️ 跳过位置删除测试（无CSRF令牌）${NC}"
fi

# 清理临时文件
rm -f "$COOKIE_FILE"

echo -e "\n✅ 快速测试完成" 
#!/bin/bash

# 手动curl测试脚本
# 提供逐步的curl命令来测试API

echo "🔧 手动curl测试指南"
echo "=================="

BASE_URL="http://localhost:3000"
API_BASE="$BASE_URL/api/where-is-my-friends"

echo -e "\n${BLUE}步骤1: 获取会话和CSRF令牌${NC}"
echo "执行以下命令："
echo "curl -s -c cookies.txt $BASE_URL"
echo ""
echo "然后从响应中提取CSRF令牌："
echo "curl -s $BASE_URL | grep -o 'name=\"csrf-token\" content=\"[^\"]*\"' | cut -d'\"' -f4"
echo ""

echo -e "${BLUE}步骤2: 测试GET请求（不需要CSRF）${NC}"
echo "curl -s -b cookies.txt $API_BASE"
echo ""

echo -e "${BLUE}步骤3: 测试POST请求（需要CSRF令牌）${NC}"
echo "将下面的TOKEN替换为实际的CSRF令牌："
echo "curl -X POST \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -H \"X-CSRF-Token: TOKEN\" \\"
echo "  -b cookies.txt \\"
echo "  -d '{\"latitude\": 39.9042, \"longitude\": 116.4074}' \\"
echo "  $API_BASE/locations"
echo ""

echo -e "${BLUE}步骤4: 测试附近用户查找${NC}"
echo "curl -s -b cookies.txt \"$API_BASE/locations/nearby?latitude=39.9042&longitude=116.4074&distance=50\""
echo ""

echo -e "${BLUE}步骤5: 测试DELETE请求（需要CSRF令牌）${NC}"
echo "curl -X DELETE \\"
echo "  -H \"X-CSRF-Token: TOKEN\" \\"
echo "  -b cookies.txt \\"
echo "  $API_BASE/locations"
echo ""

echo -e "${YELLOW}💡 提示：${NC}"
echo "1. 确保Discourse服务在 $BASE_URL 运行"
echo "2. 如果获取不到CSRF令牌，检查服务是否正常运行"
echo "3. 某些Discourse配置可能需要登录才能访问API"
echo "4. 如果仍然出现CSRF错误，可能需要先登录Discourse" 
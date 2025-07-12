#!/bin/bash

# 位置API测试脚本（带CSRF支持）
# 使用curl测试where-is-my-friends插件的API功能

echo "🌍 Where-Is-My-Friends API 测试脚本（带CSRF支持）"
echo "=============================================="

# 配置
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

# 获取CSRF令牌函数
get_csrf_token() {
    echo -e "\n${BLUE}🔍 获取CSRF令牌...${NC}"
    
    # 获取会话和CSRF令牌
    SESSION_RESPONSE=$(curl -s -c "$COOKIE_FILE" "$BASE_URL")
    CSRF_TOKEN=$(echo "$SESSION_RESPONSE" | grep -o 'name="csrf-token" content="[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$CSRF_TOKEN" ]; then
        echo -e "${YELLOW}⚠️ 无法从HTML获取CSRF令牌，尝试从cookie中获取${NC}"
        # 尝试从cookie中获取
        CSRF_TOKEN=$(grep -o 'csrf-token=[^;]*' "$COOKIE_FILE" | cut -d'=' -f2 | head -1)
    fi
    
    if [ -z "$CSRF_TOKEN" ]; then
        echo -e "${RED}❌ 无法获取CSRF令牌${NC}"
        echo -e "${YELLOW}💡 提示：确保Discourse服务正在运行且可访问${NC}"
        return 1
    else
        echo -e "${GREEN}✅ CSRF令牌获取成功: ${CSRF_TOKEN:0:10}...${NC}"
        return 0
    fi
}

# 测试函数
test_api() {
    local test_name="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    
    echo -e "\n${BLUE}🔍 测试: $test_name${NC}"
    echo "URL: $url"
    echo "方法: $method"
    
    if [ -n "$data" ]; then
        echo "数据: $data"
    fi
    
    # 执行请求
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -b "$COOKIE_FILE" "$url")
    elif [ "$method" = "POST" ]; then
        if [ -n "$CSRF_TOKEN" ]; then
            response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
                -H "Content-Type: application/json" \
                -H "X-CSRF-Token: $CSRF_TOKEN" \
                -b "$COOKIE_FILE" \
                -d "$data" "$url")
        else
            echo -e "${YELLOW}⚠️ 跳过POST请求（无CSRF令牌）${NC}"
            return 1
        fi
    elif [ "$method" = "DELETE" ]; then
        if [ -n "$CSRF_TOKEN" ]; then
            response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X DELETE \
                -H "X-CSRF-Token: $CSRF_TOKEN" \
                -b "$COOKIE_FILE" "$url")
        else
            echo -e "${YELLOW}⚠️ 跳过DELETE请求（无CSRF令牌）${NC}"
            return 1
        fi
    fi
    
    # 分离响应体和状态码
    http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    response_body=$(echo "$response" | sed '/HTTP_STATUS:/d')
    
    echo -e "\n${YELLOW}响应状态: $http_status${NC}"
    
    if [ "$http_status" = "200" ] || [ "$http_status" = "201" ]; then
        echo -e "${GREEN}✅ 成功${NC}"
        echo "响应内容:"
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
    else
        echo -e "${RED}❌ 失败${NC}"
        echo "错误响应:"
        echo "$response_body"
    fi
    
    echo "----------------------------------------"
}

# 检查依赖
echo "📋 检查依赖..."
if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ curl 未安装${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️ jq 未安装，将显示原始JSON${NC}"
fi

# 检查服务是否运行
echo -e "\n${BLUE}🔍 检查服务状态...${NC}"
if curl -s "$BASE_URL" > /dev/null; then
    echo -e "${GREEN}✅ 服务正在运行${NC}"
else
    echo -e "${RED}❌ 服务未运行或无法访问${NC}"
    echo "请确保Discourse服务在 $BASE_URL 运行"
    exit 1
fi

# 获取CSRF令牌
if ! get_csrf_token; then
    echo -e "${YELLOW}⚠️ 继续测试，但POST/DELETE请求可能失败${NC}"
fi

# 测试1: 获取初始数据
test_api "获取初始数据" "GET" "$API_BASE"

# 测试2: 创建位置（使用测试坐标）
echo -e "\n${BLUE}📍 测试位置数据${NC}"
echo "使用测试坐标：北京天安门 (39.9042, 116.4074)"

test_api "创建位置" "POST" "$API_BASE/locations" '{"latitude": 39.9042, "longitude": 116.4074}'

# 测试3: 再次获取数据（应该包含位置）
test_api "获取数据（包含位置）" "GET" "$API_BASE"

# 测试4: 查找附近用户
test_api "查找附近用户" "GET" "$API_BASE/locations/nearby?latitude=39.9042&longitude=116.4074&distance=50"

# 测试5: 使用不同的测试坐标
echo -e "\n${BLUE}📍 测试不同坐标${NC}"
echo "使用测试坐标：上海外滩 (31.2304, 121.4737)"

test_api "创建位置（上海）" "POST" "$API_BASE/locations" '{"latitude": 31.2304, "longitude": 121.4737}'

# 测试6: 查找附近用户（上海）
test_api "查找附近用户（上海）" "GET" "$API_BASE/locations/nearby?latitude=31.2304&longitude=121.4737&distance=50"

# 测试7: 删除位置
test_api "删除位置" "DELETE" "$API_BASE/locations"

# 测试8: 最终获取数据（应该不包含位置）
test_api "获取最终数据" "GET" "$API_BASE"

# 测试9: 错误处理测试
echo -e "\n${BLUE}🚨 错误处理测试${NC}"

# 无效坐标
test_api "无效坐标测试" "POST" "$API_BASE/locations" '{"latitude": 999, "longitude": 999}'

# 缺少参数
test_api "缺少参数测试" "POST" "$API_BASE/locations" '{"latitude": 39.9042}'

# 无效距离
test_api "无效距离测试" "GET" "$API_BASE/locations/nearby?latitude=39.9042&longitude=116.4074&distance=999"

# 清理临时文件
rm -f "$COOKIE_FILE"

echo -e "\n${GREEN}✅ API测试完成！${NC}"
echo -e "\n${BLUE}📊 测试总结：${NC}"
echo "1. 服务连接性"
echo "2. CSRF令牌获取"
echo "3. 位置创建功能"
echo "4. 位置查询功能"
echo "5. 附近用户查找功能"
echo "6. 位置删除功能"
echo "7. 错误处理功能"

echo -e "\n${YELLOW}💡 如果API测试成功，说明后端功能正常，问题可能在于：${NC}"
echo "- 浏览器地理位置API权限"
echo "- HTTPS要求（Chrome需要HTTPS）"
echo "- 设备位置服务设置"
echo "- 网络连接问题" 
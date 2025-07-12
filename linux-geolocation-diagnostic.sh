#!/bin/bash

# Kubuntu/Linux 地理位置诊断脚本
echo "🐧 Kubuntu/Linux 地理位置诊断"
echo "=============================="

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${BLUE}📋 系统信息${NC}"
echo "操作系统: $(lsb_release -d | cut -f2)"
echo "内核版本: $(uname -r)"
echo "架构: $(uname -m)"

echo -e "\n${BLUE}🌐 网络连接${NC}"
# 检查网络连接
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ 网络连接正常${NC}"
else
    echo -e "${RED}❌ 网络连接异常${NC}"
fi

# 检查DNS解析
if nslookup google.com > /dev/null 2>&1; then
    echo -e "${GREEN}✅ DNS解析正常${NC}"
else
    echo -e "${RED}❌ DNS解析异常${NC}"
fi

echo -e "\n${BLUE}🔧 位置服务检查${NC}"

# 检查位置服务相关包
echo "检查位置服务包..."
if dpkg -l | grep -q "geoclue"; then
    echo -e "${GREEN}✅ GeoClue 已安装${NC}"
else
    echo -e "${YELLOW}⚠️ GeoClue 未安装${NC}"
fi

if dpkg -l | grep -q "gpsd"; then
    echo -e "${GREEN}✅ GPSD 已安装${NC}"
else
    echo -e "${YELLOW}⚠️ GPSD 未安装${NC}"
fi

# 检查位置服务状态
echo -e "\n${BLUE}🔄 服务状态${NC}"
if systemctl is-active --quiet geoclue; then
    echo -e "${GREEN}✅ GeoClue 服务正在运行${NC}"
else
    echo -e "${RED}❌ GeoClue 服务未运行${NC}"
    echo "尝试启动 GeoClue..."
    sudo systemctl start geoclue 2>/dev/null && echo -e "${GREEN}✅ GeoClue 已启动${NC}" || echo -e "${RED}❌ 无法启动 GeoClue${NC}"
fi

# 检查位置权限
echo -e "\n${BLUE}🔐 位置权限检查${NC}"
if command -v gsettings > /dev/null; then
    location_enabled=$(gsettings get org.gnome.system.location enabled 2>/dev/null || echo "unknown")
    if [ "$location_enabled" = "true" ]; then
        echo -e "${GREEN}✅ 系统位置服务已启用${NC}"
    elif [ "$location_enabled" = "false" ]; then
        echo -e "${RED}❌ 系统位置服务已禁用${NC}"
    else
        echo -e "${YELLOW}⚠️ 无法检查系统位置服务状态${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ 无法检查位置权限（gsettings 不可用）${NC}"
fi

# 检查浏览器
echo -e "\n${BLUE}🌐 浏览器检查${NC}"
if command -v google-chrome > /dev/null; then
    echo -e "${GREEN}✅ Google Chrome 已安装${NC}"
    chrome_version=$(google-chrome --version)
    echo "版本: $chrome_version"
else
    echo -e "${YELLOW}⚠️ Google Chrome 未安装${NC}"
fi

if command -v firefox > /dev/null; then
    echo -e "${GREEN}✅ Firefox 已安装${NC}"
    firefox_version=$(firefox --version)
    echo "版本: $firefox_version"
else
    echo -e "${YELLOW}⚠️ Firefox 未安装${NC}"
fi

# 检查HTTPS证书
echo -e "\n${BLUE}🔒 HTTPS 检查${NC}"
if curl -s -k "https://localhost:4200" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ HTTPS 端点可访问${NC}"
else
    echo -e "${YELLOW}⚠️ HTTPS 端点不可访问${NC}"
fi

# 检查防火墙
echo -e "\n${BLUE}🔥 防火墙检查${NC}"
if command -v ufw > /dev/null; then
    ufw_status=$(sudo ufw status 2>/dev/null | head -1)
    echo "UFW 状态: $ufw_status"
fi

# 检查端口
echo -e "\n${BLUE}🔌 端口检查${NC}"
if netstat -tlnp 2>/dev/null | grep -q ":4200"; then
    echo -e "${GREEN}✅ 端口 4200 正在监听${NC}"
else
    echo -e "${RED}❌ 端口 4200 未监听${NC}"
fi

# 检查系统时间
echo -e "\n${BLUE}⏰ 系统时间检查${NC}"
system_time=$(date)
echo "系统时间: $system_time"

# 检查时区
timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
echo "时区: $timezone"

echo -e "\n${BLUE}💡 建议${NC}"
echo "1. 确保系统位置服务已启用"
echo "2. 检查浏览器位置权限设置"
echo "3. 如果使用Chrome，确保使用HTTPS或localhost"
echo "4. 尝试在浏览器中访问 chrome://settings/content/location"
echo "5. 检查是否有防火墙阻止位置服务"

echo -e "\n${BLUE}🔧 修复命令${NC}"
echo "# 安装位置服务"
echo "sudo apt update"
echo "sudo apt install geoclue-2.0 gpsd"

echo -e "\n# 启动位置服务"
echo "sudo systemctl enable geoclue"
echo "sudo systemctl start geoclue"

echo -e "\n# 检查位置服务状态"
echo "systemctl status geoclue"

echo -e "\n${GREEN}✅ 诊断完成${NC}" 
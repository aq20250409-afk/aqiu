#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}aqiu - 一键安装${NC}"
echo -e "${BLUE}================================${NC}"

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ 此脚本必须以 root 身份运行${NC}"
    exit 1
fi

# 检查依赖
echo -e "${YELLOW}检查依赖...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}安装 git...${NC}"
    apt-get update && apt-get install -y git || yum install -y git
fi

# 克隆仓库
REPO_DIR="/tmp/aqiu-$(date +%s)"
echo -e "${YELLOW}克隆仓库到 $REPO_DIR...${NC}"
git clone https://github.com/aq20250409-afk/aqiu.git "$REPO_DIR" 2>/dev/null || {
    echo -e "${RED}✗ 克隆失败${NC}"
    exit 1
}

cd "$REPO_DIR"
echo -e "${GREEN}✓ 仓库克隆成功${NC}"

# 运行 setup.sh
echo -e "${YELLOW}启动安装向导...${NC}"
bash setup.sh

echo -e "${GREEN}✓ 安装完成${NC}"
echo -e "${BLUE}================================${NC}",
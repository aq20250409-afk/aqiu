#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以 root 身份运行"
        exit 1
    fi
}

detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "无法检测操作系统"
        exit 1
    fi
}

install_dependencies() {
    print_header "安装依赖"
    
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt-get update
        apt-get install -y curl wget python3 python3-pip
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        yum install -y curl wget python3 python3-pip
    else
        print_warning "不支持的操作系统: $OS，请手动安装 curl wget python3"
    fi
    
    print_success "依赖安装完成"
}

setup_relay() {
    print_header "中继机（本机）安装"
    
    echo -e "${YELLOW}选择运行模式：${NC}"
    echo "1) 启动登记服务（自动接收上游并配置）"
    echo "2) 生成配置模式（手动维护 upstream-ips.txt）"
    read -p "请选择 [1/2]: " relay_mode
    
    if [ "$relay_mode" == "1" ]; then
        print_header "启动中继登记服务"
        print_warning "按 Ctrl+C 可停止服务"
        python3 register-upstream-server.py
    elif [ "$relay_mode" == "2" ]; then
        print_header "生成配置模式"
        print_warning "请先编辑 upstream-ips.txt，每行一个出口机 IP"
        read -p "继续？ [y/n]: " continue_gen
        if [ "$continue_gen" == "y" ]; then
            python3 generate-config.py
            print_success "配置已生成"
        fi
    else
        print_error "无效的选择"
        exit 1
    fi
}

setup_upstream() {
    print_header "代理出口机（上游）安装"
    
    echo -e "${YELLOW}选择中继配置方式：${NC}"
    echo "1) 自动上报到默认中继 (47.243.170.64:9999)"
    echo "2) 指定自定义中继地址"
    echo "3) 仅安装，不自动上报"
    read -p "请选择 [1/2/3]: " upstream_mode
    
    case $upstream_mode in
        1)
            print_header "安装出口机（默认中继）"
            bash install-upstream-hy2.sh
            ;;
        2)
            read -p "请输入中继地址 (例: 192.168.1.100:9999): " relay_addr
            print_header "安装出口机（自定义中继）"
            RELAY_REGISTER_URL="http://">${relay_addr}/register?ip=" bash install-upstream-hy2.sh
            ;;
        3)
            print_header "安装出口机（不上报）"
            RELAY_REGISTER_URL= bash install-upstream-hy2.sh
            ;;
        *)
            print_error "无效的选择"
            exit 1
            ;;
    esac
}

show_menu() {
    echo
    print_header "aqiu - Hy2 中继与出口节点一键安装"
    echo
    echo -e "${YELLOW}请选择角色：${NC}"
    echo "1) 中继机（接收出口机上报，生成配置）"
    echo "2) 代理出口机（连接到中继��提供代理服务）"
    echo "3) 退出"
    echo
    read -p "请选择 [1/2/3]: " choice
}

main() {
    check_root
    detect_system
    
    while true; do
        show_menu
        
        case $choice in
            1)
                install_dependencies
                setup_relay
                ;;
            2)
                install_dependencies
                setup_upstream
                ;;
            3)
                print_success "退出安装"
                exit 0
                ;;
            *)
                print_error "无效的选择，请重试"
                ;;
        esac
        
        echo
        read -p "是否继续? [y/n]: " cont
        if [ "$cont" != "y" ]; then
            print_success "安装完成"
            exit 0
        fi
    done
}

# Run main
main

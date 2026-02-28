#!/bin/bash
# 从仓库获取脚本并一键 setup
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/aq20250409-afk/aqiu/main/setup.sh | sudo bash -s -- --upstream   # 出口机：安装并上报中继
#   curl -fsSL https://raw.githubusercontent.com/aq20250409-afk/aqiu/main/setup.sh | sudo bash -s -- --relay     # 中继机：拉取脚本并启动登记服务
#   curl -fsSL https://raw.githubusercontent.com/aq20250409-afk/aqiu/main/setup.sh | sudo bash -s -- --fetch      # 仅拉取脚本到本地，不执行
set -e

REPO_RAW="https://raw.githubusercontent.com/aq20250409-afk/aqiu/main"
INSTALL_DIR="${INSTALL_DIR:-/root/sing-box-helper}"
FILES="install-upstream-hy2.sh register-upstream-server.py upstream-ips.txt generate-config.py install-singbox-hy2.sh"

fetch() {
  echo "[*] 拉取脚本到 ${INSTALL_DIR}"
  mkdir -p "$INSTALL_DIR"
  for f in $FILES; do
    echo "    -> $f"
    curl -fsSL "${REPO_RAW}/${f}" -o "${INSTALL_DIR}/${f}" || true
  done
  chmod +x "${INSTALL_DIR}/install-upstream-hy2.sh" "${INSTALL_DIR}/install-singbox-hy2.sh" 2>/dev/null || true
  echo "[*] 完成"
}

setup_upstream() {
  # 从开始就使用中继 SOCKS5 代理，拉取脚本与后续安装均走代理
  RELAY_SOCKS="${SOCKS5_PROXY:-47.243.170.64:9998}"
  export all_proxy="socks5h://${RELAY_SOCKS}"
  export https_proxy="socks5h://${RELAY_SOCKS}"
  export http_proxy="socks5h://${RELAY_SOCKS}"
  export SOCKS5_PROXY="${RELAY_SOCKS}"
  echo "[*] 已启用中继代理: ${RELAY_SOCKS}（拉取脚本与安装均经中继）"
  fetch
  echo "[*] 执行出口机安装（上报中继）"
  exec bash "${INSTALL_DIR}/install-upstream-hy2.sh"
}

setup_relay() {
  fetch
  echo "[*] 启动中继登记服务（端口 9999）"
  exec sudo python3 "${INSTALL_DIR}/register-upstream-server.py"
}

usage() {
  echo "用法: $0 --upstream | --relay | --fetch"
  echo "  --upstream  出口机：拉取脚本并执行 install-upstream-hy2.sh（安装 Hy2 入站并上报中继）"
  echo "  --relay     中继机：拉取脚本并启动 register-upstream-server.py（登记服务）"
  echo "  --fetch     仅拉取脚本到 ${INSTALL_DIR}，不执行"
}

case "${1:-}" in
  --upstream) setup_upstream ;;
  --relay)    setup_relay ;;
  --fetch)    fetch ;;
  *)          usage ;;
esac

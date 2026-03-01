#!/bin/bash
# 从仓库或中继获取脚本并一键 setup
# 用法（推荐从中继拉取，不卡）:
#   curl -fsSL http://中继IP:9999/files/setup.sh | sudo bash -s -- --upstream   # 出口机：从中继拉脚本并安装
#   curl -fsSL https://raw.githubusercontent.com/aq20250409-afk/aqiu/main/setup.sh | sudo bash -s -- --upstream  # 从 GitHub（可能慢/卡）
#   curl -fsSL http://中继IP:9999/files/setup.sh | sudo bash -s -- --relay     # 中继机：拉取脚本并启动登记服务
#   curl -fsSL http://中继IP:9999/files/setup.sh | sudo bash -s -- --fetch      # 仅拉取脚本到本地
set -e

REPO_RAW="https://raw.githubusercontent.com/aq20250409-afk/aqiu/main"
# 优先从中继拉取（快、不卡）；设为空则从 GitHub 拉
FETCH_BASE="${RELAY_FILES:-http://47.243.170.64:9999/files}"
INSTALL_DIR="${INSTALL_DIR:-/root/sing-box-helper}"
FILES="install-upstream-hy2.sh register-upstream-server.py upstream-ips.txt generate-config.py install-singbox-hy2.sh"

fetch() {
  echo "[*] 拉取脚本到 ${INSTALL_DIR}"
  mkdir -p "$INSTALL_DIR"
  BASE="${FETCH_BASE:-$REPO_RAW}"
  [ -n "$FETCH_BASE" ] && echo "[*] 从中继拉取: ${BASE}" || echo "[*] 从 GitHub 拉取"
  for f in $FILES; do
    echo "    -> $f"
    curl -fsSL "${BASE}/${f}" -o "${INSTALL_DIR}/${f}" --connect-timeout 15 --max-time 30 || true
  done
  chmod +x "${INSTALL_DIR}/install-upstream-hy2.sh" "${INSTALL_DIR}/install-singbox-hy2.sh" 2>/dev/null || true
  echo "[*] 完成"
}

setup_upstream() {
  # 先拉取脚本（从中继则直连，不设代理）
  fetch
  # 再启用中继 SOCKS5，安装 sing-box 等走代理
  RELAY_SOCKS="${SOCKS5_PROXY:-47.243.170.64:9998}"
  export all_proxy="socks5h://${RELAY_SOCKS}"
  export https_proxy="socks5h://${RELAY_SOCKS}"
  export http_proxy="socks5h://${RELAY_SOCKS}"
  export SOCKS5_PROXY="${RELAY_SOCKS}"
  echo "[*] 已启用中继代理: ${RELAY_SOCKS}（安装 sing-box 等经中继）"
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

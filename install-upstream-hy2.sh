#!/bin/bash
# 代理出口机用：在出口机上运行本脚本，安装 sing-box + Hy2 入站（端口 9999，密码 aqiu，185Mbps），并自动启动
# 设置 RELAY_REGISTER_URL 后，出口机公网 IP 会自动上报到本机（中继机）登记；中继机收到后自动为该出口分配对应端口（30072、30073…）并写入配置，端口 9999/密码 aqiu/185Mbps 等均为默认
# 用法（在代理出口机上执行）:
#   sudo ./install-upstream-hy2.sh   # 默认自动上报到 47.243.170.64:9999 中继登记
#   sudo RELAY_REGISTER_URL='http://其他中继IP:9999/register?ip=' ./install-upstream-hy2.sh   # 指定其他中继
#   sudo RELAY_REGISTER_URL= ./install-upstream-hy2.sh   # 只安装不自动上报
set -e

# 默认中继登记地址（本机 47.243.170.64）；可通过环境变量 RELAY_REGISTER_URL 覆盖
RELAY_REGISTER_URL="${RELAY_REGISTER_URL:-http://47.243.170.64:9999/register?ip=}"
# 默认通过中继机 SOCKS5 代理 9998 加速下载；设为空则直连
SOCKS5_PROXY="${SOCKS5_PROXY:-47.243.170.64:9998}"

LISTEN_PORT=9999  # 与中继 register-upstream-server.py 的 OUTBOUND_PORT 一致
PASSWORD="aqiu"
UP_MBPS=185
DOWN_MBPS=185
CONFIG_DIR="/etc/sing-box"
CERT_PATH="$CONFIG_DIR/cert.pem"
KEY_PATH="$CONFIG_DIR/key.pem"

install_singbox() {
  if command -v sing-box &>/dev/null; then
    echo "[*] sing-box 已安装: $(sing-box version | head -1)"
    return 0
  fi
  echo "[*] 正在安装 sing-box..."
  if [[ -n "$SOCKS5_PROXY" ]]; then
    export all_proxy="socks5h://${SOCKS5_PROXY}"
    echo "[*] 使用中继 SOCKS5 代理加速: ${SOCKS5_PROXY}"
    curl --socks5-hostname "$SOCKS5_PROXY" -fsSL https://sing-box.app/install.sh | env all_proxy="socks5h://${SOCKS5_PROXY}" sh
  else
    curl -fsSL https://sing-box.app/install.sh | sh
  fi
  echo "[*] sing-box 安装完成"
}

setup_cert_and_dir() {
  mkdir -p "$CONFIG_DIR"
  if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
    echo "[*] 生成 TLS 证书..."
    tmpdir=$(mktemp -d)
    openssl ecparam -name prime256v1 -genkey -noout -out "$tmpdir/key.pem"
    openssl req -x509 -nodes -key "$tmpdir/key.pem" -out "$tmpdir/cert.pem" -subj "/CN=localhost" -days 3650
    cp "$tmpdir/cert.pem" "$CERT_PATH"
    cp "$tmpdir/key.pem" "$KEY_PATH"
    rm -rf "$tmpdir"
  fi
  chown -R sing-box:sing-box "$CONFIG_DIR" 2>/dev/null || true
}

generate_config() {
  python3 << PY
import json
c = {
  "log": {"level": "info"},
  "inbounds": [{
    "type": "hysteria2",
    "tag": "hy2-in",
    "listen": "::",
    "listen_port": $LISTEN_PORT,
    "up_mbps": $UP_MBPS,
    "down_mbps": $DOWN_MBPS,
    "users": [{"password": "$PASSWORD"}],
    "tls": {"enabled": True, "certificate_path": "$CERT_PATH", "key_path": "$KEY_PATH"}
  }],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"rules": [], "final": "direct"}
}
with open("$CONFIG_DIR/config.json", "w") as f:
    json.dump(c, f, indent=2)
PY
}

register_to_relay() {
  local my_ip
  # 获取出口机真实公网 IP 必须直连，不走代理
  my_ip=$(env -u all_proxy -u http_proxy -u https_proxy curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || env -u all_proxy -u http_proxy -u https_proxy curl -s --connect-timeout 5 icanhazip.com 2>/dev/null || true)
  echo "[*] 本机(出口机)公网 IP: ${my_ip:-无法获取}"
  if [[ -n "$RELAY_REGISTER_URL" && -n "$my_ip" ]]; then
    if env -u all_proxy -u http_proxy -u https_proxy curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${RELAY_REGISTER_URL}${my_ip}" | grep -q 200; then
      echo "[*] 已上报至本机(中继机)登记，中继将自动分配端口并写入默认配置"
    else
      echo "[!] 上报中继失败，请确认本机(中继机)已运行 register-upstream-server.py 且 RELAY_REGISTER_URL 正确"
    fi
  else
    echo "[*] 请将上述 IP 手动加入中继的 upstream-ips.txt，或设置 RELAY_REGISTER_URL='http://本机(中继机)IP:9999/register?ip=' 后重新运行以自动上报"
  fi
}

main() {
  [[ $EUID -ne 0 ]] && { echo "请使用 root 或 sudo 运行"; exit 1; }
  install_singbox
  setup_cert_and_dir
  generate_config
  chown sing-box:sing-box "$CONFIG_DIR/config.json" 2>/dev/null || true
  sing-box check -c "$CONFIG_DIR/config.json" || { echo "[!] 配置校验失败"; exit 1; }
  # 若无 systemd 单元则创建，再 enable/restart
  if ! systemctl cat sing-box.service &>/dev/null; then
    echo "[*] 未检测到 sing-box.service，创建 systemd 单元..."
    mkdir -p /etc/systemd/system
    cat > /etc/systemd/system/sing-box.service << 'SVC'
[Unit]
Description=sing-box service
After=network.target nss-lookup.target

[Service]
User=sing-box
StateDirectory=sing-box
ExecStart=/usr/bin/sing-box -D /var/lib/sing-box -c /etc/sing-box/config.json run
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SVC
    systemctl daemon-reload
  fi
  systemctl enable sing-box 2>/dev/null && systemctl restart sing-box 2>/dev/null && echo "[*] sing-box 已启动并开机自启" || { echo "[!] systemd 启动失败，请手动执行: sing-box run -c $CONFIG_DIR/config.json"; }
  echo "[*] 上游 Hy2 入站: 0.0.0.0:${LISTEN_PORT}  密码 ${PASSWORD}  上下行 ${UP_MBPS} Mbps (无用户名)"
  register_to_relay
  # 安装完成后移除代理，避免当前环境继续走代理
  unset all_proxy http_proxy https_proxy SOCKS5_PROXY 2>/dev/null || true
  echo "[*] 已移除代理环境，后续命令直连"
}

main "$@"

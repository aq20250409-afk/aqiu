#!/bin/bash
# 一键安装 sing-box + 200 个 Hy2 入站 + 自动启动，出站固定 28800/密码 aqiu/185Mbps
# 用法:
#   单节点出站(全部走同一上游): sudo ./install-singbox-hy2.sh
#   单节点指定上游:             sudo ./install-singbox-hy2.sh 114.55.139.72
#   多节点(每端口一个出站):     sudo ./install-singbox-hy2.sh /path/to/servers.txt
#   servers.txt: 每行一个上游地址(IP或域名)，200行对应端口30072-30271
set -e

OUTBOUND_PORT=28800
OUTBOUND_PASSWORD="aqiu"
OUTBOUND_UP_MBPS=185
OUTBOUND_DOWN_MBPS=185
INBOUND_USER="aqiu"
INBOUND_PASSWORD="aqiu"
INBOUND_UP_MBPS=185
INBOUND_DOWN_MBPS=185
PORT_START=30072
PORT_COUNT=200
CONFIG_DIR="/etc/sing-box"
CERT_PATH="$CONFIG_DIR/cert.pem"
KEY_PATH="$CONFIG_DIR/key.pem"

# ---------- 安装 sing-box ----------
install_singbox() {
  if command -v sing-box &>/dev/null; then
    echo "[*] sing-box 已安装: $(sing-box version | head -1)"
    return 0
  fi
  echo "[*] 正在安装 sing-box..."
  curl -fsSL https://sing-box.app/install.sh | sh
  echo "[*] sing-box 安装完成"
}

# ---------- 证书与目录 ----------
setup_cert_and_dir() {
  mkdir -p "$CONFIG_DIR"
  if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
    echo "[*] 生成 TLS 证书..."
    (cd "$(mktemp -d)" && \
     openssl ecparam -name prime256v1 -genkey -noout -out key.pem && \
     openssl req -x509 -nodes -key key.pem -out cert.pem -subj "/CN=localhost" -days 3650) && \
     mv "$(mktemp -d)/key.pem" "$KEY_PATH" && \
     mv "$(mktemp -d)/cert.pem" "$CERT_PATH"
    # 上面 mv 会失败因为 mktemp -d 每次不同，改用直接写
    local tmpdir
    tmpdir=$(mktemp -d)
    openssl ecparam -name prime256v1 -genkey -noout -out "$tmpdir/key.pem"
    openssl req -x509 -nodes -key "$tmpdir/key.pem" -out "$tmpdir/cert.pem" -subj "/CN=localhost" -days 3650
    cp "$tmpdir/cert.pem" "$CERT_PATH"
    cp "$tmpdir/key.pem" "$KEY_PATH"
    rm -rf "$tmpdir"
  fi
  chown -R sing-box:sing-box "$CONFIG_DIR" 2>/dev/null || true
}

# ---------- 生成 config.json ----------
# 参数: 1=默认单节点 | 单节点IP | 多节点文件路径
generate_config() {
  local single_default="114.55.139.72"
  local servers=()
  if [[ $# -eq 0 ]]; then
    servers=("$single_default")
  elif [[ $# -eq 1 && -f "$1" ]]; then
    mapfile -t servers < "$1"
    servers=("${servers[@]//[[:space:]]/}")
    [[ ${#servers[@]} -eq 0 ]] && servers=("$single_default")
  else
    servers=("${1:-$single_default}")
  fi

  python3 << PY
import json, os
config_dir = "$CONFIG_DIR"
cert_path = "$CERT_PATH"
key_path = "$KEY_PATH"
port_start = $PORT_START
port_count = $PORT_COUNT
servers = [s.strip() for s in """${servers[*]}""".split() if s.strip()]
if not servers:
    servers = ["114.55.139.72"]

# 入站 30072..30271
inbounds = []
for i in range(port_count):
    p = port_start + i
    inbounds.append({
        "type": "hysteria2",
        "tag": f"hy2-in-{p}",
        "listen": "::",
        "listen_port": p,
        "up_mbps": $INBOUND_UP_MBPS,
        "down_mbps": $INBOUND_DOWN_MBPS,
        "users": [{"name": "$INBOUND_USER", "password": "$INBOUND_PASSWORD"}],
        "tls": {"enabled": True, "certificate_path": cert_path, "key_path": key_path},
    })

# 出站: 1 个则全部走它；200 个则 1:1
outbounds = []
for i, srv in enumerate(servers):
    tag = f"hy2-out-{port_start + i}" if len(servers) > 1 else "hy2-out"
    outbounds.append({
        "type": "hysteria2",
        "tag": tag,
        "server": srv,
        "server_port": $OUTBOUND_PORT,
        "password": "$OUTBOUND_PASSWORD",
        "up_mbps": $OUTBOUND_UP_MBPS,
        "down_mbps": $OUTBOUND_DOWN_MBPS,
        "tls": {"enabled": True, "server_name": srv, "insecure": True},
    })
outbounds.append({"type": "direct", "tag": "direct"})

# 路由
rules = []
if len(servers) == 1:
    rules.append({"inbound": [f"hy2-in-{port_start + i}" for i in range(port_count)], "action": "route", "outbound": "hy2-out"})
else:
    for i in range(min(port_count, len(servers))):
        rules.append({"inbound": [f"hy2-in-{port_start + i}"], "action": "route", "outbound": f"hy2-out-{port_start + i}"})
    if len(servers) < port_count:
        for i in range(len(servers), port_count):
            rules.append({"inbound": [f"hy2-in-{port_start + i}"], "action": "route", "outbound": "hy2-out-" + str(port_start)})

config = {
    "log": {"level": "info"},
    "inbounds": inbounds,
    "outbounds": outbounds,
    "route": {"rules": rules, "final": "direct"},
}
with open(os.path.join(config_dir, "config.json"), "w") as f:
    json.dump(config, f, indent=2)
print(f"Generated: {len(inbounds)} inbounds, {len(outbounds)-1} outbounds, {len(rules)} rules")
PY
}

# ---------- 主流程 ----------
main() {
  [[ $EUID -ne 0 ]] && { echo "请使用 root 或 sudo 运行"; exit 1; }
  install_singbox
  setup_cert_and_dir
  if [[ -n "$1" && -f "$1" ]]; then
    echo "[*] 使用出站列表: $1 (共 $(wc -l < "$1") 行)"
    generate_config "$1"
  else
    echo "[*] 使用单节点出站: ${1:-114.55.139.72}:${OUTBOUND_PORT}"
    generate_config "$@"
  fi
  chown sing-box:sing-box "$CONFIG_DIR/config.json" 2>/dev/null || true
  sing-box check -c "$CONFIG_DIR/config.json" || { echo "[!] 配置校验失败"; exit 1; }
  systemctl enable sing-box
  systemctl restart sing-box
  echo "[*] sing-box 已启动并设置开机自启"
  ss -ulnp 2>/dev/null | grep -c sing-box || true
  echo "[*] 入站端口: ${PORT_START}-$((PORT_START+PORT_COUNT-1)) (${PORT_COUNT} 个), 用户/密码 ${INBOUND_USER}/${INBOUND_PASSWORD}, 上下行 ${INBOUND_UP_MBPS} Mbps"
}

main "$@"

#!/usr/bin/env python3
# 根据 outbounds-map.json 生成 config.json（200 入站 + 200 出站 + 200 条路由）
# 用法: python3 /root/sing-box-helper/generate-config.py && sudo systemctl restart sing-box
# 修改出站: 编辑同目录下 outbounds-map.json 中对应 port 的 server/server_port/password 后重新运行

import json
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MAP_FILE = os.path.join(SCRIPT_DIR, "outbounds-map.json")
CONFIG_DIR = "/etc/sing-box"
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
CERT_PATH = "/etc/sing-box/cert.pem"
KEY_PATH = "/etc/sing-box/key.pem"

def main():
    with open(MAP_FILE, "r", encoding="utf-8") as f:
        outbounds_map = json.load(f)
    if len(outbounds_map) != 200:
        raise SystemExit(f"outbounds-map.json 应为 200 条，当前 {len(outbounds_map)} 条")
    ports = [e["port"] for e in outbounds_map]
    if ports != list(range(30072, 30272)):
        raise SystemExit("端口必须为 30072-30271 连续 200 个")

    # 200 入站
    inbound_tpl = {
        "type": "hysteria2",
        "listen": "::",
        "up_mbps": 185,
        "down_mbps": 185,
        "users": [{"name": "aqiu", "password": "aqiu"}],
        "tls": {"enabled": True, "certificate_path": CERT_PATH, "key_path": KEY_PATH},
    }
    inbounds = []
    for p in ports:
        ib = {**inbound_tpl, "tag": f"hy2-in-{p}", "listen_port": p}
        inbounds.append(ib)

    # 200 出站 + direct
    outbounds = []
    for e in outbounds_map:
        outbounds.append({
            "type": "hysteria2",
            "tag": f"hy2-out-{e['port']}",
            "server": e["server"],
            "server_port": e["server_port"],
            "password": e["password"],
            "up_mbps": 185,
            "down_mbps": 185,
            "tls": {
                "enabled": True,
                "server_name": e.get("server_name", e["server"]),
                "insecure": e.get("insecure", True),
            },
        })
    outbounds.append({"type": "direct", "tag": "direct"})

    # 200 条路由: 入站 -> 对应出站
    rules = [
        {"inbound": [f"hy2-in-{p}"], "action": "route", "outbound": f"hy2-out-{p}"}
        for p in ports
    ]

    config = {
        "log": {"level": "info"},
        "inbounds": inbounds,
        "outbounds": outbounds,
        "route": {"rules": rules, "final": "direct"},
    }
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print(f"已生成 {CONFIG_FILE}：200 入站、200 出站、200 条路由。请执行: sudo systemctl restart sing-box")

if __name__ == "__main__":
    main()

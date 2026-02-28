#!/usr/bin/env python3
# 中继本机运行：接收上游公网 IP 登记，写入 upstream-ips.txt，收到新上游后自动生成配置并重启 sing-box
# 用法: sudo python3 register-upstream-server.py [--port 9999] [--no-reload]
# 上游脚本设置 RELAY_REGISTER_URL='http://本机IP:9999/register?ip=' 即可自动上报
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse
import os
import subprocess
import argparse
import threading

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
IPS_FILE = os.path.join(SCRIPT_DIR, "upstream-ips.txt")
CONFIG_DIR = "/etc/sing-box"
RELAY_HY2_CONFIG = os.path.join(CONFIG_DIR, "relay-hy2.json")  # 30072-30271 独立实例
PORT_START = 30072
OUTBOUND_PORT = 443
PASSWORD = "aqiu"
UP_MBPS = DOWN_MBPS = 185
CERT_PATH = "/etc/sing-box/cert.pem"
KEY_PATH = "/etc/sing-box/key.pem"
SOCKS_PORT = 9998  # 由另一实例 socks.json 提供，本脚本只写 relay-hy2.json
RELAY_SERVICE = "sing-box@relay-hy2.service"


def _valid_ip(ip):
    ip = (ip or "").strip()
    return bool(ip and all(c in "0123456789.:" for c in ip))


def append_ip(ip):
    """追加出口 IP；若该 IP 已存在则不再追加，避免重复登记。返回 'appended' | 'duplicate' | False"""
    if not _valid_ip(ip):
        return False
    ip = ip.strip()
    try:
        with open(IPS_FILE) as f:
            existing = [ln.strip() for ln in f if ln.strip()]
    except FileNotFoundError:
        existing = []
    if ip in existing:
        return "duplicate"
    with open(IPS_FILE, "a") as f:
        f.write(ip + "\n")
    return "appended"


def set_ip_at_slot(ip, slot_1based):
    """更新指定 slot（1-based）的出口 IP，并保持其它行不变；不足则补空行再写"""
    if not _valid_ip(ip) or slot_1based < 1:
        return False
    with open(IPS_FILE) as f:
        lines = [ln.rstrip("\n") for ln in f.readlines()]
    while len(lines) < slot_1based:
        lines.append("")
    lines[slot_1based - 1] = ip.strip()
    with open(IPS_FILE, "w") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))
    return True


def generate_config_and_reload():
    import json
    if not os.path.isfile(IPS_FILE):
        open(IPS_FILE, "a").close()
    with open(IPS_FILE) as f:
        ips = [ln.strip() for ln in f if ln.strip()]
    inbounds = []
    outbounds = [{"type": "direct", "tag": "direct"}]
    rules = []
    for i, ip in enumerate(ips):
        port = PORT_START + i
        inbounds.append({
            "type": "hysteria2",
            "tag": f"hy2-in-{port}",
            "listen": "::",
            "listen_port": port,
            "up_mbps": UP_MBPS,
            "down_mbps": DOWN_MBPS,
            "users": [{"password": PASSWORD}],
            "tls": {"enabled": True, "certificate_path": CERT_PATH, "key_path": KEY_PATH},
        })
        outbounds.insert(-1, {
            "type": "hysteria2",
            "tag": f"hy2-out-{port}",
            "server": ip,
            "server_port": OUTBOUND_PORT,
            "password": PASSWORD,
            "up_mbps": UP_MBPS,
            "down_mbps": DOWN_MBPS,
            "tls": {"enabled": True, "server_name": ip, "insecure": True},
        })
        rules.append({"inbound": [f"hy2-in-{port}"], "action": "route", "outbound": f"hy2-out-{port}"})
    config = {
        "log": {"level": "info"},
        "inbounds": inbounds,
        "outbounds": outbounds,
        "route": {"rules": rules, "final": "direct"},
    }
    with open(RELAY_HY2_CONFIG, "w") as f:
        json.dump(config, f, indent=2)
    subprocess.run(["systemctl", "restart", RELAY_SERVICE], check=False, capture_output=True)


def do_register_and_reload(ip, slot_1based=None):
    """登记或更新出口 IP 后，重新生成 30072-30271 配置并重启 relay 实例。同一 IP 重复登记不追加、不重启。"""
    if slot_1based is not None:
        ok = set_ip_at_slot(ip, slot_1based)
        need_reload = ok
    else:
        ok = append_ip(ip)
        need_reload = ok == "appended"  # 仅新追加时重载；已存在(duplicate)不重载
    if not ok:
        return False
    if not need_reload or not getattr(do_register_and_reload, "_do_reload", True):
        return True
    def _reload():
        try:
            generate_config_and_reload()
            if slot_1based is not None:
                print(f"[*] 已更新 slot {slot_1based} 出口为 {ip}，已刷新 relay-hy2 配置并重启 {RELAY_SERVICE}")
            else:
                print(f"[*] 已登记上游 {ip}，已更新 relay-hy2 配置并重启 {RELAY_SERVICE}")
        except Exception as e:
            print(f"[!] 登记/更新后重载失败: {e}")
    threading.Thread(target=_reload, daemon=True).start()
    return True


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        ip = (q.get("ip") or [""])[0].strip()
        slot_raw = (q.get("slot") or [""])[0].strip()
        slot_1based = None
        if slot_raw and slot_raw.isdigit():
            slot_1based = int(slot_raw)
        if self.path.startswith("/register") and ip:
            if do_register_and_reload(ip, slot_1based):
                self.send_response(200)
                self.send_header("Content-type", "text/plain")
                self.end_headers()
                self.wfile.write(b"ok")
                return
        self.send_response(400)
        self.end_headers()

    def log_message(self, format, *args):
        pass


def main():
    ap = argparse.ArgumentParser(description="中继：接收上游 IP 登记")
    ap.add_argument("--port", type=int, default=9999)
    ap.add_argument("--no-reload", action="store_true", help="登记后不自动重生成配置/重载 sing-box")
    ap.add_argument("--generate-only", action="store_true", help="仅按 upstream-ips.txt 生成配置并重载 sing-box 后退出")
    args = ap.parse_args()
    os.makedirs(SCRIPT_DIR, exist_ok=True)
    if not os.path.isfile(IPS_FILE):
        open(IPS_FILE, "a").close()
    if args.generate_only:
        with open(IPS_FILE) as f:
            ips = [ln.strip() for ln in f if ln.strip()]
        generate_config_and_reload()
        print(f"[*] 已生成 relay-hy2 配置并重启 {RELAY_SERVICE}：上游 {len(ips)} 台（端口 {PORT_START}-{PORT_START + len(ips) - 1}）" if ips else f"[*] 已生成 relay-hy2 配置并重启 {RELAY_SERVICE}，upstream-ips.txt 为空")
        return
    server = HTTPServer(("0.0.0.0", args.port), Handler)
    do_register_and_reload._do_reload = not args.no_reload
    print(f"[*] 登记服务已启动: http://0.0.0.0:{args.port}/register?ip=上游公网IP")
    print("[*] 登记/更新后会自动刷新 30072-30271 配置并重启 relay 实例 (sing-box@relay-hy2)" if do_register_and_reload._do_reload else "[*] 当前为 --no-reload 模式，仅写 IP，不自动重启")
    print("[*] 新出口: ?ip=IP 追加；出口更新: ?ip=新IP&slot=1 更新第 1 个端口(30072)，slot 从 1 起")
    server.serve_forever()


if __name__ == "__main__":
    main()

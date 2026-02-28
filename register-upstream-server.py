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
PORT_START = 30072
OUTBOUND_PORT = 28800
PASSWORD = "aqiu"
UP_MBPS = DOWN_MBPS = 185
CERT_PATH = "/etc/sing-box/cert.pem"
KEY_PATH = "/etc/sing-box/key.pem"
SOCKS_PORT = 9998  # 中继机 SOCKS5 代理，供出口机安装时加速下载


def append_ip(ip):
    ip = (ip or "").strip()
    if not ip or not all(c in "0123456789.:" for c in ip):
        return False
    with open(IPS_FILE, "a") as f:
        f.write(ip + "\n")
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
    # SOCKS5 代理 9998，供出口机安装 sing-box 时加速下载
    inbounds.append({
        "type": "socks",
        "tag": "socks-proxy",
        "listen": "::",
        "listen_port": SOCKS_PORT,
    })
    rules.append({"inbound": ["socks-proxy"], "action": "route", "outbound": "direct"})
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
    cfg_path = os.path.join(CONFIG_DIR, "config.json")
    with open(cfg_path, "w") as f:
        json.dump(config, f, indent=2)
    subprocess.run(["systemctl", "restart", "sing-box"], check=False, capture_output=True)


def do_register_and_reload(ip):
    """登记 IP 后，若开启自动重载则后台生成配置并重启 sing-box"""
    if not append_ip(ip):
        return False
    if not getattr(do_register_and_reload, "_do_reload", True):
        return True
    def _reload():
        try:
            generate_config_and_reload()
            print(f"[*] 已登记上游 {ip}，已更新配置并重启 sing-box")
        except Exception as e:
            print(f"[!] 登记后重载失败: {e}")
    threading.Thread(target=_reload, daemon=True).start()
    return True


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        ip = (q.get("ip") or [""])[0].strip()
        if self.path.startswith("/register") and ip:
            if do_register_and_reload(ip):
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
        print(f"[*] 已生成配置并重启 sing-box：SOCKS5 代理 {SOCKS_PORT}；上游 {len(ips)} 台（端口 {PORT_START}-{PORT_START + len(ips) - 1}）" if ips else f"[*] 已生成配置并重启 sing-box：仅 SOCKS5 代理 {SOCKS_PORT}，upstream-ips.txt 为空")
        return
    server = HTTPServer(("0.0.0.0", args.port), Handler)
    do_register_and_reload._do_reload = not args.no_reload
    print(f"[*] 登记服务已启动: http://0.0.0.0:{args.port}/register?ip=上游公网IP")
    print("[*] 收到新上游后将自动更新配置并重启 sing-box" if do_register_and_reload._do_reload else "[*] 当前为 --no-reload 模式，仅追加 IP，不自动重启")
    print("[*] 上游安装脚本设置: RELAY_REGISTER_URL='http://本机IP:9999/register?ip='")
    server.serve_forever()


if __name__ == "__main__":
    main()

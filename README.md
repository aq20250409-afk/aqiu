# aqiu

Hy2 中继与出口节点一键脚本：中继机从 30072 起按登记顺序对应各出口 28800，端口/密码/带宽默认（28800 / aqiu / 185Mbps）。

## 仓库说明

- **代理出口机**：运行 `install-upstream-hy2.sh`，安装 sing-box + Hy2 入站（28800，密码 aqiu），并可将本机公网 IP 自动上报到中继登记。
- **中继机（本机）**：运行 `register-upstream-server.py` 接收登记，收到新上游后自动生成配置并重启 sing-box；或使用 `upstream-ips.txt` + `generate-config.py` 手动维护。

协议：Hysteria2，无用户名，仅密码 `aqiu`，上下行 185 Mbps。

## 代理出口机（上游）

```bash
# 默认自动上报到 47.243.170.64:9999 中继登记
sudo ./install-upstream-hy2.sh

# 指定其他中继
sudo RELAY_REGISTER_URL='http://中继IP:9999/register?ip=' ./install-upstream-hy2.sh

# 只安装不自动上报
sudo RELAY_REGISTER_URL= ./install-upstream-hy2.sh
```

## 中继机（本机）

1. 启动登记服务（收到新上游自动改配置并重启 sing-box）：
   ```bash
   sudo python3 register-upstream-server.py
   ```
2. 或手动维护 `upstream-ips.txt`（每行一个出口公网 IP），再生成配置并重启：
   ```bash
   sudo python3 register-upstream-server.py --generate-only
   ```

## 文件说明

| 文件 | 说明 |
|------|------|
| `install-upstream-hy2.sh` | 出口机一键安装：sing-box + Hy2 入站 28800，可选上报到中继 |
| `register-upstream-server.py` | 中继机登记服务：接收出口 IP，自动写配置并重启 sing-box |
| `upstream-ips.txt` | 中继机上游列表（每行一个 IP），供生成配置 |
| `generate-config.py` | 按 outbounds-map.json 生成 200 入站/出站配置（可选，与 register 二选一） |
| `install-singbox-hy2.sh` | 中继机一键安装 sing-box + 多端口入站/出站（可选） |

## License

GPL-3.0

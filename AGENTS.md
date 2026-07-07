# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
A small collection of Bash + Python (standard-library only) scripts for deploying a
sing-box Hysteria2 (Hy2) proxy relay. There is **no package manager, no lockfile, and
no build/lint/test tooling**. The only runtime needed to execute the repo's own code is
`python3` (preinstalled) plus `bash`; the actual proxying is done by an externally
installed `sing-box` binary managed by `systemd`.

### The only long-running service you can run here
`register-upstream-server.py` is the relay registration HTTP server and is the piece of
code you can actually run and exercise in this environment. Run it with:

```bash
python3 register-upstream-server.py            # listens on 0.0.0.0:9999
python3 register-upstream-server.py --no-reload # register only, skip config regen/restart
python3 register-upstream-server.py --generate-only  # regenerate config from upstream-ips.txt and exit
```

Exercise it over HTTP (no GUI exists):
- `GET /register?ip=<IP>` appends a new upstream to `upstream-ips.txt` (duplicates are ignored) and regenerates config.
- `GET /register?ip=<IP>&slot=<n>` overwrites the n-th upstream (1-based; slot 1 == port 30072).
- `GET /files/<name>` serves an allow-listed script (see `ALLOWED_FILES` in the script); non-listed files 404.

### Non-obvious caveats
- **Config output path requires `/etc/sing-box`.** The server writes `/etc/sing-box/relay-hy2.json`.
  That directory does not exist by default and is not writable by a non-root user. To run/test
  the full register→config-generation flow, create it once and make it writable, e.g.
  `sudo mkdir -p /etc/sing-box && sudo chown "$(id -u):$(id -g)" /etc/sing-box`. Without this,
  registration still returns `ok` (config generation runs in a background thread that swallows
  its exception) but no `relay-hy2.json` is produced.
- **`systemctl restart sing-box@relay-hy2.service` is expected to fail here.** It is called with
  `check=False`/output suppressed, so a missing systemd unit / no `sing-box` binary does not break
  registration or config generation. This is normal in the cloud VM.
- **stdout is block-buffered when piped.** When you background the server or pipe it through `tee`,
  the startup banner may not appear immediately; the server is still listening (verify with a
  `curl http://127.0.0.1:9999/register?ip=1.2.3.4`). Use `python3 -u` if you need live logs.
- **`upstream-ips.txt` is a tracked, normally-empty file that the server mutates.** If you register
  IPs while testing, reset it (`: > upstream-ips.txt`) before committing so test data is not staged.
- **`generate-config.py` needs a sibling `outbounds-map.json` with exactly 200 entries** for ports
  30072–30271; that file is not in the repo, so this optional script cannot run without supplying it.

### Lint/test/build equivalents
There are none configured. The closest checks are:
```bash
python3 -m py_compile register-upstream-server.py generate-config.py
for f in install.sh setup.sh install-upstream-hy2.sh install-singbox-hy2.sh; do bash -n "$f"; done
```

### Things that do NOT work in the cloud VM
The exit-node/relay installers (`install-upstream-hy2.sh`, `install-singbox-hy2.sh`, `setup.sh`,
`install.sh`) download `sing-box`, generate systemd units, and expect root + real network/public IP.
Do not expect these to fully run here; validate their logic via `bash -n` and by running the Python
config-generation paths instead.

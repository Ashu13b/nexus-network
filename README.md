# Nexus Network Module

Symmetric tunnel and file-sharing suite for Termux (Android) + Oracle Cloud. Works standalone or as part of the full `~/.bash.d/` modular shell system.

---

## Architecture

```
Internet (net)
     ↑
 Oracle (cld)  ←→  Oracle's LAN
     ↑
 Phone (lcl)   ←→  Phone WiFi (lan)
```

**Naming convention:** `{source}2{destination}`
- `lcl` = phone (where the shell runs)
- `cld` = Oracle cloud server (SSH alias, default `ubu`)
- `lan` = phone's WiFi / local network (via `socat`)
- `net` = public internet (via `cloudflared`)
- `all` = `lan` + `net` simultaneously

**Pipeline types detected by `tnl st`:**

| Type | Direction | Transport |
|---|---|---|
| `CLD2LCL` | Oracle port → Phone localhost | SSH `-L` forward |
| `CLD2NET` | Oracle port → Public URL | cloudflared on Oracle |
| `SOCAT` | Phone port → Phone WiFi | socat TCP bridge |
| `CF_L` | Phone port → Public URL | cloudflared on Phone |
| `HTTP` | Phone port → localhost only | python3 http.server |

---

## Commands

### Tunnel (`tnl <cmd>`)

| Command | What it does |
|---|---|
| `tnl st` | Live dashboard — oracle ports, phone ports, all active pipelines |
| `tnl cld2lcl [port]` | Pull oracle port → phone localhost (SSH -L) |
| `tnl cld2lan [port]` | Pull oracle port → phone WiFi (SSH -L + socat) |
| `tnl cld2net [port]` | Expose oracle port → public URL (cloudflared on oracle) |
| `tnl cld2all [port]` | Pull oracle port → phone WiFi + public URL |
| `tnl lcl2lan [port]` | Bridge phone port → WiFi (socat) |
| `tnl lcl2net [port]` | Expose phone port → public URL (cloudflared on phone) |
| `tnl lcl2all [port]` | Phone port → WiFi + public URL |
| `tnl kx [port]` | Smart kill — kills tunnel + oracle-side service if applicable |
| `tnl xall` | Kill all tunnels, socat bridges, and local servers |
| `tnl deploy [port]` | Start http.server on a tablet via SSH port 8022 |

Tunnel commands also work as direct aliases: `cld2lcl`, `lcl2lan`, etc.

### File Sharing (`fshare [pick] <mode>`)

Default source: `pwd` for `lcl*` modes, `~/` on oracle for `cld*` modes.  
Add `pick` as first arg for interactive folder selection.

| Command | What it does |
|---|---|
| `fshare` | Serve current directory on phone (localhost only) |
| `fshare lcl2lan` | Share pwd → phone WiFi |
| `fshare lcl2net` | Share pwd → public URL |
| `fshare lcl2all` | Share pwd → WiFi + public URL |
| `fshare cld2lcl` | Share oracle ~/ → phone localhost |
| `fshare cld2lan` | Share oracle ~/ → phone WiFi |
| `fshare cld2net` | Share oracle ~/ → public URL |
| `fshare cld2all` | Share oracle ~/ → WiFi + public URL |
| `fshare pick lcl2lan` | Pick folder interactively, then share → WiFi |
| `fshare pick cld2lcl` | Pick oracle folder interactively, then pull down |

Default port: `TNL_DEF_FSERVER_PORT` (default `9000`).

### LAN Scanner (`scan <cmd>`)

| Command | What it does |
|---|---|
| `scan net` | Discover all devices on local subnet |
| `scan sniff <ip>` | Probe for plaintext/insecure services |
| `scan vuln <ip>` | Run nmap vulnerability scripts |
| `scan audit <ip>` | Full nmap audit |

---

## Files

| File | Purpose |
|---|---|
| `tnl.sh` | Core tunnel orchestrator — all `tnl` sub-commands |
| `fshare.sh` | File sharing engine — starts HTTP server, then exposes it |
| `discover.sh` | Port discovery, pipeline detection, port/pipeline pickers |
| `scan.sh` | LAN scanner using nmap |

### `discover.sh` internals

- **`list_local_ports()`** — Cache-first socket scan (instant on repeat, background-refreshes full range 1024–10999)
- **`get_active_pipelines()`** — Parses `/proc`, `~/.ssh/config` LocalForward entries, and running processes → outputs `type|local_port|remote_port|desc|url` records
- **`kill_port(port)`** — Validates numeric input, kills via `fuser` then `pgrep`
- **`pick_pipeline_port(var)`** — Interactive picker from active pipelines
- **`pick_port_oracle(var)`** — Interactive picker from oracle's listening ports (via `ss -tlnp`)

---

## Requirements

### On Termux (Phone)
```bash
pkg install cloudflared socat python nmap openssh
```

### On Oracle (Ubuntu)
```bash
sudo apt install cloudflared socat python3 nmap
```

---

## Configuration

Edit `~/.bash.d/core/01-config.sh`:
```bash
export TNL_REMOTE="ubu"               # SSH alias for oracle server
export TNL_DEF_FSERVER_PORT="9000"   # default port for fshare HTTP server
```

> Port 6000 is blocked by Chrome (X11). Port 8080 is reserved for code-server. Use 9000.

---

## SSH Config (required)

`~/.ssh/config` must define the oracle alias. All oracle-related hosts should inherit a shared base:

```
Host ubu oa ns code fshare
    HostName <YOUR_ORACLE_IP>
    User ubuntu
    IdentityFile ~/.ssh/your-key.key
    ServerAliveInterval 60
    ServerAliveCountMax 2
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 600

Host ubu
    RequestTTY yes

# Service tunnel hosts use LocalForward:
Host fshare
    RequestTTY no
    LocalForward 9000 127.0.0.1:9000
    RemoteCommand fuser -k 9000/tcp 2>/dev/null; cd ~ && python3 -m http.server 9000 2>/dev/null
```

Test with: `ssh ubu echo ok`

---

## Installation

### Option A — Full `~/.bash.d/` system

The module is auto-discovered when the `~/.bash.d/` loader is in `~/.bashrc`:

```bash
for f in ~/.bash.d/core/*.sh; do source "$f"; done
for _mod_dir in ~/.bash.d/*/; do
  _mod=$(basename "${_mod_dir%/}")
  [[ "$_mod" == "core" || "$_mod" == "user" ]] && continue
  for f in "$_mod_dir"*.sh; do [ -f "$f" ] && source "$f"; done
done
```

The `core/` module must be present — it provides colors (`00-style.sh`), config (`01-config.sh`), utilities (`utils.sh`), and pickers (`picker.sh`).

### Option B — Standalone

```bash
# Minimum core deps
source ~/.bash.d/core/00-style.sh    # C_GREEN, B_BLUE, style_header, etc.
source ~/.bash.d/core/01-config.sh   # TNL_REMOTE, TNL_DEF_FSERVER_PORT
source ~/.bash.d/core/utils.sh       # mylan(), check_lan(), _read_input()
source ~/.bash.d/core/picker.sh      # pick_folder(), _smart_select()

# Network module
for f in ~/.bash.d/network/*.sh; do source "$f"; done
```

Optional direct aliases:
```bash
alias lcl2lan='tnl lcl2lan'
alias lcl2net='tnl lcl2net'
alias lcl2all='tnl lcl2all'
alias cld2lcl='tnl cld2lcl'
alias cld2lan='tnl cld2lan'
alias cld2net='tnl cld2net'
alias cld2all='tnl cld2all'
```

---

## Notes

- **No `lsof` on Termux** — Android SELinux blocks process info in `/proc/net/tcp`. Local port detection uses Python socket probing (`discover.sh`). `lsof` is only used on the oracle side via SSH.
- **`tnl st` uses a single oracle SSH call** — ports, cloudflare PID, and CF URL are fetched in one round-trip using inline separators.
- **`tnl kx` is smart** — for named SSH tunnels (CLD2LCL), it kills both the phone-side SSH process and the oracle-side service via `fuser -k RPORT/tcp`.
- **zsh + bash compatible** — all functions handle 1-indexed (zsh) vs 0-indexed (bash) arrays via `$CURRENT_SHELL` checks.
- **Cache-first port scan** — `list_local_ports()` returns instantly on repeat calls by probing the cached port list, while a background fork refreshes the full scan.

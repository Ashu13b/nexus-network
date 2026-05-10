# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the **network module** of a modular Termux shell system (`~/.bash.d/`). It provides symmetric tunnel commands and file sharing between an Android phone (local) and an Oracle Cloud server (`ubu`).

---

## Dependency Chain (what must exist before sourcing this module)

### From `~/.bash.d/core/` — must be sourced first

| File | Provides |
|---|---|
| `core/00-style.sh` | Color vars (`C_GREEN`, `B_BLUE`, `C_DIM`, `C_BOLD`, `C_RESET`, `B_MAGENTA`, etc.) and `style_header()` |
| `core/01-config.sh` | `TNL_REMOTE="ubu"`, `TNL_DEF_FSERVER_PORT="9000"`, `CURRENT_SHELL` |
| `core/utils.sh` | `mylan()`, `check_lan()`, `_read_input()` |
| `core/picker.sh` | `_smart_select()`, `pick_folder()` |

> `core/` is NOT a git repo — changes there are unversioned. Track manually.

### Provided by this module (`discover.sh`)

These were moved FROM `core/` into this module during refactor:

| Function | File | Description |
|---|---|---|
| `list_local_ports()` | `discover.sh` | Cache-first socket scan, returns port numbers as space-separated string |
| `get_active_pipelines()` | `discover.sh` | Returns `type\|local\|remote\|desc\|url` records for all active tunnels/servers |
| `kill_port(port)` | `discover.sh` | Validates numeric, kills via `fuser` then `pgrep -f :PORT` |
| `pick_pipeline_port(var)` | `discover.sh` | Interactive picker from active pipelines |
| `pick_port_oracle(var)` | `discover.sh` | Interactive picker from oracle listening ports (`ss -tlnp` via SSH) |

### System binaries required (Termux phone)
```bash
pkg install cloudflared socat python3 nmap openssh
```

### System binaries required (Oracle Ubuntu)
```bash
sudo apt install cloudflared socat python3 nmap tmux
```

---

## Files in This Module

| File | Purpose |
|---|---|
| `discover.sh` | Port discovery, pipeline detection, port/pipeline pickers |
| `tnl.sh` | Core tunnel orchestrator — all `tnl` sub-commands |
| `fshare.sh` | File sharing engine — starts HTTP server then exposes it |
| `scan.sh` | LAN scanner using nmap |
| `mobocr.sh` | Sends image to oracle for OCR via SSH pipe |

---

## Deployment Status

### Phone (Termux) — COMPLETE
- All `.sh` files in this repo are the live deployed version
- `~/.ssh/config` — configured with `Host oa` using `RequestTTY yes` + LocalForward 5000

### Oracle (`ubu`) — COMPLETE
- `~/open_algo_start.sh` — kills existing tmux algo session, starts new one with `tmux new-session -s algo` (no `-d` — intentional, attaches so user sees the terminal via `ssh oa`)
- `Host oa` SSH config: `RequestTTY yes`, `RemoteCommand cd ~ && ./open_algo_start.sh`, `LocalForward 5000 127.0.0.1:5000`
- OpenAlgo runs on oracle port `5000`, forwarded to phone `localhost:5000`
- OpenAlgo websocket on oracle port `8765` (not forwarded — internal only)

### Nothing incomplete / pending deployment

---

## Testing & Validation

```bash
# Syntax check all scripts
for f in *.sh; do bash -n "$f" && echo "✓ $f" || echo "✗ $f"; done

# Function existence check (mocks core deps)
bash -c "
  style_header(){ true; }; mylan(){ echo '192.168.1.1'; }
  _read_input(){ true; }; _smart_select(){ true; }; pick_folder(){ true; }
  check_lan(){ true; }; CURRENT_SHELL=bash
  source discover.sh; source tnl.sh; source fshare.sh; source scan.sh
  type tnl; type fshare; type scan; type list_local_ports; type get_active_pipelines
"

# Reload live shell
source ~/.bashrc
```

---

## Architecture

### Naming Convention: `{source}2{destination}`
- `lcl` = phone (where the shell is running)
- `cld` = Oracle server (SSH alias configured via `TNL_REMOTE`)
- `lan` = phone's WiFi/LAN (via `socat`)
- `net` = global internet (via `cloudflared`)
- `all` = lan + net simultaneously

### Pipeline types output by `get_active_pipelines()`

| Type | Transport | remote_port field |
|---|---|---|
| `CLD2LCL` | SSH `-L` forward (parsed from `~/.ssh/config` LocalForward) | oracle port |
| `SOCAT` | socat TCP bridge (phone → WiFi) | empty |
| `CF_L` | cloudflared on phone | empty |
| `HTTP` | python3 http.server (local only) | empty |

`CLD2NET` (cloudflare on oracle) is detected separately via `pgrep` — not output by `get_active_pipelines()`, handled directly in `tnl st`.

### Key Implementation Notes
- **No `lsof` on Termux** — Android SELinux blocks `/proc/net/tcp` process info. Use Python socket probing for local ports, `ss -tlnp` on oracle side via SSH only.
- **`tnl st` uses a single oracle SSH call** — parses port list, cloudflare PID, and CF URL in one round-trip using `---NEXUS_CF_PID---` / `---NEXUS_CF_URL---` separators.
- **`tnl kx` is smart** — for CLD2LCL tunnels: kills phone-side SSH process by host name AND kills oracle-side service via `fuser -k RPORT/tcp`.
- **zsh + bash compatible** — zsh arrays are 1-indexed, bash 0-indexed. All pickers use `$CURRENT_SHELL` to select correct index.
- **`ssh_opt` must be an array** — `local ssh_opt; ssh_opt=(-T -o ConnectTimeout=5)` and used as `"${ssh_opt[@]}"`. String form silently fails in zsh (no word-split).
- **Safe eval pattern** — always use `eval "var=\$_val"` not `eval "var=\"${array[$i]}\""` to prevent injection through variable values.
- **Cache-first port scan** — `list_local_ports()` probes cached ports instantly, background fork does full 1024–10999 rescan via `poll()` batches (not `select()` — no FD_SETSIZE limit).
- **Port 9000** — default for `fshare` only (`TNL_DEF_FSERVER_PORT`). Tunnel commands have no hardcoded default — they prompt or take arg.
- **`unalias` guard** — `scan.sh` calls `unalias scan 2>/dev/null` at load to prevent zsh alias conflicts.
- **Cloudflare URL detection** — all tunnel wait loops grep for `https://[a-z0-9-]+\.trycloudflare\.com` in `~/.cloudflared.log`.

---

## Git Workflow

```bash
git add <file> && git commit -m "message" && git push
```

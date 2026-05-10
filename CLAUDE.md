# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the **network module** of a modular Termux shell system (`~/.bash.d/`). It provides symmetric tunnel commands and file sharing between an Android phone (local) and an Oracle Cloud server (`ubu`).

## Testing & Validation

```bash
# Syntax check all scripts
for f in *.sh; do bash -n "$f" && echo "✓ $f" || echo "✗ $f"; done

# Function existence check (mocks core deps)
bash -c "
  style_header(){ true; }; mylan(){ echo '192.168.1.1'; }; list_local_ports(){ echo '8080'; }
  get_active_pipelines(){ echo ''; }; pick_folder(){ true; }; pick_pipeline_port(){ true; }
  pick_port_oracle(){ true; }; _read_input(){ true; }; _smart_select(){ true; }
  kill_port(){ true; }; check_lan(){ true; }; CURRENT_SHELL=bash
  source tnl.sh; source fshare.sh; source scan.sh
  type tnl; type fshare; type scan
"

# Reload live shell
source ~/.bashrc
```

## Git Workflow

```bash
# Commit and push changes
git add <file> && git commit -m "message" && git push
```

## Architecture

### Dependency Chain
This module depends on `~/.bash.d/core/` — which must be sourced first:
- `00-style.sh` — color variables (`C_GREEN`, `B_BLUE`, etc.) and `style_header()`
- `01-config.sh` — `TNL_REMOTE` (SSH alias), `TNL_DEF_FSERVER_PORT`
- `utils.sh` — `mylan()`, `list_local_ports()`, `get_active_pipelines()`, `kill_port()`
- `picker.sh` — `pick_folder()`, `pick_pipeline_port()`, `pick_port_oracle()`, `_smart_select()`, `_read_input()`

### Naming Convention: `{source}2{destination}`
- `lcl` = phone (where the shell is running)
- `cld` = Oracle server (SSH alias `ubu`, configured via `TNL_REMOTE`)
- `lan` = phone's WiFi/LAN (via `socat`)
- `net` = global internet (via `cloudflared`)
- `all` = lan + net simultaneously

### Files

**`tnl.sh`** — Core tunnel orchestrator. All tunnel commands are sub-cases of `tnl <cmd>`:
- `lcl2lan/net/all` — expose a running local port outward
- `cld2lcl/lan/net/all` — pull an Oracle port down to phone (SSH `-L`) then expose
- `st` — live dashboard (probes oracle via SSH, local ports via Python socket)
- `kx` / `xall` — kill pipelines
- `deploy` — start http.server on a tablet via SSH port 8022

**`fshare.sh`** — File sharing engine. Starts an HTTP server then exposes it:
- `lcl*` modes: starts `python -m http.server` locally, default dir = `pwd`
- `cld*` modes: starts server on Oracle via SSH, default dir = `~/`
- Add `pick` as first arg for interactive folder selection
- Private helpers: `_fshare_start_local`, `_fshare_start_remote`, `_fshare_wait_cf`, `_fshare_pick_remote_folder`

**`scan.sh`** — LAN scanner using `nmap`. Commands: `net`, `sniff <ip>`, `vuln <ip>`, `audit <ip>`

**`mobocr.sh`** — Sends an image to Oracle for OCR processing via SSH pipe.

### Key Rules
- **No `lsof` on Termux** — Android SELinux blocks it. Use Python socket probing (`list_local_ports()`) or `ss` for local port checks. `lsof` is only used on Oracle (Ubuntu) side via SSH.
- **Cross-shell compatibility** — All functions support both `bash` and `zsh`. Array indexing differs: zsh is 1-indexed, bash is 0-indexed. Check `$CURRENT_SHELL` where needed.
- **`unalias` guard** — `scan.sh` calls `unalias scan 2>/dev/null` at load time to prevent zsh conflicts when the function name matches an existing alias.
- **Port default** — `TNL_DEF_FSERVER_PORT` (default `9000`) is used by `fshare` for the HTTP server port. Port 6000 is blocked by Chrome (X11), port 8080 reserved for code-server.
- **Cloudflare URL detection** — All tunnel wait loops grep for `https://[a-z0-9-]+\.trycloudflare\.com` in `~/.cloudflared.log`.

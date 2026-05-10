# 🌐 Nexus Network Module

Symmetric tunnel and file-sharing suite for Termux (Android) + Oracle Cloud.
Works standalone or as part of the full `~/.bash.d/` modular shell system.

## Commands

### Tunnel Commands (also work as direct aliases)
| Command | Description |
|---|---|
| `lcl2lan [port]` | Phone port → WiFi (socat) |
| `lcl2net [port]` | Phone port → Internet (cloudflare) |
| `lcl2all [port]` | Phone port → WiFi + Internet |
| `cld2lcl [port]` | Oracle port → Phone localhost (SSH -L) |
| `cld2lan [port]` | Oracle port → Phone WiFi (SSH -L + socat) |
| `cld2net [port]` | Oracle port → Internet (cloudflare on oracle) |
| `cld2all [port]` | Oracle port → WiFi + Internet |

### File Sharing
| Command | Description |
|---|---|
| `fshare` | Serve current directory on phone |
| `fshare lcl2lan` | Share pwd → WiFi |
| `fshare lcl2net` | Share pwd → Internet |
| `fshare lcl2all` | Share pwd → WiFi + Internet |
| `fshare cld2lcl` | Share oracle ~/ → phone localhost |
| `fshare cld2lan` | Share oracle ~/ → phone WiFi |
| `fshare cld2net` | Share oracle ~/ → Internet |
| `fshare cld2all` | Share oracle ~/ → WiFi + Internet |
| `fshare pick <mode>` | Interactive folder picker before sharing |

### System (via `tnl` only)
| Command | Description |
|---|---|
| `tnl st` | Live network dashboard |
| `tnl kx` | Smart kill (interactive process killer) |
| `tnl xall` | Kill all tunnels and servers |
| `tnl deploy` | Deploy file server to tablet via SSH |
| `scan net` | Map all devices on LAN |
| `scan sniff <ip>` | Check for plaintext vulnerabilities |
| `scan audit <ip>` | Full nmap audit |

---

## Requirements

### On Termux (Phone)
```bash
pkg install cloudflared socat python nmap
```

### On Oracle / Remote Server
```bash
# Ubuntu
sudo apt install cloudflared socat python3 nmap
```

### SSH Alias `ubu`
This module expects a working SSH alias named `ubu` pointing to your Oracle server.
Add to `~/.ssh/config`:
```
Host ubu
    HostName <YOUR_ORACLE_IP>
    User ubuntu
    IdentityFile ~/.ssh/your-key.key
    ServerAliveInterval 60
    ServerAliveCountMax 2
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 600
```
Test with: `ssh ubu echo ok`

---

## Installation

### Option A — Part of full `~/.bash.d/` system
The `~/.bashrc` auto-discovers all module folders:
```bash
# In ~/.bashrc — core loads first, then all other folders, user loads last
for f in ~/.bash.d/core/*.sh; do source "$f"; done
for _mod_dir in ~/.bash.d/*/; do
  _mod=$(basename "${_mod_dir%/}")
  [ "$_mod" = "core" ] || [ "$_mod" = "user" ] && continue
  for f in "$_mod_dir"*.sh; do [ -f "$f" ] && source "$f"; done
done
for f in ~/.bash.d/user/*.sh; do source "$f"; done
```
The `core/` module must be present (provides `style_header`, colors, `mylan`, `list_local_ports`, `pick_folder`, etc.).

### Option B — Standalone (network only)
Source the required core helpers manually in your `.bashrc` / `.zshrc`:
```bash
# Minimum required from core/
source ~/.bash.d/core/00-style.sh   # colors
source ~/.bash.d/core/01-config.sh  # TNL_REMOTE, ports
source ~/.bash.d/core/utils.sh      # mylan, list_local_ports, get_active_pipelines
source ~/.bash.d/core/picker.sh     # pick_folder, pick_pipeline_port

# Then source network module
for f in ~/.bash.d/network/*.sh; do source "$f"; done
```

Add direct tunnel aliases to your `.bashrc` / `.zshrc`:
```bash
alias lcl2lan='tnl lcl2lan'
alias lcl2net='tnl lcl2net'
alias lcl2all='tnl lcl2all'
alias cld2lcl='tnl cld2lcl'
alias cld2lan='tnl cld2lan'
alias cld2net='tnl cld2net'
alias cld2all='tnl cld2all'
```

### On Oracle (install same network module)
```bash
# Clone this repo
git clone <repo-url> ~/.bash.d/network

# Add to ~/.bashrc on oracle:
source ~/.bash.d/core/00-style.sh
source ~/.bash.d/core/01-config.sh
source ~/.bash.d/core/utils.sh
source ~/.bash.d/core/picker.sh
for f in ~/.bash.d/network/*.sh; do source "$f"; done

# Configure TNL_REMOTE in 01-config.sh to point to another cloud if needed
```

---

## Configuration
Edit `~/.bash.d/core/01-config.sh`:
```bash
export TNL_REMOTE="ubu"              # SSH alias for oracle
export TNL_DEF_PORT_REMOTE="8080"   # default oracle port
export TNL_DEF_FSERVER_PORT="6000"  # default fshare port
```

---

## Architecture
```
Internet (net)
     ↑
 Oracle (cld)  ←→  Oracle's LAN
     ↑
 Phone (lcl)   ←→  Phone's LAN / WiFi
```
- `{from}2{to}` = connect service from source node to target direction
- `lcl*` = service runs on phone, `cld*` = service runs on oracle
- `fshare` starts the HTTP server; tunnel commands expose it

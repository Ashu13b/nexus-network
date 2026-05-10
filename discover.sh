# ── Network Discovery & Pipeline Engine ──

# Cache-first port scan — instant on repeat calls, background-refreshes cache
# First run: full scan 1024-10999 (~2s). Subsequent: probe cache only (~instant).
list_local_ports() {
    python -c "
import socket, select, errno, os, json
from concurrent.futures import ThreadPoolExecutor

CACHE = os.path.expanduser('~/.cache/nexus_ports.json')

def probe(ports):
    active = []
    for port in ports:
        try:
            s = socket.socket(); s.settimeout(0.02)
            if s.connect_ex(('127.0.0.1', port)) == 0: active.append(port)
            s.close()
        except: pass
    return active

def full_scan():
    def scan_batch(ports):
        socks = {}; found = []
        poller = select.poll()
        for port in ports:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setblocking(False)
            if s.connect_ex(('127.0.0.1', port)) in (0, errno.EINPROGRESS):
                socks[s.fileno()] = (s, port)
                poller.register(s.fileno(), select.POLLOUT)
            else:
                s.close()
        if socks:
            for fd, _ in poller.poll(20):
                s, port = socks[fd]
                if s.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR) == 0: found.append(port)
            for s, _ in socks.values(): s.close()
        return found
    chunks = [list(range(b, min(b+500, 11000))) for b in range(1024, 11000, 500)]
    result = []
    with ThreadPoolExecutor(max_workers=10) as ex:
        for res in ex.map(scan_batch, chunks): result.extend(res)
    return sorted(set(result))

def save(ports):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, 'w') as f: json.dump(ports, f)

cached = []
try:
    with open(CACHE) as f: cached = json.load(f)
except: pass

if cached:
    print(' '.join(str(p) for p in sorted(probe(cached))))
    if os.fork() == 0:
        try: os.setsid(); save(full_scan())
        finally: os._exit(0)
else:
    found = full_scan()
    save(found)
    print(' '.join(str(p) for p in sorted(found)))
" 2>/dev/null
}

# Unified pipeline discovery — outputs 5-field records: type|local|remote|desc|url
# remote is empty for local-only services (SOCAT/CF_L/HTTP)
get_active_pipelines() {
    local ip=$(mylan)
    LAN_IP="$ip" python -c "
import os, re

def get_cmd(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='ignore')
    except: return ''

pipes = []
lan_ip = os.environ.get('LAN_IP', '127.0.0.1')

# Parse ~/.ssh/config — capture both local AND remote port from LocalForward
ssh_forwards = {}  # host -> (local_port, remote_port)
try:
    with open(os.path.expanduser('~/.ssh/config')) as f:
        current_hosts = []
        for line in f:
            line = line.strip()
            if line.startswith('Host '):
                current_hosts = [h for h in line[5:].split() if '*' not in h and '?' not in h]
            elif line.startswith('LocalForward ') and current_hosts:
                parts = line.split()
                if len(parts) >= 3:
                    local_port = parts[1].split(':')[-1]
                    remote_port = parts[2].split(':')[-1]
                    for h in current_hosts:
                        ssh_forwards[h] = (local_port, remote_port)
except: pass

for pid in os.listdir('/proc'):
    if not pid.isdigit(): continue
    cmd = get_cmd(pid)
    if not cmd: continue

    # 1. Socat Bridges (Phone -> LAN)
    if 'socat' in cmd and 'TCP-LISTEN' in cmd:
        m = re.search(r'TCP-LISTEN:(\d+)', cmd)
        if m: pipes.append(f'SOCAT|{m.group(1)}||Phone:{m.group(1)} ➔ WiFi|http://{lan_ip}:{m.group(1)}')

    # 2. Cloudflare Tunnels (Phone -> Global)
    if 'cloudflared' in cmd and '--url' in cmd:
        m = re.search(r'http://[a-zA-Z0-9.-]+:(\d+)', cmd)
        if m: pipes.append(f'CF_L|{m.group(1)}||Phone:{m.group(1)} ➔ Global|[LOG_URL]')

    # 3. Python File Servers (local only)
    if 'http.server' in cmd and 'ssh' not in cmd:
        parts = cmd.split()
        if parts:
            port = parts[-1]
            if port.isdigit(): pipes.append(f'HTTP|{port}||File Server:{port}|http://{lan_ip}:{port}')

    # 4. SSH Tunnels — local and remote ports may differ (e.g. LocalForward 5000 host:8005)
    if cmd.strip().startswith('ssh ') and 'ssh-' not in cmd:
        words = cmd.strip().split()
        if len(words) >= 2:
            host = words[-1]
            if host in ssh_forwards:
                lp, rp = ssh_forwards[host]
                label = f'{host}  (oracle:{rp} → phone:{lp})' if rp != lp else host
                pipes.append(f'CLD2LCL|{lp}|{rp}|{label}|http://127.0.0.1:{lp}')

for p in sorted(list(set(pipes))):
    print(p)
" 2>/dev/null
}

# Kill a local port's owning process
kill_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] || return 1
    fuser -k "${p}/tcp" 2>/dev/null || pgrep -f ":${p}" | xargs kill -9 2>/dev/null
}

# ── Pipeline Port Picker ──
pick_pipeline_port() {
    local target_var=$1
    local ports=(); local descs=()

    while IFS='|' read -r type lport rport desc url; do
        [ -z "$type" ] && continue
        ports+=("$lport")
        descs+=("$desc ($lport)")
    done <<< "$(get_active_pipelines)"

    local count=${#ports[@]}
    if [ $count -eq 0 ]; then return 1; fi
    if [ $count -eq 1 ]; then
        if [ "$CURRENT_SHELL" = "zsh" ]; then eval "$target_var=\"${ports[1]}\""
        else eval "$target_var=\"${ports[0]}\""; fi
        return 0
    fi

    style_header "ACTIVE PIPELINES & SERVERS" >&2
    for ((i=1; i<=$count; i++)); do
        if [ "$CURRENT_SHELL" = "zsh" ]; then
            printf "%d) %s\n" "$i" "${descs[$i]}" >&2
        else
            printf "%d) %s\n" "$i" "${descs[$((i-1))]}" >&2
        fi
    done

    local choice; _smart_select 1 $count 1 "Kill which one?" choice || return 1
    if [ "$CURRENT_SHELL" = "zsh" ]; then
        eval "$target_var=\"${ports[$choice]}\""
    else
        eval "$target_var=\"${ports[$((choice-1))]}\""
    fi
    return 0
}

# ── Oracle Port Picker ──
pick_port_oracle() {
    local target_var=$1; local remote="${TNL_REMOTE:-ubu}"
    local listeners=($(ssh -q "$remote" "ss -tlnp 2>/dev/null | awk 'NR>1{print \$4}' | grep -oE '[0-9]+$' | sort -un" 2>/dev/null))
    if [ ${#listeners[@]} -eq 0 ]; then echo -e "${C_RED}No ports found on $remote.${C_RESET}" >&2; return 1; fi
    style_header "$remote PORTS" >&2
    local i=1; for p in "${listeners[@]}"; do echo "$i) Port $p" >&2; ((i++)); done
    local choice; _smart_select 1 ${#listeners[@]} 1 "Select source port" choice || return 1
    local _val
    if [ "$CURRENT_SHELL" = "zsh" ]; then _val="${listeners[$choice]}"
    else _val="${listeners[$((choice-1))]}"; fi
    eval "$target_var=\$_val"
    return 0
}

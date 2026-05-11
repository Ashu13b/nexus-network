#!/bin/bash
# nexus_cf.sh — cloudflared probe, runs ON oracle
# Deploy: scp this to ~/nexus_cf.sh on oracle (tnl push)
#
# Usage:
#   ~/nexus_cf.sh          → outputs 2 lines: PID, URL (empty if unknown)
#   ~/nexus_cf.sh kill     → stops cloudflared (systemctl + kill)

cf_pid=""
for p in /proc/[0-9]*/exe; do
    t=$(readlink "$p" 2>/dev/null) || continue
    case "$t" in *cloudflare*)
        cf_pid=$(basename "$(dirname "$p")")
        break
    ;; esac
done

if [ "$1" = "kill" ]; then
    systemctl stop cloudflared 2>/dev/null
    [ -n "$cf_pid" ] && kill "$cf_pid" 2>/dev/null
    exit 0
fi

echo "$cf_pid"
[ -z "$cf_pid" ] && echo "" && exit 0

cf_port=$(ss -tlnp 2>/dev/null | grep "pid=$cf_pid," | grep -oE ':[0-9]+' | tr -d ':' | head -1)
if [ -n "$cf_port" ]; then
    curl -s --max-time 2 "http://localhost:$cf_port/metrics" 2>/dev/null \
        | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | head -1
else
    echo ""
fi

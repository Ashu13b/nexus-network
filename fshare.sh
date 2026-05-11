# ── fshare: File Sharing Engine ──
# Usage: fshare [pick] <mode>
# Modes: lcl2lan  lcl2net  lcl2all  cld2lcl  cld2lan  cld2net  cld2all
# Default source: pwd for lcl*, ~/  for cld*
# Add 'pick' to select folder interactively

fshare() {
    local use_picker=false
    local mode=""

    if [ "$1" = "pick" ]; then
        use_picker=true; mode="${2:-}"
    else
        mode="${1:-}"
    fi

    local lp="${TNL_DEF_FSERVER_PORT:-9000}"
    local remote="${TNL_REMOTE:-ubu}"
    local cf_log="$HOME/.cloudflared.log"
    local ip=$(mylan)

    local is_cloud=false
    [[ "$mode" == cld* ]] && is_cloud=true

    # ── Folder Selection ──
    local dir=""
    if $use_picker; then
        if $is_cloud; then
            _fshare_pick_remote_folder dir || return 1
        else
            pick_folder dir "$HOME" || return 1
        fi
    else
        $is_cloud && dir="~" || dir="$(pwd)"
    fi

    echo -e "${C_CYAN}[FSHARE]${C_RESET} Source: ${C_BOLD}$dir${C_RESET}"

    # ── Mode Dispatch ──
    case "$mode" in
        ""|"lcl")
            _fshare_start_local "$dir" "$lp" "$ip" ;;

        "lcl2lan")
            _fshare_start_local "$dir" "$lp" "$ip"
            pkill -f "socat.*TCP-LISTEN:$lp" 2>/dev/null
            socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
            echo -e "  ${C_GREEN}✓ LAN:${C_RESET} http://$ip:$lp" ;;

        "lcl2net")
            _fshare_start_local "$dir" "$lp" "$ip"
            _fshare_wait_cf "$lp" "$cf_log" ;;

        "lcl2all"|"broadcast")
            _fshare_start_local "$dir" "$lp" "$ip"
            pkill -f "socat.*TCP-LISTEN:$lp" 2>/dev/null
            socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
            echo -e "  ${C_GREEN}✓ LAN:${C_RESET} http://$ip:$lp"
            _fshare_wait_cf "$lp" "$cf_log" ;;

        "cld2lcl")
            if ! $use_picker && [ "$dir" = "~" ] && [ "$lp" = "${TNL_DEF_FSERVER_PORT:-9000}" ]; then
                # Default case — use dedicated SSH host (clean, no scripting)
                echo -e "${C_CYAN}[FSHARE]${C_RESET} Source: ${C_BOLD}oracle ~/  ${C_RESET}"
                pkill -f "ssh.*fshare" 2>/dev/null; sleep 0.2
                ssh fshare &
                sleep 2
                echo -e "  ${C_GREEN}✓ LOCAL:${C_RESET} http://127.0.0.1:$lp"
            else
                # Pick mode or custom port — fall back to scripting
                _fshare_start_remote "$dir" "$lp" "$remote" || return 1
                ssh -T -o ConnectTimeout=5 -f -N -L "$lp:127.0.0.1:$lp" "$remote"
                echo -e "  ${C_GREEN}✓ LOCAL:${C_RESET} http://127.0.0.1:$lp"
            fi ;;

        "cld2lan")
            if ! $use_picker && [ "$dir" = "~" ] && [ "$lp" = "${TNL_DEF_FSERVER_PORT:-9000}" ]; then
                # Default case — use SSH host for server+tunnel, add socat for LAN
                echo -e "${C_CYAN}[FSHARE]${C_RESET} Source: ${C_BOLD}oracle ~/  ${C_RESET}"
                pkill -f "ssh.*fshare" 2>/dev/null
                pkill -f "socat.*TCP-LISTEN:$lp" 2>/dev/null; sleep 0.2
                ssh fshare &
                sleep 2
                socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
                echo -e "  ${C_GREEN}✓ LAN:${C_RESET} http://$ip:$lp"
            else
                _fshare_start_remote "$dir" "$lp" "$remote" || return 1
                pkill -f "socat.*TCP-LISTEN:$lp" 2>/dev/null
                ssh -T -o ConnectTimeout=5 -f -N -L "$lp:127.0.0.1:$lp" "$remote"
                socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
                echo -e "  ${C_GREEN}✓ LAN:${C_RESET} http://$ip:$lp"
            fi ;;

        "cld2net")
            _fshare_start_remote "$dir" "$lp" "$remote" || return 1
            echo -n "  Starting oracle tunnel"
            local rem_url
            rem_url=$(ssh -T -o ConnectTimeout=5 "$remote" "
                pkill -x cloudflared 2>/dev/null
                rm -f ~/cf.log; nohup cloudflared tunnel --url http://localhost:$lp > ~/cf.log 2>&1 &
                for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
                    sleep 1
                    url=\$(grep -oE 'https://[^ ]+\.trycloudflare\.com' ~/cf.log 2>/dev/null | tail -1)
                    [ -n \"\$url\" ] && echo \"\$url\" && exit 0
                done
            " 2>/dev/null | tr -d '\r')
            echo ""
            [ -n "$rem_url" ] && echo -e "  ${C_GREEN}✓ NET:${C_RESET} ${B_MAGENTA}$rem_url${C_RESET}" \
                              || echo -e "  ${C_YELLOW}⚠ Tunnel starting... check tnl st${C_RESET}" ;;

        "cld2all")
            _fshare_start_remote "$dir" "$lp" "$remote" || return 1
            pkill -f "socat.*TCP-LISTEN:$lp" 2>/dev/null
            ssh -T -o ConnectTimeout=5 -f -N -L "$lp:127.0.0.1:$lp" "$remote"
            socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
            echo -e "  ${C_GREEN}✓ LAN:${C_RESET} http://$ip:$lp"
            echo -n "  Starting oracle tunnel"
            local rem_url
            rem_url=$(ssh -T -o ConnectTimeout=5 "$remote" "
                pkill -x cloudflared 2>/dev/null
                rm -f ~/cf.log; nohup cloudflared tunnel --url http://localhost:$lp > ~/cf.log 2>&1 &
                for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
                    sleep 1
                    url=\$(grep -oE 'https://[^ ]+\.trycloudflare\.com' ~/cf.log 2>/dev/null | tail -1)
                    [ -n \"\$url\" ] && echo \"\$url\" && exit 0
                done
            " 2>/dev/null | tr -d '\r')
            echo ""
            [ -n "$rem_url" ] && echo -e "  ${C_GREEN}✓ NET:${C_RESET} ${B_MAGENTA}$rem_url${C_RESET}" \
                              || echo -e "  ${C_YELLOW}⚠ NET tunnel starting... check tnl st${C_RESET}" ;;

        *)
            style_header "FSHARE HELP"
            printf "\n  ${C_DIM}LOCAL SOURCE (default: pwd)${C_RESET}\n"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare"          "serve pwd on phone"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare lcl2lan"  "pwd → phone WiFi"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare lcl2net"  "pwd → internet"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare lcl2all"  "pwd → WiFi + internet"
            printf "\n  ${C_DIM}CLOUD SOURCE (default: oracle ~/)${C_RESET}\n"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare cld2lcl"  "oracle ~/ → phone localhost"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare cld2lan"  "oracle ~/ → phone WiFi"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare cld2net"  "oracle ~/ → internet"
            printf "  ${C_CYAN}%-26s${C_RESET} %s\n" "fshare cld2all"  "oracle ~/ → WiFi + internet"
            printf "\n  Add ${C_BOLD}pick${C_RESET} to select folder: ${C_CYAN}fshare pick lcl2lan${C_RESET}\n" ;;
    esac
}

# ── Private Helpers ──

_fshare_start_local() {
    local dir="$1" lp="$2" ip="$3"
    pkill -f "http.server $lp" 2>/dev/null; sleep 0.3
    ( cd "$dir" && python3 -m http.server "$lp" > /dev/null 2>&1 ) &
    echo -e "  ${C_GREEN}✓ LOCAL:${C_RESET} http://127.0.0.1:$lp"
    [ "$ip" != "127.0.0.1" ] && echo -e "  ${C_DIM}LAN:${C_RESET}   http://$ip:$lp"
}

_fshare_start_remote() {
    local dir="$1" lp="$2" remote="$3"
    local escaped_dir; escaped_dir=$(printf '%q' "$dir")
    echo -e "  Starting oracle file server..."
    ssh -T -o ConnectTimeout=5 "$remote" \
        "fuser -k ${lp}/tcp 2>/dev/null; cd ${escaped_dir} && nohup python3 -m http.server ${lp} > /dev/null 2>&1 &" \
        2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "  ${C_RED}✗ Cannot reach oracle${C_RESET}"; return 1
    fi
    sleep 0.5
}

_fshare_wait_cf() {
    local lp="$1" cf_log="$2"
    pkill -x cloudflared 2>/dev/null
    rm -f "$cf_log"; touch "$cf_log"
    cloudflared tunnel --url "http://127.0.0.1:$lp" > "$cf_log" 2>&1 &
    local t=15
    echo -n "  Waiting for public URL"
    while [ $t -gt 0 ]; do
        local url
        url=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" "$cf_log" 2>/dev/null | tail -1)
        if [ -n "$url" ]; then
            echo -e "\n  ${C_GREEN}✓ NET:${C_RESET} ${B_MAGENTA}$url${C_RESET}"
            return 0
        fi
        sleep 1; echo -n "."; ((t--))
    done
    echo -e "\n  ${C_YELLOW}⚠ Tunnel starting... check tnl st${C_RESET}"
}

_fshare_pick_remote_folder() {
    local target_var=$1
    local remote="${TNL_REMOTE:-ubu}"
    local ssh_opt; ssh_opt=(-T -o ConnectTimeout=5)

    echo -e "${C_CYAN}[FSHARE]${C_RESET} Fetching oracle folders..." >&2
    local dirs_raw
    dirs_raw=$(ssh "${ssh_opt[@]}" "$remote" \
        "find ~ -maxdepth 2 -mindepth 1 -type d 2>/dev/null | sort" 2>/dev/null)

    if [ -z "$dirs_raw" ]; then
        echo -e "  ${C_RED}✗ Cannot reach oracle${C_RESET}" >&2; return 1
    fi

    style_header "ORACLE FOLDERS" >&2
    local dirs=(); local i=1
    while IFS= read -r d; do
        printf "  %d) %s\n" "$i" "$d" >&2
        dirs+=("$d"); ((i++))
    done <<< "$dirs_raw"

    local choice; _smart_select 1 $((i-1)) 1 "Pick folder" choice || return 1
    local _val
    if [ "$CURRENT_SHELL" = "zsh" ]; then _val="${dirs[$choice]}"
    else _val="${dirs[$((choice-1))]}"; fi
    eval "$target_var=\$_val"
}

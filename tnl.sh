# ── Network & Tunnels (Truth Dashboard - Optimized UI) ──

tnl() {
  local cmd="$1"; local arg2="$2"; local ip=$(mylan); local remote="${TNL_REMOTE:-ubu}"
  local cf_log="$HOME/.cloudflared.log"; local rem_cf_log="/home/ubuntu/cf.log"
  local ssh_opt="-T -o ConnectTimeout=5"
  local width=${COLUMNS:-$(tput cols 2>/dev/null || echo 40)}

  case "$cmd" in
    "st")
      # --- 1. PROBE STATE ---
      local r_ports_raw=$(ssh -q "$remote" "ss -tlnp 2>/dev/null || lsof -i -P -n | grep LISTEN" 2>/dev/null)
      # Filter to user-space ports only (>1023 — skip SSH/DNS/RPC noise)
      local r_ports=$(echo "$r_ports_raw" | grep -oE ':[0-9]+' | tr -d ':' | sort -un \
        | awk '$1+0 > 1023' | tr '\n' ' ' | sed 's/ $//')
      local l_ports=$(list_local_ports)
      local local_ps=$(ps -ef | grep -v grep)
      local r_cf_active=$(ssh -q "$remote" "pgrep -f 'cloudflared tunnel'" 2>/dev/null)
      local lan_ok=""; echo "$local_ps" | grep -q "socat" && lan_ok="1"
      local net_ok=""; [ -n "$r_cf_active" ] && net_ok="1"
      echo "$local_ps" | grep -q "cloudflared" && net_ok="1"

      # --- 2. STATUS ROWS ---
      style_header "NETWORK STATUS"
      printf "\n"
      if [ -n "$r_ports" ]; then
        printf "  %b%-10s%b ${C_GREEN}✓${C_RESET}  %s\n" "${B_BLUE}" "Oracle" "${C_RESET}" "$r_ports"
      else
        printf "  %b%-10s  ✗%b\n" "${C_DIM}" "Oracle" "${C_RESET}"
      fi
      if [ -n "$l_ports" ]; then
        printf "  %b%-10s%b ${C_GREEN}✓${C_RESET}  %s\n" "${B_GREEN}" "Phone" "${C_RESET}" "$l_ports"
      else
        printf "  %b%-10s  ✗%b\n" "${C_DIM}" "Phone" "${C_RESET}"
      fi
      if [ -n "$lan_ok" ]; then
        printf "  %-10s ${C_GREEN}✓${C_RESET}  http://$ip\n" "LAN"
      else
        printf "  %b%-10s  ✗%b\n" "${C_DIM}" "LAN" "${C_RESET}"
      fi
      if [ -n "$net_ok" ]; then
        printf "  %-10s ${C_GREEN}✓${C_RESET}\n" "Internet"
      else
        printf "  %b%-10s  ✗%b\n" "${C_DIM}" "Internet" "${C_RESET}"
      fi

      # --- 3. PIPELINE ENTRIES ---
      style_header "ACTIVE PIPELINES"
      local found=0
      local ssh_covered_ports=""
      local _pipelines; _pipelines="$(get_active_pipelines)"
      while IFS='|' read -r type lport rport desc url; do
        [ "$type" = "CLD2LCL" ] && ssh_covered_ports="$ssh_covered_ports $lport"
      done <<< "$_pipelines"

      # Symmetry-detected CLD2LCL (skip ports covered by named SSH entries)
      for p in $(echo $l_ports); do
        echo "$ssh_covered_ports" | grep -qw "$p" && continue
        if echo "$r_ports" | grep -qw "$p"; then
          [ $found -ne 0 ] && printf "  ${C_DIM}──────────────────────────${C_RESET}\n"
          printf "  %b▸ CLD2LCL %b Oracle → Phone\n  %b  └─%b http://127.0.0.1:%s\n" \
            "${B_BLUE}" "${C_RESET}" "${C_DIM}" "${C_RESET}" "$p"
          found=1
        fi
      done

      while IFS='|' read -r type lport rport desc url; do
        [ -z "$type" ] && continue
        [ $found -ne 0 ] && printf "  ${C_DIM}──────────────────────────${C_RESET}\n"
        [ "$type" = "CF_L" ] && url=$(grep -oE "https://.*\.trycloudflare\.com" "$cf_log" 2>/dev/null | tail -1)

        local badge="${B_BLUE}▸" note=""
        if [ "$type" = "CLD2LCL" ] && [ -n "$rport" ]; then
          if ! echo " $r_ports " | grep -qw "$rport"; then
            badge="${C_YELLOW}⚠"
            note="  ${C_DIM}[oracle:$rport offline]${C_RESET}"
          fi
        fi
        printf "  %b %-8s%b %s\n  %b  └─%b %s%b\n" \
          "$badge" "$type" "${C_RESET}" "$desc" "${C_DIM}" "${C_RESET}" "${url:-[starting...]}" "$note"
        found=1
      done <<< "$_pipelines"

      if [ -n "$r_cf_active" ]; then
        [ $found -ne 0 ] && printf "  ${C_DIM}──────────────────────────${C_RESET}\n"
        local u=$(ssh -q "$remote" "grep -oE 'https://.*\.trycloudflare\.com' ~/cf.log 2>/dev/null | tail -1")
        printf "  %b▸ CLD2NET %b Oracle → Global\n  %b  └─%b %s\n" \
          "${B_BLUE}" "${C_RESET}" "${C_DIM}" "${C_RESET}" "${u:-[active]}"
        found=1
      fi

      [ $found -eq 0 ] && printf "\n  %bNo active pipelines%b\n" "${C_DIM}" "${C_RESET}" ;;

    "cld2net")
      local rp="$arg2"; [ -z "$rp" ] && pick_port_oracle rp; [ -z "$rp" ] && return
      echo -e "${C_CYAN}[CLD2NET]${C_RESET} Starting Global Tunnel on $remote..."
      ssh -t "$remote" "pkill -f 'cloudflared tunnel'; cloudflared tunnel --url http://localhost:$rp > ~/cf.log 2>&1 & sleep 2; grep -oE 'https://.*\.trycloudflare\.com' ~/cf.log" ;;

    "lcl2net"|"public")
      local lp="$arg2"
      [ -z "$lp" ] && { style_header "LOCAL PORTS"; list_local_ports | tr ' ' '\n'; _read_input "Port: " lp; }
      [ -z "$lp" ] && return
      pkill -f "cloudflared tunnel" 2>/dev/null
      echo -e "${C_CYAN}[LCL2NET]${C_RESET} Starting Local Tunnel..."; rm -f "$cf_log"; touch "$cf_log"
      cloudflared tunnel --url "http://127.0.0.1:$lp" > "$cf_log" 2>&1 &
      local t=15
      while [ $t -gt 0 ]; do
        local url=$(grep -oE "https://.*\.trycloudflare\.com" "$cf_log" 2>/dev/null | tail -1)
        if [ -n "$url" ]; then echo -e "\n\n${C_GREEN}✓ LIVE:${C_RESET} ${B_MAGENTA}$url${C_RESET}"; return 0; fi
        sleep 1; echo -n "."; ((t--))
      done
      echo -e "\n${C_YELLOW}⚠ Tunnel starting... check st${C_RESET}" ;;

    "cld2lcl"|"fwd")
      local rp; [ -z "$arg2" ] && pick_port_oracle rp || rp="$arg2"; [ -z "$rp" ] && return
      local lp; _read_input "Local port? [$rp]: " lp; lp="${lp:-$rp}"
      echo -e "${C_CYAN}[CLD2LCL]${C_RESET} Oracle:$rp ➔ Local:$lp"
      ssh $ssh_opt -f -N -L "$lp:127.0.0.1:$rp" "$remote"
      echo -e "${C_GREEN}✓ Link: http://127.0.0.1:$lp${C_RESET}" ;;

    "lcl2lan")
      local lp="$arg2"
      [ -z "$lp" ] && { style_header "LOCAL PORTS"; list_local_ports | tr ' ' '\n'; _read_input "Port: " lp; }
      [ -z "$lp" ] && return
      echo -e "${C_CYAN}[LCL2LAN]${C_RESET} Phone:$lp ➔ WiFi: http://$ip:$lp"
      socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" & ;;

    "lcl2all")
      local lp="$arg2"
      [ -z "$lp" ] && { style_header "LOCAL PORTS"; list_local_ports | tr ' ' '\n'; _read_input "Port: " lp; }
      [ -z "$lp" ] && return
      pkill -f "socat.*TCP-LISTEN:$lp" 2>/dev/null
      pkill -f "cloudflared tunnel" 2>/dev/null
      socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
      rm -f "$cf_log"; touch "$cf_log"
      cloudflared tunnel --url "http://127.0.0.1:$lp" > "$cf_log" 2>&1 &
      echo -e "${C_CYAN}[LCL2ALL]${C_RESET} Phone:$lp ➔ WiFi + Internet"
      echo -e "  ${C_GREEN}✓ LAN:${C_RESET} http://$ip:$lp"
      local t=15; echo -n "  Waiting for public URL"
      while [ $t -gt 0 ]; do
        local url=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" "$cf_log" 2>/dev/null | tail -1)
        if [ -n "$url" ]; then echo -e "\n  ${C_GREEN}✓ NET:${C_RESET} ${B_MAGENTA}$url${C_RESET}"; return 0; fi
        sleep 1; echo -n "."; ((t--))
      done
      echo -e "\n  ${C_YELLOW}⚠ Tunnel starting... check tnl st${C_RESET}" ;;

    "cld2all")
      local rp; [ -z "$arg2" ] && pick_port_oracle rp || rp="$arg2"; [ -z "$rp" ] && return
      local lp; _read_input "Local port? [$rp]: " lp; lp="${lp:-$rp}"; kill_port "$lp"
      echo -e "${C_CYAN}[CLD2ALL]${C_RESET} Oracle:$rp ➔ LAN + Internet"
      ssh $ssh_opt -f -N -L "$lp:127.0.0.1:$rp" "$remote"
      socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
      echo -e "  ${C_GREEN}✓ LAN:${C_RESET} http://$ip:$lp"
      pkill -f "cloudflared tunnel" 2>/dev/null
      rm -f "$cf_log"; touch "$cf_log"
      cloudflared tunnel --url "http://127.0.0.1:$lp" > "$cf_log" 2>&1 &
      local t=15; echo -n "  Waiting for public URL"
      while [ $t -gt 0 ]; do
        local url=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" "$cf_log" 2>/dev/null | tail -1)
        if [ -n "$url" ]; then echo -e "\n  ${C_GREEN}✓ NET:${C_RESET} ${B_MAGENTA}$url${C_RESET}"; return 0; fi
        sleep 1; echo -n "."; ((t--))
      done
      echo -e "\n  ${C_YELLOW}⚠ Tunnel starting... check tnl st${C_RESET}" ;;

    "cld2lan"|"bridge")
      style_header "ESTABLISHING BRIDGE"
      check_lan || { local ans; _read_input "No network detected. Try anyway? (y/n): " ans; [[ "$ans" != "y" ]] && return; }
      local rp; [ -z "$arg2" ] && pick_port_oracle rp || rp="$arg2"; [ -z "$rp" ] && return
      local lp; _read_input "Local share port? [$rp]: " lp; lp="${lp:-$rp}"; kill_port "$lp"
      echo -e "\n${C_CYAN}[BRIDGE]${C_RESET} Oracle:$rp ➔ LAN: http://$ip:$lp"
      socat TCP-LISTEN:"$lp",bind="$ip",fork,reuseaddr TCP:127.0.0.1:"$lp" &
      ssh $ssh_opt -f -N -L "$lp:127.0.0.1:$rp" "$remote" ;;

    "deploy")
      style_header "REMOTE SERVER DEPLOYMENT"
      local target_ip; _read_input "Enter Target IP (Tablet): " target_ip
      [ -z "$target_ip" ] && return
      local target_port="${arg2:-6000}"
      echo -e "${C_CYAN}[ACTION]${C_RESET} Deploying File Server to $target_ip..."
      ssh -p 8022 "$target_ip" "nohup python3 -m http.server $target_port > /dev/null 2>&1 &"
      if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}✓ SUCCESS!${C_RESET} Access at: ${B_MAGENTA}http://$target_ip:$target_port${C_RESET}"
      else
        echo -e "${C_RED}✗ FAILED.${C_RESET} Make sure 'sshd' is running on the tablet."
      fi ;;

    "fserver"|"fshare")
      echo -e "${C_YELLOW}⚠ Use 'fshare' directly — see: fshare help${C_RESET}" ;;

    "kx"|"x")
      local p="$arg2"; [ -z "$p" ] && pick_pipeline_port p; [ -z "$p" ] && return 1
      if [[ "$p" == cf_* ]]; then
        pkill -f "cloudflared tunnel"; ssh $ssh_opt "$remote" "pkill -f 'cloudflared tunnel'"
        echo -e "${C_RED}[KILLED]${C_RESET} Cloudflare tunnel stopped."
      else
        # Check if this port belongs to a named SSH tunnel (kill by host, not port)
        local ssh_host=""
        while IFS='|' read -r _type lport rport desc url; do
          if [ "$_type" = "CLD2LCL" ] && [ "$lport" = "$p" ]; then
            ssh_host="${desc%% *}"  # first word is always the host alias
            break
          fi
        done <<< "$(get_active_pipelines)"

        if [ -n "$ssh_host" ]; then
          pkill -f "ssh $ssh_host" 2>/dev/null
          ssh -O exit "$ssh_host" 2>/dev/null  # close ControlMaster if active
          echo -e "${C_RED}[KILLED]${C_RESET} SSH tunnel ${C_BOLD}$ssh_host${C_RESET} (port $p) stopped."
        else
          kill_port "$p"
          echo -e "${C_RED}[KILLED]${C_RESET} Port $p stopped."
        fi
      fi ;;

    "xall")
      pkill -9 -f "socat|http.server|ssh -f -N|cloudflared tunnel"
      ssh $ssh_opt "$remote" "pkill -9 -f 'cloudflared tunnel'" 2>/dev/null
      echo -e "${C_RED}[KILL ALL]${C_RESET} Everything stopped." ;;

    *)
      style_header "SYMMETRIC TNL HELP"
      printf "\n  ${C_DIM}TUNNEL COMMANDS (also work standalone)${C_RESET}\n"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "lcl2lan"  "phone port → WiFi"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "lcl2net"  "phone port → internet"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "lcl2all"  "phone port → WiFi + internet"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "cld2lcl"  "oracle port → phone localhost"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "cld2lan"  "oracle port → phone WiFi"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "cld2net"  "oracle port → internet"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "cld2all"  "oracle port → WiFi + internet"
      printf "\n  ${C_DIM}SYSTEM (tnl only)${C_RESET}\n"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "tnl st"   "network dashboard"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "tnl kx"   "smart kill"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "tnl xall" "kill everything"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "tnl deploy" "deploy server to tablet"
      printf "\n  ${C_DIM}FILE SHARING${C_RESET}\n"
      printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "fshare"   "share folders — see: fshare help\n" ;;
  esac
}

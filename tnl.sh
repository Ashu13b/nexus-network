# ── Network & Tunnels (Truth Dashboard - Optimized UI) ──

tnl() {
  local cmd="$1"; local arg2="$2"; local ip=$(mylan); local remote="${TNL_REMOTE:-ubu}"
  local cf_log="$HOME/.cloudflared.log"; local rem_cf_log="/home/ubuntu/cf.log"
  local ssh_opt="-q -o ConnectTimeout=5"
  local width=${COLUMNS:-$(tput cols 2>/dev/null || echo 40)}

  case "$cmd" in
    "st")
      # --- 1. PROBE STATE ---
      local r_ports_raw=$(ssh -q "$remote" "ss -tlnp 2>/dev/null || lsof -i -P -n | grep LISTEN" 2>/dev/null)
      local r_ports=$(echo "$r_ports_raw" | grep -oE ':\d+' | tr -d ':' | sort -un | tr '\n' ' ' | sed 's/ $//')
      local l_ports=$(list_local_ports)
      local local_ps=$(ps -ef | grep -v grep)
      local r_cf_active=$(ssh -q "$remote" "pgrep -f 'cloudflared tunnel'" 2>/dev/null)

      local c_sym="${C_RED}✗${C_RESET}"; [ -n "$r_ports" ] && c_sym="${C_GREEN}✓${C_RESET}"
      local l_sym="${C_RED}✗${C_RESET}"; [ -n "$l_ports" ] && l_sym="${C_GREEN}✓${C_RESET}"
      local a_sym="${C_RED}✗${C_RESET}"; echo "$local_ps" | grep -q "socat" && a_sym="${C_GREEN}✓${C_RESET}"
      local n_sym="${C_RED}✗${C_RESET}"; [[ -n "$r_cf_active" || "$local_ps" =~ "cloudflared" ]] && n_sym="${C_GREEN}✓${C_RESET}"

      style_header "NETWORK DASHBOARD"
      local summary="[CLD:$c_sym] | [LCL:$l_sym] | [LAN:$a_sym] | [NET:$n_sym]"
      local pad=$(( (width - 34) / 2 )); [ $pad -lt 0 ] && pad=0
      printf "%${pad}s%b\n" "" "$summary"

      printf "\n  %b%-7s%b %s | %b%-6s%b %s\n" \
        "${B_BLUE}" "ORACLE:" "${C_RESET}" "${r_ports:-None}" \
        "${B_GREEN}" "PHONE:" "${C_RESET}" "${l_ports:-None}"

      style_header "PIPELINES & LINKS"
      local found=0

      # [CLD2LCL] Symmetry Check
      for p in $(echo $l_ports); do
        if echo "$r_ports" | grep -qw "$p"; then
          [ $found -ne 0 ] && printf "  ${C_DIM}──────────────────────────${C_RESET}\n"
          printf "  %b[CLD2LCL] Oracle ➔ Phone%b\n  http://127.0.0.1:%s\n" "${B_BLUE}" "${C_RESET}" "$p"
          found=1
        fi
      done

      # [LCL2LAN] [LCL2NET] [HTTP] from discovery engine
      while IFS='|' read -r type port desc url; do
        [ -z "$type" ] && continue
        [ $found -ne 0 ] && printf "  ${C_DIM}──────────────────────────${C_RESET}\n"
        [ "$type" = "CF_L" ] && url=$(grep -oE "https://.*\.trycloudflare\.com" "$cf_log" 2>/dev/null | tail -1)
        printf "  %b[%s] %s%b\n  %s\n" "${B_BLUE}" "$type" "$desc" "${C_RESET}" "${url:-[Starting...]}"
        found=1
      done <<< "$(get_active_pipelines)"

      # [CLD2NET]
      if [ -n "$r_cf_active" ]; then
        [ $found -ne 0 ] && printf "  ${C_DIM}──────────────────────────${C_RESET}\n"
        local u=$(ssh -q "$remote" "grep -oE 'https://.*\.trycloudflare\.com' ~/cf.log 2>/dev/null | tail -1")
        printf "  %b[CLD2NET] Oracle ➔ Global%b\n  %s\n" "${B_BLUE}" "${C_RESET}" "${u:-[Active]}"
        found=1
      fi

      [ $found -eq 0 ] && echo "  No active pipelines detected."
      [ "$ip" != "127.0.0.1" ] && echo -e "\n  ${B_BLUE}LAN IP:${C_RESET} http://$ip" ;;

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
      else
        kill_port "$p"
      fi
      echo -e "${C_RED}[KILLED]${C_RESET} Target stopped." ;;

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

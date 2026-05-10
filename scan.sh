# ── Network Security Auditor (Engineer Edition) ──
unalias scan 2>/dev/null; unalias tnl 2>/dev/null; unalias fshare 2>/dev/null

# Helper: Find the real local subnet
_scan_get_subnet() {
    python -c "
import subprocess, re
try:
    out = subprocess.check_output(['ifconfig'], stderr=subprocess.STDOUT).decode()
    matches = re.findall(r'inet\s+(10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[0-1])\.\d+\.\d+|192\.168\.\d+\.\d+)', out)
    if not matches: matches = re.findall(r'inet\s+(192\.\d+\.\d+\.\d+)', out)
    valid_ips = [ip for ip in matches if ip != '127.0.0.1' and not ip.startswith('192.0.0.')]
    if valid_ips:
        ip = valid_ips[0]
        print('.'.join(ip.split('.')[:-1]) + '.0/24')
    else: print('10.225.222.0/24')
except: print('10.225.222.0/24')
" 2>/dev/null
}

scan() {
    local cmd="$1"
    local target="$2"
    local subnet=$(_scan_get_subnet)

    case "$cmd" in
        "net")
            style_header "DEVICE DISCOVERY ($subnet)"
            echo -e "${C_CYAN}[ACTION]${C_RESET} Probing all nodes..."
            local res=$(nmap -Pn -p 22,80,443,8080,8082 -T4 --max-rtt-timeout 200ms "$subnet" | grep "Nmap scan report" | awk '{print $NF}' | tr -d '()')
            if [ -n "$res" ]; then echo -e "${C_YELLOW}Detected Nodes:${C_RESET}\n$res" | grep -v "127.0.0.1"; else echo -e "${C_RED}No nodes found.${C_RESET}"; fi
            ;;

        "vuln")
            [ -z "$target" ] && { echo -e "${C_RED}Error: Provide IP${C_RESET}"; return 1; }
            style_header "VULNERABILITY AUDIT ($target)"
            echo -e "${C_CYAN}[ACTION]${C_RESET} Running NSE vulnerability scripts..."
            # --script vuln: Checks for known exploits and CVEs
            nmap -Pn --script vuln "$target"
            ;;

        "sniff")
            [ -z "$target" ] && { echo -e "${C_RED}Error: Provide IP${C_RESET}"; return 1; }
            style_header "PLAINTEXT CHECK ($target)"
            local v=$(nmap -Pn -p 21,23,80,110 --open "$target" | grep "open")
            if [ -n "$v" ]; then echo -e "${C_RED}⚠ LEAK DETECTED:${C_RESET}\n$v"; else echo -e "${C_GREEN}✓ SECURE${C_RESET}"; fi
            ;;

        "audit")
            [ -z "$target" ] && target="localhost"
            style_header "FULL STACK AUDIT ($target)"
            # -A: OS detection, Versioning, Script scanning
            nmap -Pn -A -T4 "$target"
            ;;

        *)
            style_header "NEXUS GUARDIAN HELP"
            echo "  scan net          Map all connected devices"
            echo "  scan vuln <ip>    NSE script-based vulnerability check"
            echo "  scan sniff <ip>   Check for unencrypted leaks"
            echo "  scan audit <ip>   Detailed OS/Version fingerprinting"
            ;;
    esac
}

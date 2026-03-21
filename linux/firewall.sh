#!/usr/bin/env bash
# LAN Firewall Setup for llama-server (Linux)
# Opens the llama-server port via ufw / firewalld / iptables
# Usage: ./firewall.sh [port]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${ROOT_DIR}/config/settings.ini"
PORT="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- read port from config ---
if [[ -z "$PORT" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        PORT=$(grep -E '^PORT\s*=' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ' | head -1)
    fi
    PORT="${PORT:-8080}"
fi

# --- get LAN IPs ---
get_lan_ips() {
    ip -4 addr show 2>/dev/null | grep 'inet ' | grep -v '127\.' | awk '{print $2}' | cut -d/ -f1
}

echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  llama-server LAN Firewall Setup${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""

info "This machine's LAN IP addresses:"
while IFS= read -r ip; do
    echo -e "    ${GREEN}${ip}${NC}"
done < <(get_lan_ips)
echo ""
info "Port to open: $PORT"
echo ""

# --- detect firewall tool ---
detect_fw() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status:"; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "firewalld"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

FW=$(detect_fw)
info "Detected firewall: $FW"
echo ""

read -rp "Open port $PORT for LAN access? (Y/n): " go
[[ "${go,,}" == "n" ]] && exit 0

# --- open port ---
case "$FW" in
    ufw)
        sudo ufw allow "$PORT/tcp" comment "llama-server LAN"
        sudo ufw reload
        ok "ufw: opened TCP $PORT"
        ;;
    firewalld)
        sudo firewall-cmd --permanent --add-port="${PORT}/tcp"
        sudo firewall-cmd --reload
        ok "firewalld: opened TCP $PORT"
        ;;
    iptables)
        # check if rule already exists
        if sudo iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
            warn "iptables rule already exists for port $PORT"
        else
            sudo iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
            ok "iptables: opened TCP $PORT"
        fi
        # persist rules
        if command -v netfilter-persistent &>/dev/null; then
            sudo netfilter-persistent save
            ok "Rules saved via netfilter-persistent"
        elif command -v iptables-save &>/dev/null; then
            sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null 2>/dev/null || \
            sudo iptables-save | sudo tee /etc/iptables.rules >/dev/null 2>/dev/null || true
            warn "Saved to iptables rules file (verify persistence on reboot)"
        fi
        ;;
    none)
        warn "No active firewall detected. Port may already be open."
        warn "If using a cloud VM, open port $PORT in the security group/console."
        ;;
esac

# --- update config bind address ---
echo ""
info "Updating config HOST to 0.0.0.0 for LAN binding..."
if [[ -f "$CONFIG_FILE" ]]; then
    sed -i "s/^HOST\s*=.*/HOST=0.0.0.0/" "$CONFIG_FILE"
    ok "config/settings.ini: HOST=0.0.0.0"
else
    warn "config/settings.ini not found. Pass host manually: ./serve.sh <model> <port>"
fi

# --- show summary ---
echo ""
echo -e "${BOLD}============================================================${NC}"
echo -e "${BOLD}  Setup Complete${NC}"
echo -e "${BOLD}============================================================${NC}"
echo ""
echo "  LAN clients can now connect to:"
while IFS= read -r ip; do
    echo -e "    ${CYAN}http://${ip}:${PORT}${NC}"
done < <(get_lan_ips)
echo ""
echo -e "  To revert (block LAN access):" -ForegroundColor DarkGray
case "$FW" in
    ufw)       echo "    sudo ufw delete allow ${PORT}/tcp" ;;
    firewalld) echo "    sudo firewall-cmd --permanent --remove-port=${PORT}/tcp && sudo firewall-cmd --reload" ;;
    iptables)  echo "    sudo iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT" ;;
esac
echo ""

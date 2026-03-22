#!/usr/bin/env bash
# GPT-OSS 20B Gradio Frontend Launcher (Linux)
# Usage: ./frontend.sh
#        ./frontend.sh --host 0.0.0.0 --port 7860
#        ./frontend.sh --share
#        ./frontend.sh --server http://192.168.1.10:8080

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${ROOT_DIR}/config/settings.ini"
FRONTEND_DIR="${ROOT_DIR}/frontend"
APP_PY="${FRONTEND_DIR}/app.py"
REQ_TXT="${FRONTEND_DIR}/requirements.txt"

# ── defaults ──────────────────────────────────────────────────
FRONTEND_HOST="127.0.0.1"
FRONTEND_PORT="7860"
SERVER=""
SHARE=""

# ── parse args ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)   FRONTEND_HOST="$2"; shift 2 ;;
        --port)   FRONTEND_PORT="$2"; shift 2 ;;
        --server) SERVER="$2";        shift 2 ;;
        --share)  SHARE="--share";    shift   ;;
        *) shift ;;
    esac
done

# ── read llama-server URL from settings.ini ───────────────────
if [[ -z "$SERVER" ]]; then
    CFG_HOST="127.0.0.1"; CFG_PORT="8080"
    if [[ -f "$CONFIG_FILE" ]]; then
        _h=$(grep -E '^HOST=' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')
        _p=$(grep -E '^PORT=' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')
        CFG_HOST="${_h:-$CFG_HOST}"; CFG_PORT="${_p:-$CFG_PORT}"
    fi
    # if server is bound to 0.0.0.0, connect via localhost
    LLM_HOST="$CFG_HOST"
    [[ "$CFG_HOST" == "0.0.0.0" ]] && LLM_HOST="127.0.0.1"
    SERVER="http://${LLM_HOST}:${CFG_PORT}"
fi

B='\033[1m'; C='\033[0;36m'; G='\033[0;32m'; Y='\033[1;33m'; N='\033[0m'

echo ""
echo -e "${B}============================================================${N}"
echo -e "${B}  GPT-OSS 20B  Gradio Frontend${N}"
echo -e "${B}============================================================${N}"
echo ""
echo -e "  llama-server : ${C}${SERVER}${N}"
echo -e "  UI address   : ${G}http://${FRONTEND_HOST}:${FRONTEND_PORT}${N}"
[[ -n "$SHARE" ]] && echo -e "  Gradio share : ${Y}enabled (public link)${N}"
echo ""

# ── check python ──────────────────────────────────────────────
PYTHON=""
for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then PYTHON="$cmd"; break; fi
done
if [[ -z "$PYTHON" ]]; then
    echo "ERROR: Python not found. Install Python 3.9+ and retry."
    exit 1
fi

# ── install / check dependencies ─────────────────────────────
echo -e "${C}Checking dependencies...${N}"
if ! "$PYTHON" -c "import gradio" &>/dev/null; then
    echo -e "${Y}Installing frontend requirements...${N}"
    "$PYTHON" -m pip install -r "$REQ_TXT" --quiet
fi

# ── launch ────────────────────────────────────────────────────
echo -e "${G}Starting Gradio...${N}"
echo ""
exec "$PYTHON" "$APP_PY" \
    --server  "$SERVER" \
    --host    "$FRONTEND_HOST" \
    --port    "$FRONTEND_PORT" \
    $SHARE

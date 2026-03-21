#!/usr/bin/env bash
# llama-server Status & Usage Monitor (Linux)
# Usage: ./status.sh [host] [port]
#        ./status.sh              # uses settings.ini defaults
#        ./status.sh 0.0.0.0 8080 # override

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${ROOT_DIR}/config/settings.ini"

# ── defaults ──────────────────────────────────────────────────
HOST="127.0.0.1"; PORT="8080"
if [[ -f "$CONFIG_FILE" ]]; then
    _h=$(grep -E '^HOST=' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')
    _p=$(grep -E '^PORT=' "$CONFIG_FILE" | cut -d= -f2 | tr -d ' ')
    HOST="${_h:-$HOST}"; PORT="${_p:-$PORT}"
fi
[[ -n "${1:-}" ]] && HOST="$1"
[[ -n "${2:-}" ]] && PORT="$2"
BASE="http://${HOST}:${PORT}"

# ── colours ───────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; D='\033[2m'; N='\033[0m'

# ── parse prometheus metric ───────────────────────────────────
metric() { grep -E "^${1}[{ ]" <<< "$METRICS" | tail -1 | awk '{print $NF}'; }

print_status() {
    clear
    echo -e "${B}============================================================${N}"
    echo -e "${B}  llama-server Status${N}  ${D}${BASE}${N}  $(date '+%H:%M:%S')"
    echo -e "${B}============================================================${N}"

    # ── health ────────────────────────────────────────────────
    HEALTH=$(curl -sf "${BASE}/health" 2>/dev/null)
    if [[ -z "$HEALTH" ]]; then
        echo -e "\n  ${R}[OFFLINE]${N}  Server not reachable at ${BASE}\n"
        return
    fi
    STATUS=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null)
    SLOTS_IDLE=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('slots_idle','?'))" 2>/dev/null)
    SLOTS_PROC=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('slots_processing','?'))" 2>/dev/null)

    if [[ "$STATUS" == "ok" ]]; then
        echo -e "\n  Health    : ${G}OK${N}"
    else
        echo -e "\n  Health    : ${Y}${STATUS}${N}"
    fi
    echo -e "  Slots     : ${G}${SLOTS_IDLE} idle${N}  /  ${Y}${SLOTS_PROC} active${N}"

    # ── metrics ───────────────────────────────────────────────
    METRICS=$(curl -sf "${BASE}/metrics" 2>/dev/null)
    if [[ -z "$METRICS" ]]; then
        echo -e "\n  ${D}(metrics endpoint not available — start server with --metrics)${N}"
    else
        # tokens
        PROMPT_TOK=$(metric "llamacpp:tokens_evaluated_total")
        GEN_TOK=$(metric "llamacpp:tokens_predicted_total")
        # throughput
        PROMPT_TP=$(metric "llamacpp:prompt_tokens_per_second")
        GEN_TP=$(metric "llamacpp:predicted_tokens_per_second")
        # requests
        REQ_TOTAL=$(metric "llamacpp:requests_processing_total")
        REQ_FAIL=$(metric "llamacpp:requests_failed_total")
        # KV cache
        KV_USED=$(metric "llamacpp:kv_cache_usage_ratio")
        KV_CELLS=$(metric "llamacpp:kv_cache_tokens")

        echo ""
        echo -e "  ${B}── Throughput ────────────────────────────────────${N}"
        printf "  %-18s ${C}%s${N} tok/s\n"  "Prompt speed:"     "${PROMPT_TP:-n/a}"
        printf "  %-18s ${G}%s${N} tok/s\n"  "Generate speed:"   "${GEN_TP:-n/a}"

        echo ""
        echo -e "  ${B}── Tokens ───────────────────────────────────────${N}"
        printf "  %-18s %s\n" "Prompt processed:" "${PROMPT_TOK:-n/a}"
        printf "  %-18s %s\n" "Tokens generated:" "${GEN_TOK:-n/a}"

        echo ""
        echo -e "  ${B}── Requests ─────────────────────────────────────${N}"
        printf "  %-18s %s\n" "Total:"   "${REQ_TOTAL:-n/a}"
        printf "  %-18s ${R}%s${N}\n" "Failed:" "${REQ_FAIL:-n/a}"

        echo ""
        echo -e "  ${B}── KV Cache ─────────────────────────────────────${N}"
        if [[ -n "$KV_USED" ]]; then
            PCT=$(echo "$KV_USED * 100" | bc -l 2>/dev/null | xargs printf "%.1f")
            printf "  %-18s %s%%\n" "Usage:" "${PCT:-n/a}"
        fi
        printf "  %-18s %s tokens\n" "Cached tokens:" "${KV_CELLS:-n/a}"
    fi

    # ── GPU ───────────────────────────────────────────────────
    if command -v nvidia-smi &>/dev/null; then
        echo ""
        echo -e "  ${B}── GPU ──────────────────────────────────────────${N}"
        nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu \
            --format=csv,noheader 2>/dev/null | while IFS=, read -r name util mem_used mem_total temp; do
            printf "  %-18s %s\n"  "GPU:"       "${name// /}"
            printf "  %-18s ${Y}%s${N}\n"       "Utilization:" "${util// /}"
            printf "  %-18s %s / %s\n"          "VRAM:"        "${mem_used// /}" "${mem_total// /}"
            printf "  %-18s %s\n"               "Temp:"        "${temp// /}°C"
        done
    fi

    echo ""
    echo -e "  ${D}Refreshes every 3s — Ctrl+C to exit${N}"
    echo -e "${B}============================================================${N}"
}

# ── one-shot or watch loop ────────────────────────────────────
if [[ "${1:-}" == "--once" || "${2:-}" == "--once" || "${3:-}" == "--once" ]]; then
    print_status
else
    while true; do
        print_status
        sleep 3
    done
fi

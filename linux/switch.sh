#!/usr/bin/env bash
# ============================================================
# GPT-OSS 20B 設定快速切換工具
# 用途: 切換 settings.local.ini 預設組合
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOCAL_CFG="${ROOT_DIR}/config/settings.local.ini"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── 預設組合 ─────────────────────────────────────────────────
# 格式: "名稱|說明|N_GPU_LAYERS|CTX_SIZE|N_PREDICT|N_PARALLEL|N_THREADS"
PRESETS=(
    "純CPU|安全模式，無 GPU，適合測試|0|4096|-1|1|8"
    "混合30層|GPU+CPU，RTX 3060 12GB 推薦|30|6144|-1|1|8"
    "混合20層(32k)|4層留CPU釋放VRAM，支援32k長文本|20|32768|-1|1|8"
    "混合35層|GPU+CPU，記憶體較充裕時使用|35|6144|-1|1|8"
    "全GPU|全部 offload，VRAM 需夠用|-1|8192|-1|2|4"
    "高並行|多用戶，4 槽平行處理|30|4096|-1|4|8"
    "長文本|單用戶，最大 context 32k|30|32768|-1|1|8"
)

# ─── 讀取目前設定 ──────────────────────────────────────────────
show_current() {
    echo
    echo -e "${BOLD}── 目前 settings.local.ini ──${NC}"
    if [[ -f "$LOCAL_CFG" ]]; then
        while IFS= read -r line; do
            echo -e "  ${DIM}${line}${NC}"
        done < "$LOCAL_CFG"
    else
        echo -e "  ${DIM}(尚未建立，使用 settings.ini 預設值)${NC}"
    fi
    echo
}

# ─── 寫入設定 ─────────────────────────────────────────────────
write_preset() {
    local gpu="$1" ctx="$2" predict="$3" parallel="$4" threads="$5"
    cat > "$LOCAL_CFG" << EOF
[server]
N_GPU_LAYERS=${gpu}
N_THREADS=${threads}

[inference]
CTX_SIZE=${ctx}
N_PREDICT=${predict}
N_PARALLEL=${parallel}
EOF
    echo -e "${GREEN}[成功]${NC} 已寫入 ${LOCAL_CFG}"
}

write_custom() {
    echo
    echo -e "${BOLD}── 自訂設定 (按 Enter 保留目前值) ──${NC}"
    echo

    # 讀取目前值
    local cur_gpu="0" cur_ctx="8192" cur_predict="-1" cur_parallel="1" cur_threads="8"
    if [[ -f "$LOCAL_CFG" ]]; then
        while IFS='=' read -r k v; do
            k="${k// /}"; v="${v// /}"
            case "$k" in
                N_GPU_LAYERS) cur_gpu="$v" ;;
                CTX_SIZE)     cur_ctx="$v" ;;
                N_PREDICT)    cur_predict="$v" ;;
                N_PARALLEL)   cur_parallel="$v" ;;
                N_THREADS)    cur_threads="$v" ;;
            esac
        done < "$LOCAL_CFG"
    fi

    read -rp "  GPU 層數    [${cur_gpu}]  (0=CPU, -1=全GPU, 30=混合): " v
    local gpu="${v:-$cur_gpu}"

    read -rp "  Context     [${cur_ctx}]  (4096 / 6144 / 8192 / 32768): " v
    local ctx="${v:-$cur_ctx}"

    read -rp "  Max tokens  [${cur_predict}]  (-1=不限): " v
    local predict="${v:-$cur_predict}"

    read -rp "  平行槽數    [${cur_parallel}]  (1=單用戶, 4=多用戶): " v
    local parallel="${v:-$cur_parallel}"

    read -rp "  CPU 執行緒  [${cur_threads}]: " v
    local threads="${v:-$cur_threads}"

    echo
    write_preset "$gpu" "$ctx" "$predict" "$parallel" "$threads"
}

# ─── 主選單 ───────────────────────────────────────────────────
main() {
    clear
    echo
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  GPT-OSS 20B 設定快速切換${NC}"
    echo -e "${BOLD}============================================================${NC}"

    show_current

    echo -e "${BOLD}── 選擇預設組合 ──${NC}"
    echo
    local i=1
    for preset in "${PRESETS[@]}"; do
        IFS='|' read -r name desc gpu ctx predict parallel threads <<< "$preset"
        printf "  ${CYAN}[%d]${NC} %-10s ${DIM}%s${NC}\n" "$i" "$name" "$desc"
        printf "       GPU層數:%-4s  Context:%-6s  平行槽:%-2s  執行緒:%s\n" \
               "$gpu" "$ctx" "$parallel" "$threads"
        echo
        ((i++))
    done
    printf "  ${CYAN}[%d]${NC} %-10s ${DIM}手動輸入每個設定值${NC}\n" "$i" "自訂"
    echo
    printf "  ${CYAN}[0]${NC} %-10s ${DIM}不修改，直接離開${NC}\n" "離開"
    echo

    read -rp "請選擇 [0-${i}]: " choice

    if [[ "$choice" == "0" ]]; then
        echo; exit 0
    fi

    if [[ "$choice" == "$i" ]]; then
        write_custom
    elif [[ "$choice" -ge 1 && "$choice" -lt "$i" ]]; then
        IFS='|' read -r name desc gpu ctx predict parallel threads <<< "${PRESETS[$((choice-1))]}"
        echo
        echo -e "${CYAN}[資訊]${NC} 套用預設組合: ${BOLD}${name}${NC}"
        write_preset "$gpu" "$ctx" "$predict" "$parallel" "$threads"
    else
        echo -e "${RED}[錯誤]${NC} 無效選項"; exit 1
    fi

    echo
    echo -e "${YELLOW}[提示]${NC} 重新執行 ./serve.sh 讓設定生效"
    echo
}

main "$@"

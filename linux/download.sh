#!/usr/bin/env bash
# ============================================================
# GPT-OSS 20B 模型下載腳本 (Linux/macOS)
# 用途: 從 HuggingFace 下載指定的 GGUF 模型檔案
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="${ROOT_DIR}/models"
HF_REPO="DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf"
HF_BASE_URL="https://huggingface.co/${HF_REPO}/resolve/main"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${CYAN}[資訊]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[警告]${NC} $*"; }
log_error()   { echo -e "${RED}[錯誤]${NC} $*"; }

# 建立 models 目錄
mkdir -p "$MODELS_DIR"

# ─── 偵測下載工具 ────────────────────────────────────────────
detect_downloader() {
    if command -v huggingface-cli &>/dev/null; then
        echo "hf-cli"
    elif python3 -c "import huggingface_hub" &>/dev/null 2>&1; then
        echo "python"
    elif command -v wget &>/dev/null; then
        echo "wget"
    elif command -v curl &>/dev/null; then
        echo "curl"
    else
        echo ""
    fi
}

# ─── 顯示標頭 ────────────────────────────────────────────────
print_header() {
    echo
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  GPT-OSS 20B 模型下載工具${NC}"
    echo -e "  Repository: ${CYAN}${HF_REPO}${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo
}

# ─── 模型選單 ────────────────────────────────────────────────
select_model() {
    echo -e "${BOLD}請選擇量化類型:${NC}"
    echo
    echo "  [1] IQ4_NL  - 約 12GB  ▸ 創意/娛樂用途 (Imatrix 最強效果)"
    echo "  [2] Q5_1    - 約 16GB  ▸ 均衡/一般用途 (穩定性佳)"
    echo "  [3] Q8_0    - 約 22GB  ▸ 最高品質      (檔案最大)"
    echo "  [4] 手動輸入檔名"
    echo "  [0] 結束"
    echo
    read -rp "請輸入選項 (0-4): " QUANT_CHOICE

    case "$QUANT_CHOICE" in
        0) exit 0 ;;
        1) select_iq4_model ;;
        2) select_q51_model ;;
        3) select_q80_model ;;
        4) manual_input ;;
        *) log_error "無效選項"; exit 1 ;;
    esac
}

select_iq4_model() {
    echo
    echo -e "${BOLD}=== IQ4_NL 模型清單 (約 12GB) ===${NC}"
    local models=(
        "OpenAI-20B-NEO-Uncensored2-IQ4_NL.gguf|標準"
        "OpenAI-20B-NEOPlus-Uncensored-IQ4_NL.gguf|增強版"
        "OpenAI-20B-NEO-CODEPlus16-Uncensored-IQ4_NL.gguf|程式碼加強"
        "OpenAI-20B-NEO-HRRPlus-Uncensored-IQ4_NL.gguf|DI-Matrix"
        "OpenAI-20B-NEO-CODEPlus-Uncensored-IQ4_NL.gguf|DI-Matrix 程式碼"
        "OpenAI-20B-NEO-CODE2-Plus-Uncensored-IQ4_NL.gguf|程式碼 v2"
        "OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-IQ4_NL.gguf|TRI-Matrix"
    )
    choose_from_list "${models[@]}"
}

select_q51_model() {
    echo
    echo -e "${BOLD}=== Q5_1 模型清單 (約 16GB) ===${NC}"
    local models=(
        "OpenAI-20B-NEO-Uncensored2-Q5_1.gguf|標準"
        "OpenAI-20B-NEOPlus-Uncensored-Q5_1.gguf|增強版"
        "OpenAI-20B-NEO-CODEPlus-Uncensored-Q5_1.gguf|程式碼"
        "OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q5_1.gguf|TRI-Matrix"
        "OpenAI-20B-NEO-HRR-DI-Uncensored-Q5_1.gguf|DI-Matrix"
        "OpenAI-20B-NEO-CODE-DI-Uncensored-Q5_1.gguf|DI-Matrix 程式碼"
    )
    choose_from_list "${models[@]}"
}

select_q80_model() {
    echo
    echo -e "${BOLD}=== Q8_0 模型清單 (約 22GB) ===${NC}"
    local models=(
        "OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf|增強版"
        "OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q8_0.gguf|TRI-Matrix"
        "OpenAI-20B-NEO-HRR-CODE-5-TRI-Uncensored-Q8_0.gguf|TRI-Matrix v5"
        "OpenAI-20B-NEO-HRR-DI-Uncensored-Q8_0.gguf|DI-Matrix"
        "OpenAI-20B-NEO-CODE-DI-Uncensored-Q8_0.gguf|DI-Matrix 程式碼"
    )
    choose_from_list "${models[@]}"
}

choose_from_list() {
    local models=("$@")
    local i=1
    for entry in "${models[@]}"; do
        local name="${entry%%|*}"
        local desc="${entry##*|}"
        printf "  [%d] %-55s (%s)\n" "$i" "$name" "$desc"
        ((i++))
    done
    echo "  [0] 返回"
    echo
    read -rp "請選擇模型 (0-$((i-1))): " MODEL_IDX

    if [[ "$MODEL_IDX" == "0" ]]; then
        select_model
        return
    fi

    if [[ "$MODEL_IDX" -ge 1 && "$MODEL_IDX" -lt "$i" ]]; then
        MODEL_FILE="${models[$((MODEL_IDX-1))]%%|*}"
    else
        log_error "無效選項"
        exit 1
    fi
}

manual_input() {
    echo
    read -rp "請輸入完整檔名 (例: OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf): " MODEL_FILE
    if [[ -z "$MODEL_FILE" ]]; then
        log_error "檔名不能為空"
        exit 1
    fi
}

# ─── 執行下載 ────────────────────────────────────────────────
do_download() {
    local model_file="$1"
    local dest_path="${MODELS_DIR}/${model_file}"
    local hf_url="${HF_BASE_URL}/${model_file}"
    local downloader
    downloader="$(detect_downloader)"

    echo
    echo -e "${BOLD}============================================================${NC}"
    echo -e "  準備下載:"
    echo -e "    檔案: ${CYAN}${model_file}${NC}"
    echo -e "    目標: ${dest_path}"
    echo -e "    來源: ${hf_url}"
    echo -e "${BOLD}============================================================${NC}"
    echo

    # 檢查是否已存在
    if [[ -f "$dest_path" ]]; then
        local size_mb
        size_mb=$(du -m "$dest_path" | cut -f1)
        log_warn "檔案已存在 (${size_mb} MB): ${dest_path}"
        read -rp "是否重新下載? (y/N): " OVERWRITE
        if [[ "${OVERWRITE,,}" != "y" ]]; then
            log_info "取消下載"
            return 0
        fi
        rm -f "$dest_path"
    fi

    if [[ -z "$downloader" ]]; then
        log_error "找不到下載工具，請安裝以下其中之一:"
        echo "  pip install huggingface_hub[cli]"
        echo "  sudo apt install wget  # 或 curl"
        exit 1
    fi

    log_info "使用下載工具: ${downloader}"

    case "$downloader" in
        hf-cli)
            log_info "使用 huggingface-cli 下載..."
            huggingface-cli download "$HF_REPO" "$model_file" \
                --local-dir "$MODELS_DIR" \
                --local-dir-use-symlinks False
            ;;
        python)
            log_info "使用 Python huggingface_hub 下載..."
            python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(
    repo_id='${HF_REPO}',
    filename='${model_file}',
    local_dir='${MODELS_DIR}',
    local_dir_use_symlinks=False
)"
            ;;
        wget)
            log_info "使用 wget 下載 (支援斷點續傳)..."
            wget -c --show-progress \
                --header="User-Agent: Mozilla/5.0" \
                "$hf_url" -O "$dest_path"
            ;;
        curl)
            log_info "使用 curl 下載..."
            log_warn "curl 不支援斷點續傳，建議安裝 wget 或 huggingface-cli"
            curl -L --progress-bar \
                -H "User-Agent: Mozilla/5.0" \
                -C - "$hf_url" -o "$dest_path"
            ;;
    esac

    if [[ $? -ne 0 ]]; then
        log_error "下載失敗!"
        log_info "提示: 若需要認證，請設定環境變數: export HF_TOKEN=your_token"
        exit 1
    fi

    # 驗證下載結果
    if [[ -f "$dest_path" ]]; then
        local final_size
        final_size=$(du -sh "$dest_path" | cut -f1)
        echo
        log_success "模型下載完成!"
        echo -e "  路徑: ${CYAN}${dest_path}${NC}"
        echo -e "  大小: ${final_size}"
        echo
        echo -e "  ${YELLOW}[提示]${NC} 可執行 serve.sh 啟動模型服務"
    else
        log_error "下載後找不到檔案: ${dest_path}"
        exit 1
    fi
}

# ─── 主程式 ──────────────────────────────────────────────────
main() {
    print_header

    local downloader
    downloader="$(detect_downloader)"
    if [[ -n "$downloader" ]]; then
        log_info "偵測到下載工具: ${downloader}"
    else
        log_warn "未找到推薦下載工具，建議執行: pip install huggingface_hub[cli]"
    fi
    echo

    # 支援命令列直接指定檔名: ./download.sh OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf
    if [[ $# -ge 1 ]]; then
        MODEL_FILE="$1"
        log_info "命令列模式，直接下載: ${MODEL_FILE}"
    else
        select_model
    fi

    do_download "$MODEL_FILE"
}

main "$@"

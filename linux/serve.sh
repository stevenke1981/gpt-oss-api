#!/usr/bin/env bash
# ============================================================
# GPT-OSS 20B 模型服務腳本 (Linux/macOS)
# 用途: 使用 llama.cpp 啟動 OpenAI 相容 API 服務
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="${ROOT_DIR}/models"
CONFIG_FILE="${ROOT_DIR}/config/settings.ini"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}[資訊]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[警告]${NC} $*"; }
log_error()   { echo -e "${RED}[錯誤]${NC} $*" >&2; }

# ─── 載入設定檔 ───────────────────────────────────────────────
HOST="127.0.0.1"
PORT="8080"
N_GPU_LAYERS="0"
N_THREADS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
CTX_SIZE="8192"
N_PARALLEL="4"
BATCH_SIZE="512"
TEMPERATURE="0.8"
REPEAT_PENALTY="1.1"
TOP_K="40"
TOP_P="0.95"
ENABLE_JINJA="false"
MIN_P="0.05"
CACHE_TYPE_K="q8_0"
CACHE_TYPE_V="q8_0"
DEFRAG_THOLD="0.1"
DISABLE_FLASH_ATTN="false"

if [[ -f "$CONFIG_FILE" ]]; then
    while IFS='=' read -r key val; do
        key="${key// /}"
        val="${val// /}"
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        case "$key" in
            HOST)                HOST="$val" ;;
            PORT)                PORT="$val" ;;
            N_GPU_LAYERS)        N_GPU_LAYERS="$val" ;;
            N_THREADS)           N_THREADS="$val" ;;
            CTX_SIZE)            CTX_SIZE="$val" ;;
            N_PARALLEL)          N_PARALLEL="$val" ;;
            BATCH_SIZE)          BATCH_SIZE="$val" ;;
            TEMPERATURE)         TEMPERATURE="$val" ;;
            REPEAT_PENALTY)      REPEAT_PENALTY="$val" ;;
            TOP_K)               TOP_K="$val" ;;
            TOP_P)               TOP_P="$val" ;;
            MIN_P)               MIN_P="$val" ;;
            ENABLE_JINJA)        ENABLE_JINJA="$val" ;;
            CACHE_TYPE_K)        CACHE_TYPE_K="$val" ;;
            CACHE_TYPE_V)        CACHE_TYPE_V="$val" ;;
            DEFRAG_THOLD)        DEFRAG_THOLD="$val" ;;
            DISABLE_FLASH_ATTN)  DISABLE_FLASH_ATTN="$val" ;;
        esac
    done < "$CONFIG_FILE"
fi

# ─── 尋找 llama-server ────────────────────────────────────────
find_llama_server() {
    local candidates=(
        "llama-server"
        "${ROOT_DIR}/llama.cpp/llama-server"
        "${ROOT_DIR}/llama.cpp/build/bin/llama-server"
        "/usr/local/bin/llama-server"
        "/usr/bin/llama-server"
        "${HOME}/.local/bin/llama-server"
        "${HOME}/llama.cpp/build/bin/llama-server"
        "/opt/llama.cpp/llama-server"
    )

    for c in "${candidates[@]}"; do
        if command -v "$c" &>/dev/null 2>&1 || [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done

    # 嘗試 PATH 搜尋
    if command -v llama-server &>/dev/null; then
        echo "llama-server"
        return 0
    fi

    return 1
}

show_install_guide() {
    echo
    echo -e "${BOLD}找不到 llama-server，請選擇安裝方式:${NC}"
    echo
    echo -e "  ${CYAN}[方法 1]${NC} 套件管理器安裝 (最簡單):"
    echo "    # Ubuntu/Debian:"
    echo "    sudo apt install llama-cpp"
    echo
    echo -e "  ${CYAN}[方法 2]${NC} 自行編譯 CPU 版本:"
    echo "    git clone https://github.com/ggerganov/llama.cpp.git ${ROOT_DIR}/llama.cpp"
    echo "    cd ${ROOT_DIR}/llama.cpp"
    echo "    cmake -B build -DCMAKE_BUILD_TYPE=Release"
    echo "    cmake --build build --config Release -j\$(nproc)"
    echo "    sudo cmake --install build"
    echo
    echo -e "  ${CYAN}[方法 3]${NC} NVIDIA GPU (CUDA) 版本:"
    echo "    cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release"
    echo "    cmake --build build --config Release -j\$(nproc)"
    echo
    echo -e "  ${CYAN}[方法 4]${NC} Apple Silicon (Metal) 版本:"
    echo "    cmake -B build -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release"
    echo "    cmake --build build --config Release -j\$(nproc)"
    echo
    echo -e "  ${CYAN}[方法 5]${NC} pip 安裝 (Python):"
    echo "    pip install llama-cpp-python[server]"
    echo "    # 啟動方式改為:"
    echo "    # python -m llama_cpp.server --model <path>"
    echo
}

# ─── 偵測 GPU ─────────────────────────────────────────────────
detect_gpu() {
    local gpu_info=""
    if command -v nvidia-smi &>/dev/null; then
        gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
        if [[ -n "$gpu_info" ]]; then
            echo "NVIDIA: ${gpu_info}"
            return
        fi
    fi
    if [[ "$(uname)" == "Darwin" ]]; then
        if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Apple M"; then
            echo "Apple Silicon (Metal)"
            return
        fi
    fi
    if command -v rocm-smi &>/dev/null; then
        echo "AMD ROCm GPU"
        return
    fi
    echo "無 (純 CPU 模式)"
}

# ─── 選擇模型 ─────────────────────────────────────────────────
select_model() {
    mapfile -t MODEL_FILES < <(find "$MODELS_DIR" -maxdepth 1 -name "*.gguf" -type f | sort)

    if [[ ${#MODEL_FILES[@]} -eq 0 ]]; then
        log_error "models 目錄中沒有 .gguf 檔案"
        log_info "請先執行 download.sh 下載模型"
        exit 1
    fi

    echo
    echo -e "${BOLD}=== 選擇要啟動的模型 ===${NC}"
    echo
    local i=1
    for f in "${MODEL_FILES[@]}"; do
        local size
        size=$(du -sh "$f" | cut -f1)
        printf "  ${CYAN}[%d]${NC} %-55s ${DIM}(%s)${NC}\n" "$i" "$(basename "$f")" "$size"
        ((i++))
    done
    echo
    read -rp "請選擇模型編號: " MODEL_NUM

    if [[ "$MODEL_NUM" -lt 1 || "$MODEL_NUM" -gt "${#MODEL_FILES[@]}" ]]; then
        log_error "無效的模型編號"
        exit 1
    fi

    SELECTED_MODEL="${MODEL_FILES[$((MODEL_NUM-1))]}"
}

# ─── 互動式參數設定 ───────────────────────────────────────────
configure_params() {
    echo
    echo -e "${BOLD}=== 啟動參數設定 (按 Enter 使用預設值) ===${NC}"
    echo

    read -rp "  服務位址        [${HOST}]: " v
    HOST="${v:-$HOST}"

    read -rp "  服務埠號        [${PORT}]: " v
    PORT="${v:-$PORT}"

    read -rp "  上下文長度      [${CTX_SIZE}] (8192-131072): " v
    CTX_SIZE="${v:-$CTX_SIZE}"

    read -rp "  GPU 層數        [${N_GPU_LAYERS}] (0=純CPU, -1=全GPU): " v
    N_GPU_LAYERS="${v:-$N_GPU_LAYERS}"

    read -rp "  CPU 執行緒數    [${N_THREADS}]: " v
    N_THREADS="${v:-$N_THREADS}"

    read -rp "  平行處理槽數    [${N_PARALLEL}]: " v
    N_PARALLEL="${v:-$N_PARALLEL}"
}

# ─── 啟動服務 ─────────────────────────────────────────────────
start_server() {
    local llama_server="$1"
    local model_path="$2"

    echo
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  啟動設定摘要${NC}"
    echo -e "${BOLD}============================================================${NC}"
    printf "  %-14s %s\n" "模型:" "$(basename "$model_path")"
    printf "  %-14s ${GREEN}http://%s:%s${NC}\n" "API 位址:" "$HOST" "$PORT"
    printf "  %-14s %s tokens\n" "上下文:" "$CTX_SIZE"
    printf "  %-14s %s\n" "GPU 層數:" "$N_GPU_LAYERS"
    printf "  %-14s %s\n" "執行緒:" "$N_THREADS"
    printf "  %-14s %s\n" "平行槽數:" "$N_PARALLEL"
    echo -e "${BOLD}------------------------------------------------------------${NC}"
    echo -e "  API 端點:"
    echo -e "    聊天:   ${CYAN}http://${HOST}:${PORT}/v1/chat/completions${NC}"
    echo -e "    補全:   ${CYAN}http://${HOST}:${PORT}/v1/completions${NC}"
    echo -e "    健康:   ${CYAN}http://${HOST}:${PORT}/health${NC}"
    echo -e "    指標:   ${CYAN}http://${HOST}:${PORT}/metrics${NC}"
    echo -e "    Web UI: ${CYAN}http://${HOST}:${PORT}${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo

    read -rp "確認啟動服務? (Y/n): " CONFIRM
    [[ "${CONFIRM,,}" == "n" ]] && exit 0

    echo
    log_info "正在啟動 llama-server..."
    log_info "按 Ctrl+C 停止服務"
    echo

    # 構建啟動命令
    local cmd_args=(
        --model          "$model_path"
        --host           "$HOST"
        --port           "$PORT"
        --ctx-size       "$CTX_SIZE"
        --n-gpu-layers   "$N_GPU_LAYERS"
        --threads        "$N_THREADS"
        --parallel       "$N_PARALLEL"
        --batch-size     "$BATCH_SIZE"
        --temp           "$TEMPERATURE"
        --repeat-penalty "$REPEAT_PENALTY"
        --top-k          "$TOP_K"
        --top-p          "$TOP_P"
        --min-p          "$MIN_P"
        --cache-type-k   "$CACHE_TYPE_K"
        --cache-type-v   "$CACHE_TYPE_V"
        --defrag-thold   "$DEFRAG_THOLD"
        --metrics
    )
    [[ "${ENABLE_JINJA,,}" == "true" ]]          && cmd_args+=(--jinja)
    [[ "${DISABLE_FLASH_ATTN,,}" == "true" ]]    && cmd_args+=(--no-flash-attn)

    # 執行
    exec "$llama_server" "${cmd_args[@]}"
}

# ─── 主程式 ───────────────────────────────────────────────────
main() {
    clear
    echo
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  GPT-OSS 20B 模型服務啟動工具${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo

    # 偵測 GPU
    local gpu_info
    gpu_info=$(detect_gpu)
    log_info "GPU 偵測: ${gpu_info}"

    # 尋找 llama-server
    local llama_server
    if ! llama_server=$(find_llama_server); then
        log_error "找不到 llama-server!"
        show_install_guide

        read -rp "請手動輸入 llama-server 路徑 (或按 Enter 結束): " MANUAL_PATH
        if [[ -z "$MANUAL_PATH" ]]; then
            exit 1
        fi
        if [[ ! -x "$MANUAL_PATH" ]]; then
            log_error "路徑不存在或無執行權限: ${MANUAL_PATH}"
            exit 1
        fi
        llama_server="$MANUAL_PATH"
    fi

    log_info "llama-server 路徑: ${llama_server}"
    local version
    version=$("$llama_server" --version 2>&1 | head -1 || echo "版本未知")
    log_info "llama.cpp 版本: ${version}"

    # 命令列模式: ./serve.sh /path/to/model.gguf [port]
    if [[ $# -ge 1 ]]; then
        SELECTED_MODEL="$1"
        [[ $# -ge 2 ]] && PORT="$2"
        log_info "命令列模式: $(basename "$SELECTED_MODEL")"
    else
        select_model
        configure_params
    fi

    if [[ ! -f "$SELECTED_MODEL" ]]; then
        log_error "模型檔案不存在: ${SELECTED_MODEL}"
        exit 1
    fi

    start_server "$llama_server" "$SELECTED_MODEL"
}

# 錯誤處理
trap 'echo; log_error "服務異常退出 (exit code: $?)"; echo; echo "常見問題排查:"; echo "  - 記憶體不足: 降低 --ctx-size 或 --n-gpu-layers"; echo "  - 埠號衝突:   更換 --port 設定"; echo "  - 模型損壞:   重新執行 download.sh"; exit 1' ERR

main "$@"

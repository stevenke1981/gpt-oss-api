#!/usr/bin/env bash
# ============================================================
# GPT-OSS 20B 模型管理腳本 (Linux/macOS)
# 用途: 列出、查看資訊、刪除已下載的 GGUF 模型
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="${ROOT_DIR}/models"

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
log_error()   { echo -e "${RED}[錯誤]${NC} $*"; }

mkdir -p "$MODELS_DIR"

# ─── 取得所有模型清單 ─────────────────────────────────────────
get_model_list() {
    mapfile -t MODEL_FILES < <(find "$MODELS_DIR" -maxdepth 1 -name "*.gguf" -type f | sort)
}

# ─── 顯示模型選單 ─────────────────────────────────────────────
print_model_menu() {
    get_model_list
    if [[ ${#MODEL_FILES[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}[提示]${NC} 尚未下載任何模型，請先執行 download.sh"
        return 1
    fi
    local i=1
    for f in "${MODEL_FILES[@]}"; do
        local size
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        printf "  ${CYAN}[%d]${NC} %-55s ${DIM}(%s)${NC}\n" "$i" "$(basename "$f")" "$size"
        ((i++))
    done
    return 0
}

# ─── 菜單: 列出所有模型 ───────────────────────────────────────
cmd_list() {
    clear
    echo
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  已下載的模型清單${NC}"
    echo -e "  目錄: ${CYAN}${MODELS_DIR}${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo

    get_model_list
    if [[ ${#MODEL_FILES[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}[提示]${NC} 尚未下載任何模型，請先執行 download.sh"
        echo
        read -rp "按 Enter 返回主選單..."
        return
    fi

    local total_bytes=0
    local i=1
    for f in "${MODEL_FILES[@]}"; do
        local size_human size_bytes mtime
        size_human=$(du -sh "$f" | cut -f1)
        size_bytes=$(du -b "$f" | cut -f1)
        mtime=$(stat -c "%y" "$f" 2>/dev/null || stat -f "%Sm" "$f" 2>/dev/null || echo "未知")
        mtime="${mtime:0:19}"  # 截取日期時間部分
        total_bytes=$((total_bytes + size_bytes))

        printf "\n  ${CYAN}[%d]${NC} ${BOLD}%s${NC}\n" "$i" "$(basename "$f")"
        printf "      大小: ${size_human}\n"
        printf "      路徑: ${DIM}%s${NC}\n" "$f"
        printf "      修改: ${DIM}%s${NC}\n" "$mtime"
        ((i++))
    done

    local total_gb
    total_gb=$(echo "scale=1; $total_bytes/1073741824" | bc 2>/dev/null || echo "?")
    echo
    echo -e "${BOLD}------------------------------------------------------------${NC}"
    printf "  共 ${CYAN}%d${NC} 個模型，總計 ${YELLOW}%s GB${NC}\n" "${#MODEL_FILES[@]}" "$total_gb"
    echo -e "${BOLD}------------------------------------------------------------${NC}"
    echo
    read -rp "按 Enter 返回主選單..."
}

# ─── 菜單: 模型詳細資訊 ───────────────────────────────────────
cmd_info() {
    clear
    echo
    echo -e "${BOLD}=== 查看模型詳細資訊 ===${NC}"
    echo

    print_model_menu || { read -rp "按 Enter 返回..."; return; }
    echo
    read -rp "請輸入模型編號 (0=取消): " NUM
    [[ "$NUM" == "0" || -z "$NUM" ]] && return

    if [[ "$NUM" -lt 1 || "$NUM" -gt "${#MODEL_FILES[@]}" ]]; then
        log_error "無效編號"; sleep 2; return
    fi

    local f="${MODEL_FILES[$((NUM-1))]}"
    local fname size_human size_bytes size_mb mtime
    fname="$(basename "$f")"
    size_human=$(du -sh "$f" | cut -f1)
    size_bytes=$(du -b "$f" | cut -f1)
    size_mb=$((size_bytes / 1048576))
    mtime=$(stat -c "%y" "$f" 2>/dev/null || stat -f "%Sm" "$f" 2>/dev/null || echo "未知")

    echo
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  模型資訊: ${CYAN}${fname}${NC}"
    echo -e "${BOLD}============================================================${NC}"
    printf "\n  %-12s %s\n" "檔名:" "$fname"
    printf "  %-12s %s MB (~%s)\n" "大小:" "$size_mb" "$size_human"
    printf "  %-12s %s\n" "完整路徑:" "$f"
    printf "  %-12s %s\n" "修改時間:" "${mtime:0:19}"

    echo
    echo -e "  ${BOLD}量化類型解析:${NC}"
    if [[ "$fname" == *"IQ4_NL"* ]]; then
        echo "    類型: IQ4_NL (4-bit Imatrix) — 創意/娛樂用途，Imatrix 效果最強"
    elif [[ "$fname" == *"Q5_1"* ]]; then
        echo "    類型: Q5_1 (5-bit) — 均衡一般用途，穩定性佳"
    elif [[ "$fname" == *"Q8_0"* ]]; then
        echo "    類型: Q8_0 (8-bit) — 最高品質，最大檔案"
    fi

    if [[ "$fname" == *"TRI"* ]]; then
        echo "    Matrix: TRI-Matrix (3個資料集平均，效果最穩定)"
    elif [[ "$fname" == *"-DI-"* ]]; then
        echo "    Matrix: DI-Matrix (2個資料集平均，平衡特性)"
    else
        echo "    Matrix: 標準 Imatrix (單資料集)"
    fi

    if [[ "$fname" == *"CODE"* ]]; then
        echo "    特化: 程式碼生成增強版"
    fi
    if [[ "$fname" == *"HRR"* ]]; then
        echo "    特化: HRR (高重複率減少優化)"
    fi

    echo
    echo -e "  ${BOLD}建議啟動參數:${NC}"
    echo "    --ctx-size   8192       (最大支援 131072)"
    echo "    --temp       0.8        (創意用 1.0-1.2，程式碼用 0.6)"
    echo "    --rep-penalty 1.1       (重要! 防止重複)"
    echo "    --top-k      40"
    echo "    --top-p      0.95"
    echo "    --min-p      0.05"
    echo

    # SHA256 校驗 (可選)
    read -rp "是否計算 SHA256 校驗碼? (y/N): " DO_SHA
    if [[ "${DO_SHA,,}" == "y" ]]; then
        log_info "計算中 (大檔案需要數秒)..."
        local sha
        sha=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$f" | cut -d' ' -f1)
        echo -e "  SHA256: ${DIM}${sha}${NC}"
    fi

    echo
    read -rp "按 Enter 返回主選單..."
}

# ─── 菜單: 刪除模型 ───────────────────────────────────────────
cmd_delete() {
    clear
    echo
    echo -e "${BOLD}=== 刪除模型 ===${NC}"
    echo

    print_model_menu || { read -rp "按 Enter 返回..."; return; }
    echo
    read -rp "請輸入要刪除的模型編號 (0=取消): " NUM
    [[ "$NUM" == "0" || -z "$NUM" ]] && return

    if [[ "$NUM" -lt 1 || "$NUM" -gt "${#MODEL_FILES[@]}" ]]; then
        log_error "無效編號"; sleep 2; return
    fi

    local f="${MODEL_FILES[$((NUM-1))]}"
    local size
    size=$(du -sh "$f" | cut -f1)

    echo
    log_warn "即將刪除: $(basename "$f")"
    log_warn "檔案大小: ${size}  (此操作無法復原)"
    echo
    read -rp "確認刪除? 請輸入 YES 確認: " CONFIRM
    if [[ "$CONFIRM" != "YES" ]]; then
        log_info "已取消刪除"
        sleep 1
        return
    fi

    rm -f "$f"
    log_success "已刪除: $(basename "$f")"
    sleep 2
}

# ─── 菜單: 磁碟空間 ───────────────────────────────────────────
cmd_disk() {
    clear
    echo
    echo -e "${BOLD}=== 磁碟空間資訊 ===${NC}"
    echo

    local disk_path
    disk_path=$(df "$MODELS_DIR" | tail -1)
    local available used total
    available=$(df -h "$MODELS_DIR" | tail -1 | awk '{print $4}')
    used=$(df -h "$MODELS_DIR" | tail -1 | awk '{print $3}')
    total=$(df -h "$MODELS_DIR" | tail -1 | awk '{print $2}')
    local mount
    mount=$(df "$MODELS_DIR" | tail -1 | awk '{print $6}')

    printf "  %-14s %s\n" "掛載點:" "$mount"
    printf "  %-14s %s\n" "總容量:" "$total"
    printf "  %-14s %s\n" "已使用:" "$used"
    printf "  %-14s ${GREEN}%s${NC}\n" "可用空間:" "$available"

    echo
    echo -e "  ${BOLD}各量化類型所需空間:${NC}"
    printf "    %-10s 約 12 GB\n" "IQ4_NL"
    printf "    %-10s 約 16 GB\n" "Q5_1"
    printf "    %-10s 約 22 GB\n" "Q8_0"

    echo
    echo -e "  ${BOLD}models 目錄已用空間:${NC}"
    get_model_list
    if [[ ${#MODEL_FILES[@]} -gt 0 ]]; then
        local total_size
        total_size=$(du -sh "$MODELS_DIR"/*.gguf 2>/dev/null | tail -1 | cut -f1 || echo "0")
        local all_size
        all_size=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)
        echo "    模型合計: ${all_size}"
        echo "    模型數量: ${#MODEL_FILES[@]} 個"
    else
        echo "    (無模型)"
    fi

    echo
    read -rp "按 Enter 返回主選單..."
}

# ─── 菜單: 清理臨時檔案 ───────────────────────────────────────
cmd_clean() {
    clear
    echo
    echo -e "${BOLD}=== 清理不完整的下載檔案 ===${NC}"
    echo

    local found=0
    local tmp_files=()
    while IFS= read -r -d '' f; do
        tmp_files+=("$f")
        ((found++))
    done < <(find "$MODELS_DIR" \( -name "*.tmp" -o -name "*.part" -o -name "*.download" -o -name "*.incomplete" \) -print0 2>/dev/null)

    if [[ $found -eq 0 ]]; then
        log_info "未找到需要清理的臨時檔案"
    else
        echo -e "  找到 ${YELLOW}${found}${NC} 個臨時檔案:"
        for f in "${tmp_files[@]}"; do
            printf "    %s  (%s)\n" "$(basename "$f")" "$(du -sh "$f" | cut -f1)"
        done
        echo
        read -rp "是否刪除以上臨時檔案? (y/N): " CLEAN
        if [[ "${CLEAN,,}" == "y" ]]; then
            for f in "${tmp_files[@]}"; do
                rm -f "$f"
                log_success "已刪除: $(basename "$f")"
            done
        else
            log_info "已取消清理"
        fi
    fi

    echo
    read -rp "按 Enter 返回主選單..."
}

# ─── 主選單 ───────────────────────────────────────────────────
main_menu() {
    while true; do
        clear
        echo
        echo -e "${BOLD}============================================================${NC}"
        echo -e "${BOLD}  GPT-OSS 20B 模型管理工具${NC}"
        echo -e "  模型目錄: ${CYAN}${MODELS_DIR}${NC}"
        echo -e "${BOLD}============================================================${NC}"
        echo

        get_model_list
        local count="${#MODEL_FILES[@]}"
        if [[ $count -gt 0 ]]; then
            local total_size
            total_size=$(du -sh "${MODELS_DIR}"/*.gguf 2>/dev/null | awk '{sum+=$1} END{print sum}' || echo "?")
            echo -e "  已下載模型: ${GREEN}${count}${NC} 個"
        else
            echo -e "  已下載模型: ${YELLOW}無${NC}"
        fi
        echo
        echo "  [1] 列出所有已下載模型"
        echo "  [2] 查看模型詳細資訊"
        echo "  [3] 刪除模型"
        echo "  [4] 磁碟空間資訊"
        echo "  [5] 清理不完整的下載檔案"
        echo "  [0] 結束"
        echo
        read -rp "請選擇操作 (0-5): " CHOICE

        case "$CHOICE" in
            1) cmd_list ;;
            2) cmd_info ;;
            3) cmd_delete ;;
            4) cmd_disk ;;
            5) cmd_clean ;;
            0) echo; exit 0 ;;
            *) log_error "無效選項"; sleep 1 ;;
        esac
    done
}

main_menu

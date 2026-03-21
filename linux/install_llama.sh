#!/usr/bin/env bash
# ============================================================
# llama.cpp Build & Install Script (Linux)
# Method: Build from source with auto GPU detection
# Usage : ./install_llama.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${ROOT_DIR}/llama.cpp"
REPO_URL="https://github.com/ggerganov/llama.cpp.git"
JOBS=$(nproc)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}>>> $*${NC}"; }

# ─── detect GPU ──────────────────────────────────────────────
detect_backend() {
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
        local gpu
        gpu=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        echo "cuda"; return
    fi
    if command -v rocm-smi &>/dev/null 2>&1 || ls /dev/kfd &>/dev/null 2>&1; then
        echo "rocm"; return
    fi
    if [[ "$(uname)" == "Darwin" ]] && system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Apple M"; then
        echo "metal"; return
    fi
    echo "cpu"
}

# ─── check dependencies ───────────────────────────────────────
check_deps() {
    step "Checking build dependencies"

    local missing=()
    for pkg in git cmake g++ make; do
        if ! command -v "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing packages: ${missing[*]}"
        info "Installing missing packages..."

        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y git cmake g++ make libcurl4-openssl-dev
        elif command -v yum &>/dev/null; then
            sudo yum install -y git cmake gcc-c++ make libcurl-devel
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm git cmake gcc make curl
        else
            die "Cannot auto-install. Please install manually: ${missing[*]}"
        fi
    fi

    ok "All build dependencies present"
}

# ─── clone or update repo ─────────────────────────────────────
get_source() {
    step "Getting llama.cpp source"

    if [[ -d "$BUILD_DIR/.git" ]]; then
        info "Existing repo found at $BUILD_DIR — pulling latest..."
        git -C "$BUILD_DIR" pull --ff-only
    else
        info "Cloning llama.cpp into $BUILD_DIR ..."
        git clone --depth=1 "$REPO_URL" "$BUILD_DIR"
    fi

    local commit
    commit=$(git -C "$BUILD_DIR" log -1 --format="%h %s")
    ok "Source ready: $commit"
}

# ─── build ───────────────────────────────────────────────────
build_llama() {
    local backend="$1"
    step "Building llama.cpp (backend: $backend, jobs: $JOBS)"

    local cmake_args=(
        -DCMAKE_BUILD_TYPE=Release
        -DLLAMA_BUILD_TESTS=OFF
        -DLLAMA_BUILD_EXAMPLES=ON
    )

    case "$backend" in
        cuda)
            info "CUDA build — checking nvcc..."
            command -v nvcc &>/dev/null || die "nvcc not found. Install CUDA toolkit: sudo apt install nvidia-cuda-toolkit"
            local cuda_ver
            cuda_ver=$(nvcc --version | grep -oP 'release \K[0-9.]+')
            info "CUDA version: $cuda_ver"
            cmake_args+=(-DGGML_CUDA=ON)
            ;;
        rocm)
            info "ROCm / HIP build"
            cmake_args+=(-DGGML_HIPBLAS=ON)
            ;;
        metal)
            info "Apple Metal build"
            cmake_args+=(-DGGML_METAL=ON)
            ;;
        cpu)
            info "CPU-only build (AVX2 auto-detected)"
            ;;
    esac

    cmake -B "${BUILD_DIR}/build" -S "$BUILD_DIR" "${cmake_args[@]}"
    cmake --build "${BUILD_DIR}/build" --config Release -j"$JOBS"

    ok "Build complete"
}

# ─── install ─────────────────────────────────────────────────
install_llama() {
    step "Installing llama-server"

    local server_bin="${BUILD_DIR}/build/bin/llama-server"
    [[ -f "$server_bin" ]] || die "llama-server binary not found at $server_bin"

    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"
    cp "$server_bin" "$install_dir/llama-server"
    chmod +x "$install_dir/llama-server"

    # also copy llama-cli if present
    local cli_bin="${BUILD_DIR}/build/bin/llama-cli"
    if [[ -f "$cli_bin" ]]; then
        cp "$cli_bin" "$install_dir/llama-cli"
        chmod +x "$install_dir/llama-cli"
    fi

    ok "Installed to $install_dir"

    # check PATH
    if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
        warn "$install_dir is not in PATH"
        info "Adding to PATH for this session..."
        export PATH="${install_dir}:${PATH}"

        info "To make it permanent, add to ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "    source ~/.bashrc"
        echo ""
    fi
}

# ─── verify ──────────────────────────────────────────────────
verify() {
    step "Verifying installation"

    if command -v llama-server &>/dev/null; then
        local ver
        ver=$(llama-server --version 2>&1 | head -1)
        ok "llama-server found: $ver"
        ok "Path: $(which llama-server)"
    else
        warn "llama-server not in PATH yet — reload your shell or run:"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# ─── summary ─────────────────────────────────────────────────
show_summary() {
    local backend="$1"
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  Build Complete${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo "  Backend  : $backend"
    echo "  Binary   : $HOME/.local/bin/llama-server"
    echo "  Source   : $BUILD_DIR"
    echo ""
    echo "  Next steps:"
    echo "    ./download.sh    # download a GGUF model"
    echo "    ./serve.sh       # start the API server"
    echo -e "${BOLD}============================================================${NC}"
    echo ""
}

# ─── main ────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  llama.cpp Build Installer${NC}"
    echo -e "  Target: ${CYAN}${BUILD_DIR}${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo ""

    local backend
    backend=$(detect_backend)
    info "Detected backend: $backend"

    # ask for confirmation
    echo ""
    case "$backend" in
        cuda)  echo -e "  Will build with ${GREEN}NVIDIA CUDA GPU${NC} acceleration" ;;
        rocm)  echo -e "  Will build with ${GREEN}AMD ROCm GPU${NC} acceleration" ;;
        metal) echo -e "  Will build with ${GREEN}Apple Metal${NC} acceleration" ;;
        cpu)   echo -e "  Will build ${YELLOW}CPU-only${NC} (no GPU detected)" ;;
    esac
    echo ""

    # allow manual override
    read -rp "Override backend? [cuda/rocm/cpu/Enter to keep '$backend']: " override
    [[ -n "$override" ]] && backend="$override"

    read -rp "Start build? (Y/n): " go
    [[ "${go,,}" == "n" ]] && exit 0

    check_deps
    get_source
    build_llama "$backend"
    install_llama
    verify
    show_summary "$backend"
}

main "$@"

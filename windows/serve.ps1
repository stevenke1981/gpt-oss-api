# GPT-OSS 20B Model Server (Windows PowerShell)
# Usage  : .\serve.ps1
# Quick  : .\serve.ps1 -Model ".\models\model.gguf" -Port 8080

param(
    [string]$Model     = "",
    [string]$BindHost  = "",
    [int]$Port         = 0
)

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$ModelsDir  = Join-Path $RootDir "models"
$ConfigFile = Join-Path $RootDir "config\settings.ini"

function info  ($m) { Write-Host "[INFO]    $m" -ForegroundColor Cyan }
function ok    ($m) { Write-Host "[OK]      $m" -ForegroundColor Green }
function warn  ($m) { Write-Host "[WARN]    $m" -ForegroundColor Yellow }
function err   ($m) { Write-Host "[ERROR]   $m" -ForegroundColor Red }

# --- load config ---
$cfg = @{
    HOST           = "127.0.0.1"
    PORT           = "8080"
    N_GPU_LAYERS   = "0"
    N_THREADS      = ([System.Environment]::ProcessorCount).ToString()
    CTX_SIZE       = "8192"
    N_PARALLEL     = "4"
    BATCH_SIZE     = "512"
    TEMPERATURE    = "0.8"
    REPEAT_PENALTY = "1.1"
    TOP_K          = "40"
    TOP_P          = "0.95"
    MIN_P          = "0.05"
}

if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | Where-Object { $_ -notmatch '^\s*[#\[]' -and $_ -match '=' } | ForEach-Object {
        $parts = $_ -split '=', 2
        $k = $parts[0].Trim(); $v = $parts[1].Trim()
        if ($cfg.ContainsKey($k)) { $cfg[$k] = $v }
    }
}
if ($BindHost -ne "") { $cfg["HOST"] = $BindHost }
if ($Port -ne 0)      { $cfg["PORT"] = $Port.ToString() }

# --- find llama-server ---
function Find-LlamaServer {
    $paths = @(
        "llama-server.exe",
        (Join-Path $RootDir "llama.cpp\llama-server.exe"),
        (Join-Path $RootDir "llama.cpp\build\bin\Release\llama-server.exe"),
        (Join-Path $RootDir "llama.cpp\build\bin\llama-server.exe"),
        "C:\llama.cpp\llama-server.exe",
        "C:\llama.cpp\build\bin\Release\llama-server.exe",
        (Join-Path $env:LOCALAPPDATA "llama.cpp\llama-server.exe")
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    $cmd = Get-Command "llama-server.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Show-InstallGuide {
    Write-Host ""
    Write-Host "  llama-server.exe not found. Install options:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Pre-built release (recommended):" -ForegroundColor Cyan
    Write-Host "      https://github.com/ggerganov/llama.cpp/releases"
    Write-Host "      -> llama-b????-bin-win-cuda12-x64.zip  (NVIDIA GPU)"
    Write-Host "      -> llama-b????-bin-win-noavx-x64.zip   (CPU only)"
    Write-Host "      Extract to: $RootDir\llama.cpp\"
    Write-Host ""
    Write-Host "  [2] Build from source (requires CMake + Visual Studio):" -ForegroundColor Cyan
    Write-Host "      git clone https://github.com/ggerganov/llama.cpp"
    Write-Host "      cd llama.cpp"
    Write-Host "      cmake -B build -DGGML_CUDA=ON"
    Write-Host "      cmake --build build --config Release"
    Write-Host ""
    Write-Host "  [3] Python package:" -ForegroundColor Cyan
    Write-Host "      pip install llama-cpp-python[server]"
    Write-Host "      python -m llama_cpp.server --model <path>"
    Write-Host ""
}

# --- detect GPU ---
function Get-GpuInfo {
    try {
        $gpu = (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "Microsoft|Basic" } |
                Select-Object -First 1).Name
        if ($gpu) { return $gpu }
    } catch {}
    return "No discrete GPU detected (CPU mode)"
}

# --- select model ---
function Select-Model {
    $files = @(Get-ChildItem -Path $ModelsDir -Filter "*.gguf" -File | Sort-Object Name)
    if ($files.Count -eq 0) {
        err "No .gguf files in models directory."
        info "Run .\download.ps1 first."
        Read-Host "Press Enter to exit"; exit 1
    }

    Write-Host ""; Write-Host "=== Select Model ===" -ForegroundColor Cyan; Write-Host ""
    for ($i = 0; $i -lt $files.Count; $i++) {
        $mb = [math]::Round($files[$i].Length / 1MB, 1)
        Write-Host ("  [{0}] {1,-55} ({2} MB)" -f ($i+1), $files[$i].Name, $mb)
    }
    Write-Host ""
    $n = Read-Host "Select number"
    $idx = [int]$n - 1
    if ($idx -lt 0 -or $idx -ge $files.Count) { err "Invalid number"; exit 1 }
    return $files[$idx].FullName
}

# --- configure params ---
function Set-Params {
    Write-Host ""; Write-Host "=== Server Parameters (Enter = keep default) ===" -ForegroundColor Cyan; Write-Host ""

    $v = Read-Host ("  Host          [{0}]" -f $cfg["HOST"])
    if ($v) { $cfg["HOST"] = $v }

    $v = Read-Host ("  Port          [{0}]" -f $cfg["PORT"])
    if ($v) { $cfg["PORT"] = $v }

    $v = Read-Host ("  Context size  [{0}] (8192-131072)" -f $cfg["CTX_SIZE"])
    if ($v) { $cfg["CTX_SIZE"] = $v }

    $v = Read-Host ("  GPU layers    [{0}] (0=CPU only, -1=all GPU)" -f $cfg["N_GPU_LAYERS"])
    if ($v) { $cfg["N_GPU_LAYERS"] = $v }

    $v = Read-Host ("  CPU threads   [{0}]" -f $cfg["N_THREADS"])
    if ($v) { $cfg["N_THREADS"] = $v }

    $v = Read-Host ("  Parallel slots[{0}]" -f $cfg["N_PARALLEL"])
    if ($v) { $cfg["N_PARALLEL"] = $v }
}

# --- start server ---
function Start-Server ($bin, $modelPath) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Launch Summary" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ("  Model   : {0}" -f (Split-Path -Leaf $modelPath))
    Write-Host ("  API URL : http://{0}:{1}" -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Green
    Write-Host ("  Context : {0} tokens" -f $cfg["CTX_SIZE"])
    Write-Host ("  GPU lyr : {0}" -f $cfg["N_GPU_LAYERS"])
    Write-Host ("  Threads : {0}" -f $cfg["N_THREADS"])
    Write-Host ("  Parallel: {0}" -f $cfg["N_PARALLEL"])
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  Chat  : http://{0}:{1}/v1/chat/completions" -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Cyan
    Write-Host ("  Health: http://{0}:{1}/health"              -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Cyan
    Write-Host ("  Web UI: http://{0}:{1}"                     -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $c = Read-Host "Start server? (Y/n)"
    if ($c -eq "n") { exit 0 }

    Write-Host ""; info "Starting llama-server...  Press Ctrl+C to stop"; Write-Host ""

    & $bin `
        --model         $modelPath `
        --host          $cfg["HOST"] `
        --port          $cfg["PORT"] `
        --ctx-size      $cfg["CTX_SIZE"] `
        --n-gpu-layers  $cfg["N_GPU_LAYERS"] `
        --threads       $cfg["N_THREADS"] `
        --parallel      $cfg["N_PARALLEL"] `
        --batch-size    $cfg["BATCH_SIZE"] `
        --temp          $cfg["TEMPERATURE"] `
        --repeat-penalty $cfg["REPEAT_PENALTY"] `
        --top-k         $cfg["TOP_K"] `
        --top-p         $cfg["TOP_P"] `
        --min-p         $cfg["MIN_P"] `
        --metrics

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        err "llama-server exited with code $LASTEXITCODE"
        Write-Host "  Troubleshooting:" -ForegroundColor Yellow
        Write-Host "    - Out of memory  : lower --ctx-size or --n-gpu-layers"
        Write-Host "    - Port in use    : change PORT in config\settings.ini"
        Write-Host "    - Corrupt model  : re-run .\download.ps1"
        Write-Host "    - GPU error      : set N_GPU_LAYERS=0 in settings.ini"
        Read-Host "Press Enter to exit"
    }
}

# --- main ---
Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  GPT-OSS 20B Model Server" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

info "GPU: $(Get-GpuInfo)"

$bin = Find-LlamaServer
if (-not $bin) {
    err "llama-server.exe not found!"
    Show-InstallGuide
    $manual = Read-Host "Enter full path to llama-server.exe (or Enter to exit)"
    if ([string]::IsNullOrWhiteSpace($manual) -or -not (Test-Path $manual)) {
        if ($manual) { err "Path not found: $manual" }
        exit 1
    }
    $bin = $manual
}
info "llama-server: $bin"

if ($Model -ne "" -and (Test-Path $Model)) {
    $selectedModel = (Resolve-Path $Model).Path
    info "CLI mode: $(Split-Path -Leaf $selectedModel)"
} else {
    $selectedModel = Select-Model
    Set-Params
}

Start-Server $bin $selectedModel

# ============================================================
# GPT-OSS 20B 模型服務腳本 (Windows PowerShell)
# 用途: 使用 llama.cpp 啟動 OpenAI 相容 API 服務
# 執行: .\serve.ps1
# 快速: .\serve.ps1 -Model ".\models\model.gguf" -Port 8080
# ============================================================

param(
    [string]$Model  = "",
    [string]$Host   = "",
    [int]$Port      = 0
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir     = Split-Path -Parent $ScriptDir
$ModelsDir   = Join-Path $RootDir "models"
$ConfigFile  = Join-Path $RootDir "config\settings.ini"

function Write-Info    ($msg) { Write-Host "[資訊] $msg" -ForegroundColor Cyan }
function Write-Success ($msg) { Write-Host "[成功] $msg" -ForegroundColor Green }
function Write-Warn    ($msg) { Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Err     ($msg) { Write-Host "[錯誤] $msg" -ForegroundColor Red }

# ─── 載入設定檔 ───────────────────────────────────────────────
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
        $key = $parts[0].Trim()
        $val = $parts[1].Trim()
        if ($cfg.ContainsKey($key)) { $cfg[$key] = $val }
    }
}

# 命令列參數覆蓋設定檔
if ($Host -ne "")  { $cfg["HOST"] = $Host }
if ($Port -ne 0)   { $cfg["PORT"] = $Port.ToString() }

# ─── 尋找 llama-server ────────────────────────────────────────
function Find-LlamaServer {
    $candidates = @(
        "llama-server.exe",
        (Join-Path $RootDir "llama.cpp\llama-server.exe"),
        (Join-Path $RootDir "llama.cpp\build\bin\Release\llama-server.exe"),
        (Join-Path $RootDir "llama.cpp\build\bin\llama-server.exe"),
        "C:\llama.cpp\llama-server.exe",
        "C:\llama.cpp\build\bin\Release\llama-server.exe",
        (Join-Path $env:LOCALAPPDATA "llama.cpp\llama-server.exe")
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    $fromPath = Get-Command "llama-server.exe" -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    return $null
}

function Show-InstallGuide {
    Write-Host ""
    Write-Host "找不到 llama-server.exe，請選擇安裝方式:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [方法 1] 下載預編譯版本 (推薦):" -ForegroundColor Cyan
    Write-Host "    1. 前往 https://github.com/ggerganov/llama.cpp/releases"
    Write-Host "    2. 下載 llama-b????-bin-win-cuda12-x64.zip  (NVIDIA GPU)"
    Write-Host "       或   llama-b????-bin-win-noavx-x64.zip   (純 CPU)"
    Write-Host "    3. 解壓至 $RootDir\llama.cpp\"
    Write-Host ""
    Write-Host "  [方法 2] 自行編譯 (需要 CMake + Visual Studio):" -ForegroundColor Cyan
    Write-Host "    git clone https://github.com/ggerganov/llama.cpp"
    Write-Host "    cd llama.cpp"
    Write-Host "    cmake -B build -DGGML_CUDA=ON"
    Write-Host "    cmake --build build --config Release"
    Write-Host ""
    Write-Host "  [方法 3] pip 安裝 Python 版本:" -ForegroundColor Cyan
    Write-Host "    pip install llama-cpp-python[server]"
    Write-Host "    python -m llama_cpp.server --model <model_path>"
    Write-Host ""
}

# ─── 偵測 GPU ─────────────────────────────────────────────────
function Get-GpuInfo {
    try {
        $gpu = (Get-WmiObject -Class Win32_VideoController -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "Microsoft|Basic" } |
                Select-Object -First 1).Name
        if ($gpu) { return $gpu }
    } catch {}
    return "未偵測到 GPU (純 CPU 模式)"
}

# ─── 選擇模型 ─────────────────────────────────────────────────
function Select-Model {
    $files = @(Get-ChildItem -Path $ModelsDir -Filter "*.gguf" -File | Sort-Object Name)

    if ($files.Count -eq 0) {
        Write-Err "models 目錄中沒有 .gguf 檔案"
        Write-Info "請先執行 .\download.ps1 下載模型"
        Read-Host "按 Enter 結束"
        exit 1
    }

    Write-Host ""
    Write-Host "=== 選擇要啟動的模型 ===" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $files.Count; $i++) {
        $sizeMB = [math]::Round($files[$i].Length / 1MB, 1)
        Write-Host ("  [{0}] {1,-55} ({2} MB)" -f ($i+1), $files[$i].Name, $sizeMB)
    }
    Write-Host ""
    $num = Read-Host "請選擇模型編號"
    $idx = [int]$num - 1
    if ($idx -lt 0 -or $idx -ge $files.Count) {
        Write-Err "無效的模型編號"
        exit 1
    }
    return $files[$idx].FullName
}

# ─── 互動式參數設定 ───────────────────────────────────────────
function Set-Params {
    Write-Host ""
    Write-Host "=== 啟動參數設定 (按 Enter 使用預設值) ===" -ForegroundColor Cyan
    Write-Host ""

    $v = Read-Host ("  服務位址        [{0}]" -f $cfg["HOST"])
    if ($v) { $cfg["HOST"] = $v }

    $v = Read-Host ("  服務埠號        [{0}]" -f $cfg["PORT"])
    if ($v) { $cfg["PORT"] = $v }

    $v = Read-Host ("  上下文長度      [{0}] (8192-131072)" -f $cfg["CTX_SIZE"])
    if ($v) { $cfg["CTX_SIZE"] = $v }

    $v = Read-Host ("  GPU 層數        [{0}] (0=純CPU, -1=全GPU)" -f $cfg["N_GPU_LAYERS"])
    if ($v) { $cfg["N_GPU_LAYERS"] = $v }

    $v = Read-Host ("  CPU 執行緒數    [{0}]" -f $cfg["N_THREADS"])
    if ($v) { $cfg["N_THREADS"] = $v }

    $v = Read-Host ("  平行處理槽數    [{0}]" -f $cfg["N_PARALLEL"])
    if ($v) { $cfg["N_PARALLEL"] = $v }
}

# ─── 啟動服務 ─────────────────────────────────────────────────
function Start-LlamaServer ($llamaServer, $modelPath) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  啟動設定摘要" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ("  {0,-14} {1}" -f "模型:", (Split-Path -Leaf $modelPath))
    Write-Host ("  {0,-14} " -f "API 位址:") -NoNewline
    Write-Host ("http://{0}:{1}" -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Green
    Write-Host ("  {0,-14} {1} tokens" -f "上下文:", $cfg["CTX_SIZE"])
    Write-Host ("  {0,-14} {1}" -f "GPU 層數:", $cfg["N_GPU_LAYERS"])
    Write-Host ("  {0,-14} {1}" -f "執行緒:", $cfg["N_THREADS"])
    Write-Host ("  {0,-14} {1}" -f "平行槽數:", $cfg["N_PARALLEL"])
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  API 端點:" -ForegroundColor White
    Write-Host ("    聊天:   http://{0}:{1}/v1/chat/completions" -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Cyan
    Write-Host ("    補全:   http://{0}:{1}/v1/completions"      -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Cyan
    Write-Host ("    健康:   http://{0}:{1}/health"              -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Cyan
    Write-Host ("    Web UI: http://{0}:{1}"                     -f $cfg["HOST"], $cfg["PORT"]) -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $confirm = Read-Host "確認啟動服務? (Y/n)"
    if ($confirm.ToLower() -eq "n") { exit 0 }

    Write-Host ""
    Write-Info "正在啟動 llama-server..."
    Write-Host "  按 Ctrl+C 停止服務" -ForegroundColor Yellow
    Write-Host ""

    $argList = @(
        "--model",          $modelPath,
        "--host",           $cfg["HOST"],
        "--port",           $cfg["PORT"],
        "--ctx-size",       $cfg["CTX_SIZE"],
        "--n-gpu-layers",   $cfg["N_GPU_LAYERS"],
        "--threads",        $cfg["N_THREADS"],
        "--parallel",       $cfg["N_PARALLEL"],
        "--batch-size",     $cfg["BATCH_SIZE"],
        "--temp",           $cfg["TEMPERATURE"],
        "--repeat-penalty", $cfg["REPEAT_PENALTY"],
        "--top-k",          $cfg["TOP_K"],
        "--top-p",          $cfg["TOP_P"],
        "--min-p",          $cfg["MIN_P"],
        "--flash-attn",
        "--metrics",
        "--log-format",     "text"
    )

    & $llamaServer @argList

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Err "llama-server 異常退出，錯誤碼: $LASTEXITCODE"
        Write-Host ""
        Write-Host "常見問題排查:" -ForegroundColor Yellow
        Write-Host "  - 記憶體不足:   降低 --ctx-size 或 --n-gpu-layers"
        Write-Host "  - 埠號衝突:     更換 PORT 設定"
        Write-Host "  - 模型檔案損壞: 重新執行 .\download.ps1"
        Write-Host "  - GPU 驅動問題: 設定 N_GPU_LAYERS=0 改用 CPU"
        Read-Host "按 Enter 結束"
    }
}

# ─── 主程式 ───────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  GPT-OSS 20B 模型服務啟動工具" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "GPU 偵測: $(Get-GpuInfo)"

$llamaServer = Find-LlamaServer
if (-not $llamaServer) {
    Write-Err "找不到 llama-server.exe!"
    Show-InstallGuide
    $manual = Read-Host "請手動輸入 llama-server.exe 路徑 (或按 Enter 結束)"
    if ([string]::IsNullOrWhiteSpace($manual)) { exit 1 }
    if (-not (Test-Path $manual)) { Write-Err "路徑不存在: $manual"; exit 1 }
    $llamaServer = $manual
}

Write-Info "llama-server 路徑: $llamaServer"

# 命令列快速模式: .\serve.ps1 -Model "model.gguf" -Port 8080
if ($Model -ne "" -and (Test-Path $Model)) {
    $selectedModel = (Resolve-Path $Model).Path
    Write-Info "命令列模式: $(Split-Path -Leaf $selectedModel)"
} else {
    $selectedModel = Select-Model
    Set-Params
}

Start-LlamaServer $llamaServer $selectedModel

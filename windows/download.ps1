# ============================================================
# GPT-OSS 20B 模型下載腳本 (Windows PowerShell)
# 用途: 從 HuggingFace 下載指定的 GGUF 模型檔案
# 執行: .\download.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$ModelsDir  = Join-Path $RootDir "models"
$HF_REPO    = "DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf"
$HF_BASE    = "https://huggingface.co/$HF_REPO/resolve/main"

# ─── 工具函數 ─────────────────────────────────────────────────
function Write-Info    ($msg) { Write-Host "[資訊] $msg" -ForegroundColor Cyan }
function Write-Success ($msg) { Write-Host "[成功] $msg" -ForegroundColor Green }
function Write-Warn    ($msg) { Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Err     ($msg) { Write-Host "[錯誤] $msg" -ForegroundColor Red }

function Show-Header {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  GPT-OSS 20B 模型下載工具" -ForegroundColor White
    Write-Host "  Repository: $HF_REPO" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ─── 偵測下載工具 ─────────────────────────────────────────────
function Get-Downloader {
    if (Get-Command "huggingface-cli" -ErrorAction SilentlyContinue) { return "hf-cli" }
    if (Get-Command "python" -ErrorAction SilentlyContinue) {
        $ok = python -c "import huggingface_hub" 2>$null
        if ($LASTEXITCODE -eq 0) { return "python" }
    }
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) { return "curl" }
    if (Get-Command "wget" -ErrorAction SilentlyContinue) { return "wget" }
    return $null
}

# ─── 模型資料 ─────────────────────────────────────────────────
$Models = @{
    "IQ4_NL" = @(
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-Uncensored2-IQ4_NL.gguf";           Desc = "標準" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEOPlus-Uncensored-IQ4_NL.gguf";        Desc = "增強版" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-CODEPlus16-Uncensored-IQ4_NL.gguf"; Desc = "程式碼加強" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-HRRPlus-Uncensored-IQ4_NL.gguf";   Desc = "DI-Matrix" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-CODEPlus-Uncensored-IQ4_NL.gguf";  Desc = "DI-Matrix 程式碼" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-CODE2-Plus-Uncensored-IQ4_NL.gguf"; Desc = "程式碼 v2" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-IQ4_NL.gguf"; Desc = "TRI-Matrix" }
    )
    "Q5_1" = @(
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-Uncensored2-Q5_1.gguf";             Desc = "標準" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEOPlus-Uncensored-Q5_1.gguf";          Desc = "增強版" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-CODEPlus-Uncensored-Q5_1.gguf";    Desc = "程式碼" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q5_1.gguf";Desc = "TRI-Matrix" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-HRR-DI-Uncensored-Q5_1.gguf";      Desc = "DI-Matrix" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-CODE-DI-Uncensored-Q5_1.gguf";     Desc = "DI-Matrix 程式碼" }
    )
    "Q8_0" = @(
        [PSCustomObject]@{ File = "OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf";          Desc = "增強版" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q8_0.gguf";Desc = "TRI-Matrix" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-HRR-CODE-5-TRI-Uncensored-Q8_0.gguf"; Desc = "TRI-Matrix v5" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-HRR-DI-Uncensored-Q8_0.gguf";      Desc = "DI-Matrix" }
        [PSCustomObject]@{ File = "OpenAI-20B-NEO-CODE-DI-Uncensored-Q8_0.gguf";     Desc = "DI-Matrix 程式碼" }
    )
}

# ─── 選擇模型 ─────────────────────────────────────────────────
function Select-Model {
    Write-Host "請選擇量化類型:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] IQ4_NL  - 約 12GB  | 創意/娛樂用途 (Imatrix 最強效果)" -ForegroundColor Yellow
    Write-Host "  [2] Q5_1    - 約 16GB  | 均衡/一般用途 (穩定性佳)"          -ForegroundColor Green
    Write-Host "  [3] Q8_0    - 約 22GB  | 最高品質      (檔案最大)"          -ForegroundColor Magenta
    Write-Host "  [4] 手動輸入檔名"
    Write-Host "  [0] 結束"
    Write-Host ""
    $choice = Read-Host "請輸入選項 (0-4)"

    switch ($choice) {
        "0" { exit 0 }
        "1" { return Select-FromList "IQ4_NL" "約 12GB" $Models["IQ4_NL"] }
        "2" { return Select-FromList "Q5_1"   "約 16GB" $Models["Q5_1"] }
        "3" { return Select-FromList "Q8_0"   "約 22GB" $Models["Q8_0"] }
        "4" {
            $file = Read-Host "請輸入完整檔名 (例: OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf)"
            if ([string]::IsNullOrWhiteSpace($file)) { Write-Err "檔名不能為空"; exit 1 }
            return $file
        }
        default { Write-Err "無效選項"; exit 1 }
    }
}

function Select-FromList ($quantType, $sizeHint, $list) {
    Write-Host ""
    Write-Host "=== $quantType 模型清單 ($sizeHint) ===" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host ("  [{0}] {1,-55} ({2})" -f ($i+1), $list[$i].File, $list[$i].Desc)
    }
    Write-Host "  [0] 返回"
    Write-Host ""
    $idx = Read-Host "請選擇模型 (0-$($list.Count))"

    if ($idx -eq "0") { return Select-Model }
    $n = [int]$idx - 1
    if ($n -lt 0 -or $n -ge $list.Count) { Write-Err "無效選項"; exit 1 }
    return $list[$n].File
}

# ─── 下載進度回調 ─────────────────────────────────────────────
function Invoke-Download ($modelFile, $destPath, $downloader) {
    $url = "$HF_BASE/$modelFile"

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  準備下載:"
    Write-Host "    檔案: $modelFile" -ForegroundColor White
    Write-Host "    目標: $destPath"  -ForegroundColor DarkGray
    Write-Host "    來源: $url"       -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # 檢查是否已存在
    if (Test-Path $destPath) {
        $existSize = [math]::Round((Get-Item $destPath).Length / 1MB)
        Write-Warn "檔案已存在 (${existSize} MB): $destPath"
        $overwrite = Read-Host "是否重新下載? (y/N)"
        if ($overwrite.ToLower() -ne "y") {
            Write-Info "取消下載"
            return
        }
        Remove-Item $destPath -Force
    }

    Write-Info "使用下載工具: $downloader"

    switch ($downloader) {
        "hf-cli" {
            Write-Info "使用 huggingface-cli 下載..."
            & huggingface-cli download $HF_REPO $modelFile `
                --local-dir $ModelsDir `
                --local-dir-use-symlinks False
        }
        "python" {
            Write-Info "使用 Python huggingface_hub 下載..."
            $script = @"
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='$HF_REPO', filename='$modelFile', local_dir=r'$ModelsDir', local_dir_use_symlinks=False)
"@
            python -c $script
        }
        "curl" {
            Write-Info "使用 curl 下載..."
            Write-Warn "curl 不支援斷點續傳，建議安裝: pip install huggingface_hub[cli]"
            $headers = @{ "User-Agent" = "Mozilla/5.0" }
            $token = $env:HF_TOKEN
            if ($token) { $headers["Authorization"] = "Bearer $token" }
            Invoke-WebRequest -Uri $url -OutFile $destPath -Headers $headers `
                -UseBasicParsing
        }
        "wget" {
            Write-Info "使用 wget 下載..."
            wget -c $url -O $destPath --show-progress
        }
        default {
            # PowerShell 內建 (最慢，無進度)
            Write-Info "使用 PowerShell Invoke-WebRequest 下載..."
            Write-Warn "無進度顯示，建議安裝: pip install huggingface_hub[cli]"
            $ProgressPreference = "Continue"
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
        }
    }

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Err "下載失敗! 錯誤碼: $LASTEXITCODE"
        Write-Info "若需要認證請設定: `$env:HF_TOKEN = 'your_token'"
        exit 1
    }

    if (Test-Path $destPath) {
        $sizeMB = [math]::Round((Get-Item $destPath).Length / 1MB)
        Write-Host ""
        Write-Success "模型下載完成!"
        Write-Host "  路徑: $destPath"    -ForegroundColor Cyan
        Write-Host "  大小: ${sizeMB} MB" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [提示] 可執行 .\serve.ps1 啟動模型服務" -ForegroundColor Yellow
    } else {
        Write-Err "下載後找不到檔案: $destPath"
        exit 1
    }
}

# ─── 主程式 ───────────────────────────────────────────────────
Show-Header

# 建立 models 目錄
if (-not (Test-Path $ModelsDir)) { New-Item -ItemType Directory -Path $ModelsDir | Out-Null }

$downloader = Get-Downloader
if ($downloader) {
    Write-Info "偵測到下載工具: $downloader"
} else {
    Write-Warn "未找到推薦下載工具，將使用 PowerShell 內建方式 (無進度顯示)"
    Write-Host "  建議安裝: pip install huggingface_hub[cli]" -ForegroundColor DarkGray
    $downloader = "builtin"
}
Write-Host ""

# 支援命令列直接指定: .\download.ps1 OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf
if ($args.Count -ge 1) {
    $modelFile = $args[0]
    Write-Info "命令列模式，直接下載: $modelFile"
} else {
    $modelFile = Select-Model
}

$destPath = Join-Path $ModelsDir $modelFile
Invoke-Download $modelFile $destPath $downloader

Write-Host ""
Read-Host "按 Enter 結束"

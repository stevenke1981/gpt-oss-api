# GPT-OSS 20B Model Downloader (Windows PowerShell)
# Usage: .\download.ps1
# Direct: .\download.ps1 "OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf"

param([string]$FileName = "")

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$ModelsDir = Join-Path $RootDir "models"
$HF_REPO   = "DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf"
$HF_BASE   = "https://huggingface.co/$HF_REPO/resolve/main"

function info  ($m) { Write-Host "[INFO]    $m" -ForegroundColor Cyan }
function ok    ($m) { Write-Host "[OK]      $m" -ForegroundColor Green }
function warn  ($m) { Write-Host "[WARN]    $m" -ForegroundColor Yellow }
function err   ($m) { Write-Host "[ERROR]   $m" -ForegroundColor Red }

if (-not (Test-Path $ModelsDir)) { New-Item -ItemType Directory -Path $ModelsDir | Out-Null }

# --- detect downloader ---
function Get-Downloader {
    if (Get-Command "huggingface-cli" -ErrorAction SilentlyContinue) { return "hf-cli" }
    if (Get-Command "python" -ErrorAction SilentlyContinue) {
        python -c "import huggingface_hub" 2>$null
        if ($LASTEXITCODE -eq 0) { return "python" }
    }
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) { return "curl" }
    return "builtin"
}

# --- model list ---
$IQ4 = @(
    @{ f="OpenAI-20B-NEO-Uncensored2-IQ4_NL.gguf";            d="Standard" }
    @{ f="OpenAI-20B-NEOPlus-Uncensored-IQ4_NL.gguf";         d="Plus" }
    @{ f="OpenAI-20B-NEO-CODEPlus16-Uncensored-IQ4_NL.gguf";  d="Code+" }
    @{ f="OpenAI-20B-NEO-HRRPlus-Uncensored-IQ4_NL.gguf";     d="DI-Matrix" }
    @{ f="OpenAI-20B-NEO-CODEPlus-Uncensored-IQ4_NL.gguf";    d="DI-Matrix Code" }
    @{ f="OpenAI-20B-NEO-CODE2-Plus-Uncensored-IQ4_NL.gguf";  d="Code v2" }
    @{ f="OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-IQ4_NL.gguf";d="TRI-Matrix" }
)
$Q51 = @(
    @{ f="OpenAI-20B-NEO-Uncensored2-Q5_1.gguf";              d="Standard" }
    @{ f="OpenAI-20B-NEOPlus-Uncensored-Q5_1.gguf";           d="Plus" }
    @{ f="OpenAI-20B-NEO-CODEPlus-Uncensored-Q5_1.gguf";      d="Code+" }
    @{ f="OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q5_1.gguf";  d="TRI-Matrix" }
    @{ f="OpenAI-20B-NEO-HRR-DI-Uncensored-Q5_1.gguf";        d="DI-Matrix" }
    @{ f="OpenAI-20B-NEO-CODE-DI-Uncensored-Q5_1.gguf";       d="DI-Matrix Code" }
)
$Q80 = @(
    @{ f="OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf";              d="Plus" }
    @{ f="OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q8_0.gguf";     d="TRI-Matrix" }
    @{ f="OpenAI-20B-NEO-HRR-CODE-5-TRI-Uncensored-Q8_0.gguf";   d="TRI-Matrix v5" }
    @{ f="OpenAI-20B-NEO-HRR-DI-Uncensored-Q8_0.gguf";           d="DI-Matrix" }
    @{ f="OpenAI-20B-NEO-CODE-DI-Uncensored-Q8_0.gguf";          d="DI-Matrix Code" }
)

function Show-SubMenu ($title, $sizeHint, $list) {
    Write-Host ""
    Write-Host "=== $title ($sizeHint) ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host ("  [{0}] {1,-55} ({2})" -f ($i+1), $list[$i].f, $list[$i].d)
    }
    Write-Host "  [0] Back"
    Write-Host ""
    $n = Read-Host "Select"
    if ($n -eq "0") { return "" }
    $idx = [int]$n - 1
    if ($idx -lt 0 -or $idx -ge $list.Count) { err "Invalid selection"; exit 1 }
    return $list[$idx].f
}

function Select-Model {
    Write-Host ""
    Write-Host "Select quantization type:" -ForegroundColor White
    Write-Host "  [1] IQ4_NL  ~12GB  Creative / general (strongest Imatrix)" -ForegroundColor Yellow
    Write-Host "  [2] Q5_1    ~16GB  Balanced (more stable)"                 -ForegroundColor Green
    Write-Host "  [3] Q8_0    ~22GB  Highest quality (largest file)"         -ForegroundColor Magenta
    Write-Host "  [4] Enter filename manually"
    Write-Host "  [0] Exit"
    Write-Host ""
    $c = Read-Host "Choice"
    switch ($c) {
        "0" { exit 0 }
        "1" { return Show-SubMenu "IQ4_NL" "~12 GB" $IQ4 }
        "2" { return Show-SubMenu "Q5_1"   "~16 GB" $Q51 }
        "3" { return Show-SubMenu "Q8_0"   "~22 GB" $Q80 }
        "4" {
            $f = Read-Host "Filename (e.g. OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf)"
            if ([string]::IsNullOrWhiteSpace($f)) { err "Filename required"; exit 1 }
            return $f
        }
        default { err "Invalid choice"; exit 1 }
    }
}

function Start-Download ($modelFile) {
    $dest = Join-Path $ModelsDir $modelFile
    $url  = "$HF_BASE/$modelFile"
    $dl   = Get-Downloader

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  File   : $modelFile"
    Write-Host "  Dest   : $dest" -ForegroundColor DarkGray
    Write-Host "  Source : $url"  -ForegroundColor DarkGray
    Write-Host "  Tool   : $dl"   -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    if (Test-Path $dest) {
        $mb = [math]::Round((Get-Item $dest).Length / 1MB)
        warn "File already exists (${mb} MB)"
        $ow = Read-Host "Re-download? (y/N)"
        if ($ow -ne "y") { info "Cancelled"; return }
        Remove-Item $dest -Force
    }

    info "Downloading via $dl ..."

    switch ($dl) {
        "hf-cli" {
            huggingface-cli download $HF_REPO $modelFile `
                --local-dir $ModelsDir --local-dir-use-symlinks False
        }
        "python" {
            $py = "from huggingface_hub import hf_hub_download; " +
                  "hf_hub_download(repo_id='$HF_REPO', filename='$modelFile', " +
                  "local_dir=r'$ModelsDir', local_dir_use_symlinks=False)"
            python -c $py
        }
        "curl" {
            $token = $env:HF_TOKEN
            if ($token) {
                curl.exe -L --progress-bar -H "Authorization: Bearer $token" "$url" -o "$dest"
            } else {
                curl.exe -L --progress-bar "$url" -o "$dest"
            }
        }
        default {
            info "Using PowerShell Invoke-WebRequest (no progress bar)"
            warn "For better experience: pip install huggingface_hub[cli]"
            $hdrs = @{}
            if ($env:HF_TOKEN) { $hdrs["Authorization"] = "Bearer $env:HF_TOKEN" }
            Invoke-WebRequest -Uri $url -OutFile $dest -Headers $hdrs -UseBasicParsing
        }
    }

    if (Test-Path $dest) {
        $mb = [math]::Round((Get-Item $dest).Length / 1MB)
        Write-Host ""
        ok "Download complete: $modelFile (${mb} MB)"
        info "Run .\serve.ps1 to start the API server"
    } else {
        err "File not found after download: $dest"
        info "Set HF_TOKEN if the repo requires authentication: `$env:HF_TOKEN = 'hf_...'"
        exit 1
    }
}

# --- main ---
Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  GPT-OSS 20B Model Downloader" -ForegroundColor White
Write-Host "  Repo: $HF_REPO" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor Cyan

$dl = Get-Downloader
info "Downloader: $dl"
if ($dl -eq "builtin") {
    warn "huggingface-cli not found. Install for best experience:"
    Write-Host "  pip install huggingface_hub[cli]" -ForegroundColor DarkGray
}

if ($FileName -ne "") {
    $selected = $FileName
} else {
    $selected = Select-Model
}

if ([string]::IsNullOrWhiteSpace($selected)) {
    info "No model selected. Exiting."
    exit 0
}

Start-Download $selected

Write-Host ""
Read-Host "Press Enter to exit"

# GPT-OSS 20B Gradio Frontend Launcher (Windows)
# Usage: .\frontend.ps1
#        .\frontend.ps1 -Port 7860
#        .\frontend.ps1 -Host 0.0.0.0 -Port 7860
#        .\frontend.ps1 -Share

param(
    [string]$FrontendHost = "127.0.0.1",
    [int]$Port            = 7860,
    [string]$Server       = "",
    [switch]$Share
)

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir     = Split-Path -Parent $ScriptDir
$ConfigFile  = Join-Path $RootDir "config\settings.ini"
$FrontendDir = Join-Path $RootDir "frontend"
$AppPy       = Join-Path $FrontendDir "app.py"
$ReqTxt      = Join-Path $FrontendDir "requirements.txt"

# ── read llama-server URL from settings.ini ───────────────────
$cfgServerHost = "127.0.0.1"; $cfgServerPort = 8080
if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        if ($_ -match '^HOST\s*=\s*(.+)')  { $cfgServerHost = $Matches[1].Trim() }
        if ($_ -match '^PORT\s*=\s*(\d+)') { $cfgServerPort = [int]$Matches[1].Trim() }
    }
}
if ($Server -eq "") {
    $llmHost = if ($cfgServerHost -eq "0.0.0.0") { "127.0.0.1" } else { $cfgServerHost }
    $Server  = "http://${llmHost}:${cfgServerPort}"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  GPT-OSS 20B  Gradio Frontend" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host ("  llama-server : {0}" -f $Server)
Write-Host ("  UI address   : http://{0}:{1}" -f $FrontendHost, $Port)
if ($Share) { Write-Host "  Gradio share : enabled (public link)" -ForegroundColor Yellow }
Write-Host ""

# ── check python ──────────────────────────────────────────────
$python = $null
foreach ($cmd in @("python", "python3", "py")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) { $python = $cmd; break }
}
if (-not $python) {
    Write-Host "[ERROR] Python not found. Install Python 3.9+ and retry." -ForegroundColor Red
    exit 1
}

# ── install / check dependencies ─────────────────────────────
Write-Host "Checking dependencies..." -ForegroundColor DarkGray
$gradioOk = & $python -c "import gradio" 2>$null; $gradioCheck = $LASTEXITCODE
if ($gradioCheck -ne 0) {
    Write-Host "Installing frontend requirements..." -ForegroundColor Yellow
    & $python -m pip install -r $ReqTxt --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] pip install failed." -ForegroundColor Red
        exit 1
    }
}

# ── build args ────────────────────────────────────────────────
$pyArgs = @($AppPy, "--server", $Server, "--host", $FrontendHost, "--port", $Port)
if ($Share) { $pyArgs += "--share" }

Write-Host "Starting Gradio..." -ForegroundColor Green
Write-Host ""
& $python @pyArgs

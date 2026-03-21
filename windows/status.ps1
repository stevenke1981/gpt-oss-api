# llama-server Status & Usage Monitor (Windows PowerShell)
# Usage: .\status.ps1
#        .\status.ps1 -Host 0.0.0.0 -Port 8080
#        .\status.ps1 -Once          # single snapshot, no loop

param(
    [string]$ServerHost = "",
    [int]$Port          = 0,
    [switch]$Once
)

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$ConfigFile = Join-Path $RootDir "config\settings.ini"

# ── load config ───────────────────────────────────────────────
$cfgHost = "127.0.0.1"; $cfgPort = 8080
if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        if ($_ -match '^HOST\s*=\s*(.+)')  { $cfgHost = $Matches[1].Trim() }
        if ($_ -match '^PORT\s*=\s*(\d+)') { $cfgPort = [int]$Matches[1].Trim() }
    }
}
if ($ServerHost -ne "") { $cfgHost = $ServerHost }
if ($Port -ne 0)        { $cfgPort = $Port }
$BASE = "http://${cfgHost}:${cfgPort}"

# ── helpers ───────────────────────────────────────────────────
function Get-Metric ($metrics, $name) {
    $line = $metrics | Where-Object { $_ -match "^${name}[{ ]" } | Select-Object -Last 1
    if ($line) { return ($line -split '\s+')[-1] }
    return $null
}

function Show-Status {
    Clear-Host
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  llama-server Status   $BASE   $time" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan

    # ── health ────────────────────────────────────────────────
    try {
        $healthJson = Invoke-RestMethod -Uri "$BASE/health" -TimeoutSec 3 -ErrorAction Stop
        $status    = $healthJson.status
        $slotsIdle = $healthJson.slots_idle
        $slotsProc = $healthJson.slots_processing
        Write-Host ""
        if ($status -eq "ok") {
            Write-Host "  Health    : OK" -ForegroundColor Green
        } else {
            Write-Host "  Health    : $status" -ForegroundColor Yellow
        }
        Write-Host ("  Slots     : {0} idle  /  {1} active" -f $slotsIdle, $slotsProc)
    } catch {
        Write-Host ""
        Write-Host "  [OFFLINE]  Server not reachable at $BASE" -ForegroundColor Red
        Write-Host ""
        return
    }

    # ── metrics ───────────────────────────────────────────────
    try {
        $raw = (Invoke-WebRequest -Uri "$BASE/metrics" -TimeoutSec 3 -UseBasicParsing).Content
        $metrics = $raw -split "`n"

        $promptTok  = Get-Metric $metrics "llamacpp:tokens_evaluated_total"
        $genTok     = Get-Metric $metrics "llamacpp:tokens_predicted_total"
        $promptTP   = Get-Metric $metrics "llamacpp:prompt_tokens_per_second"
        $genTP      = Get-Metric $metrics "llamacpp:predicted_tokens_per_second"
        $reqTotal   = Get-Metric $metrics "llamacpp:requests_processing_total"
        $reqFail    = Get-Metric $metrics "llamacpp:requests_failed_total"
        $kvRatio    = Get-Metric $metrics "llamacpp:kv_cache_usage_ratio"
        $kvCells    = Get-Metric $metrics "llamacpp:kv_cache_tokens"

        Write-Host ""
        Write-Host "  -- Throughput -------------------------------------------" -ForegroundColor DarkGray
        Write-Host ("  {0,-18} {1} tok/s" -f "Prompt speed:", ($promptTP ?? "n/a")) -ForegroundColor Cyan
        Write-Host ("  {0,-18} {1} tok/s" -f "Generate speed:", ($genTP ?? "n/a")) -ForegroundColor Green

        Write-Host ""
        Write-Host "  -- Tokens -----------------------------------------------" -ForegroundColor DarkGray
        Write-Host ("  {0,-18} {1}" -f "Prompt processed:", ($promptTok ?? "n/a"))
        Write-Host ("  {0,-18} {1}" -f "Tokens generated:", ($genTok ?? "n/a"))

        Write-Host ""
        Write-Host "  -- Requests ---------------------------------------------" -ForegroundColor DarkGray
        Write-Host ("  {0,-18} {1}" -f "Total:", ($reqTotal ?? "n/a"))
        if ($reqFail -and [double]$reqFail -gt 0) {
            Write-Host ("  {0,-18} {1}" -f "Failed:", $reqFail) -ForegroundColor Red
        } else {
            Write-Host ("  {0,-18} {1}" -f "Failed:", ($reqFail ?? "n/a"))
        }

        Write-Host ""
        Write-Host "  -- KV Cache ---------------------------------------------" -ForegroundColor DarkGray
        if ($kvRatio) {
            $pct = [math]::Round([double]$kvRatio * 100, 1)
            $color = if ($pct -gt 80) { "Red" } elseif ($pct -gt 50) { "Yellow" } else { "Green" }
            Write-Host ("  {0,-18} {1}%" -f "Usage:", $pct) -ForegroundColor $color
        }
        Write-Host ("  {0,-18} {1} tokens" -f "Cached:", ($kvCells ?? "n/a"))

    } catch {
        Write-Host ""
        Write-Host "  (metrics endpoint not available)" -ForegroundColor DarkGray
        Write-Host "  Start server with --metrics flag (already in serve.ps1)" -ForegroundColor DarkGray
    }

    # ── GPU ───────────────────────────────────────────────────
    if (Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue) {
        try {
            $gpuData = & nvidia-smi.exe --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu `
                --format=csv,noheader 2>$null
            if ($gpuData) {
                Write-Host ""
                Write-Host "  -- GPU --------------------------------------------------" -ForegroundColor DarkGray
                $g = $gpuData -split ","
                Write-Host ("  {0,-18} {1}" -f "GPU:",         $g[0].Trim())
                Write-Host ("  {0,-18} {1}" -f "Utilization:", $g[1].Trim()) -ForegroundColor Yellow
                Write-Host ("  {0,-18} {1} / {2}" -f "VRAM:", $g[2].Trim(), $g[3].Trim())
                Write-Host ("  {0,-18} {1}°C" -f "Temp:", $g[4].Trim())
            }
        } catch {}
    }

    Write-Host ""
    Write-Host "  Refreshes every 3s — Ctrl+C to exit" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
}

# ── run ───────────────────────────────────────────────────────
if ($Once) {
    Show-Status
} else {
    while ($true) {
        Show-Status
        Start-Sleep 3
    }
}

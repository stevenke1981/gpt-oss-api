# GPT-OSS 20B 設定快速切換工具 (Windows PowerShell)
# 用途: 切換 settings.local.ini 預設組合

param()

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$LocalCfg   = Join-Path $RootDir "config\settings.local.ini"

function info  ($m) { Write-Host "[資訊]    $m" -ForegroundColor Cyan }
function ok    ($m) { Write-Host "[成功]    $m" -ForegroundColor Green }
function warn  ($m) { Write-Host "[提示]    $m" -ForegroundColor Yellow }
function err   ($m) { Write-Host "[錯誤]    $m" -ForegroundColor Red }

# ─── 預設組合 ─────────────────────────────────────────────────
$Presets = @(
    [pscustomobject]@{ Name="純CPU";    Desc="安全模式，無 GPU，適合測試";              GPU=0;  CTX=4096;  Predict=-1; Parallel=1; Threads=8 }
    [pscustomobject]@{ Name="混合30層"; Desc="GPU+CPU，RTX 3060 12GB 推薦";            GPU=30; CTX=6144;  Predict=-1; Parallel=1; Threads=8 }
    [pscustomobject]@{ Name="混合35層"; Desc="GPU+CPU，記憶體較充裕時使用";             GPU=35; CTX=6144;  Predict=-1; Parallel=1; Threads=8 }
    [pscustomobject]@{ Name="全GPU";    Desc="全部 offload，VRAM 需夠用";              GPU=-1; CTX=8192;  Predict=-1; Parallel=2; Threads=4 }
    [pscustomobject]@{ Name="高並行";   Desc="多用戶，4 槽平行處理";                   GPU=30; CTX=4096;  Predict=-1; Parallel=4; Threads=8 }
    [pscustomobject]@{ Name="長文本";   Desc="單用戶，最大 context 32k";               GPU=30; CTX=32768; Predict=-1; Parallel=1; Threads=8 }
)

# ─── 讀取目前設定 ──────────────────────────────────────────────
function Show-Current {
    Write-Host ""
    Write-Host "── 目前 settings.local.ini ──" -ForegroundColor White
    if (Test-Path $LocalCfg) {
        Get-Content $LocalCfg | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    } else {
        Write-Host "  (尚未建立，使用 settings.ini 預設值)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ─── 寫入設定 ─────────────────────────────────────────────────
function Write-Preset ($gpu, $ctx, $predict, $parallel, $threads) {
    $content = @"
[server]
N_GPU_LAYERS=$gpu
N_THREADS=$threads

[inference]
CTX_SIZE=$ctx
N_PREDICT=$predict
N_PARALLEL=$parallel
"@
    $content | Set-Content -Path $LocalCfg -Encoding UTF8
    ok "已寫入 $LocalCfg"
}

function Write-Custom {
    Write-Host ""
    Write-Host "── 自訂設定 (按 Enter 保留目前值) ──" -ForegroundColor White
    Write-Host ""

    # 讀取目前值
    $cur = @{ GPU=0; CTX=8192; Predict=-1; Parallel=1; Threads=8 }
    if (Test-Path $LocalCfg) {
        Get-Content $LocalCfg | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*[#\[]' } | ForEach-Object {
            $p = $_ -split '=', 2
            switch ($p[0].Trim()) {
                "N_GPU_LAYERS" { $cur.GPU      = $p[1].Trim() }
                "CTX_SIZE"     { $cur.CTX      = $p[1].Trim() }
                "N_PREDICT"    { $cur.Predict  = $p[1].Trim() }
                "N_PARALLEL"   { $cur.Parallel = $p[1].Trim() }
                "N_THREADS"    { $cur.Threads  = $p[1].Trim() }
            }
        }
    }

    $v = Read-Host ("  GPU 層數    [{0}]  (0=CPU, -1=全GPU, 30=混合)" -f $cur.GPU)
    $gpu      = if ($v) { $v } else { $cur.GPU }

    $v = Read-Host ("  Context     [{0}]  (4096 / 6144 / 8192 / 32768)" -f $cur.CTX)
    $ctx      = if ($v) { $v } else { $cur.CTX }

    $v = Read-Host ("  Max tokens  [{0}]  (-1=不限)" -f $cur.Predict)
    $predict  = if ($v) { $v } else { $cur.Predict }

    $v = Read-Host ("  平行槽數    [{0}]  (1=單用戶, 4=多用戶)" -f $cur.Parallel)
    $parallel = if ($v) { $v } else { $cur.Parallel }

    $v = Read-Host ("  CPU 執行緒  [{0}]" -f $cur.Threads)
    $threads  = if ($v) { $v } else { $cur.Threads }

    Write-Host ""
    Write-Preset $gpu $ctx $predict $parallel $threads
}

# ─── 主選單 ───────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  GPT-OSS 20B 設定快速切換" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

Show-Current

Write-Host "── 選擇預設組合 ──" -ForegroundColor White
Write-Host ""

for ($i = 0; $i -lt $Presets.Count; $i++) {
    $p = $Presets[$i]
    Write-Host ("  [{0}] {1,-8}  {2}" -f ($i+1), $p.Name, $p.Desc) -ForegroundColor Cyan
    Write-Host ("       GPU層數:{0,-4}  Context:{1,-6}  平行槽:{2,-2}  執行緒:{3}" `
        -f $p.GPU, $p.CTX, $p.Parallel, $p.Threads) -ForegroundColor DarkGray
    Write-Host ""
}

$customIdx = $Presets.Count + 1
Write-Host ("  [{0}] {1,-8}  手動輸入每個設定值" -f $customIdx, "自訂") -ForegroundColor Cyan
Write-Host ""
Write-Host "  [0] 離開" -ForegroundColor DarkGray
Write-Host ""

$choice = Read-Host "請選擇 [0-$customIdx]"

if ($choice -eq "0") { exit 0 }

if ($choice -eq $customIdx.ToString()) {
    Write-Custom
} elseif ([int]::TryParse($choice, [ref]$null) -and [int]$choice -ge 1 -and [int]$choice -le $Presets.Count) {
    $p = $Presets[[int]$choice - 1]
    Write-Host ""
    info "套用預設組合: $($p.Name)"
    Write-Preset $p.GPU $p.CTX $p.Predict $p.Parallel $p.Threads
} else {
    err "無效選項"; exit 1
}

Write-Host ""
warn "重新執行 .\serve.ps1 讓設定生效"
Write-Host ""

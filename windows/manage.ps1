# ============================================================
# GPT-OSS 20B 模型管理腳本 (Windows PowerShell)
# 用途: 列出、查看資訊、刪除已下載的 GGUF 模型
# 執行: .\manage.ps1
# ============================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$ModelsDir = Join-Path $RootDir "models"

function Write-Info    ($msg) { Write-Host "[資訊] $msg" -ForegroundColor Cyan }
function Write-Success ($msg) { Write-Host "[成功] $msg" -ForegroundColor Green }
function Write-Warn    ($msg) { Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Err     ($msg) { Write-Host "[錯誤] $msg" -ForegroundColor Red }

if (-not (Test-Path $ModelsDir)) { New-Item -ItemType Directory -Path $ModelsDir | Out-Null }

# ─── 取得模型清單 ─────────────────────────────────────────────
function Get-ModelList {
    return @(Get-ChildItem -Path $ModelsDir -Filter "*.gguf" -File | Sort-Object Name)
}

# ─── 列出所有模型 ─────────────────────────────────────────────
function Show-List {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  已下載的模型清單" -ForegroundColor White
    Write-Host "  目錄: $ModelsDir" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $files = Get-ModelList
    if ($files.Count -eq 0) {
        Write-Host "  [提示] 尚未下載任何模型，請先執行 .\download.ps1" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "按 Enter 返回"
        return
    }

    $totalBytes = 0
    $i = 1
    foreach ($f in $files) {
        $sizeMB = [math]::Round($f.Length / 1MB, 1)
        $totalBytes += $f.Length
        Write-Host ""
        Write-Host ("  [{0}] {1}" -f $i, $f.Name) -ForegroundColor White
        Write-Host ("      大小: {0} MB" -f $sizeMB) -ForegroundColor DarkGray
        Write-Host ("      路徑: {0}" -f $f.FullName) -ForegroundColor DarkGray
        Write-Host ("      修改: {0}" -f $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor DarkGray
        $i++
    }

    $totalGB = [math]::Round($totalBytes / 1GB, 2)
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  共 {0} 個模型，總計 {1} GB" -f $files.Count, $totalGB) -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "按 Enter 返回"
}

# ─── 查看模型詳細資訊 ─────────────────────────────────────────
function Show-Info {
    Clear-Host
    Write-Host ""
    Write-Host "=== 查看模型詳細資訊 ===" -ForegroundColor Cyan
    Write-Host ""

    $files = Get-ModelList
    if ($files.Count -eq 0) {
        Write-Host "  [提示] 尚未下載任何模型" -ForegroundColor Yellow
        Read-Host "按 Enter 返回"; return
    }

    for ($i = 0; $i -lt $files.Count; $i++) {
        $sizeMB = [math]::Round($files[$i].Length / 1MB, 1)
        Write-Host ("  [{0}] {1,-55} ({2} MB)" -f ($i+1), $files[$i].Name, $sizeMB)
    }
    Write-Host ""
    $num = Read-Host "請輸入模型編號 (0=取消)"
    if ($num -eq "0" -or [string]::IsNullOrWhiteSpace($num)) { return }

    $idx = [int]$num - 1
    if ($idx -lt 0 -or $idx -ge $files.Count) { Write-Err "無效編號"; Start-Sleep 2; return }

    $f = $files[$idx]
    $sizeMB = [math]::Round($f.Length / 1MB, 1)
    $sizeGB = [math]::Round($f.Length / 1GB, 2)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ("  模型資訊: {0}" -f $f.Name) -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  {0,-14} {1}" -f "檔名:", $f.Name)
    Write-Host ("  {0,-14} {1} MB (~{2} GB)" -f "大小:", $sizeMB, $sizeGB)
    Write-Host ("  {0,-14} {1}" -f "完整路徑:", $f.FullName)
    Write-Host ("  {0,-14} {1}" -f "修改時間:", $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))

    Write-Host ""
    Write-Host "  量化類型解析:" -ForegroundColor White
    if ($f.Name -match "IQ4_NL") { Write-Host "    類型: IQ4_NL (4-bit Imatrix) - 創意/娛樂用途，Imatrix 效果最強" -ForegroundColor Yellow }
    if ($f.Name -match "Q5_1")   { Write-Host "    類型: Q5_1 (5-bit) - 均衡一般用途，穩定性佳" -ForegroundColor Green }
    if ($f.Name -match "Q8_0")   { Write-Host "    類型: Q8_0 (8-bit) - 最高品質" -ForegroundColor Magenta }
    if ($f.Name -match "TRI")    { Write-Host "    Matrix: TRI-Matrix (3個資料集平均，最穩定)" }
    elseif ($f.Name -match "-DI-") { Write-Host "    Matrix: DI-Matrix (2個資料集平均，平衡特性)" }
    else                          { Write-Host "    Matrix: 標準 Imatrix (單資料集)" }
    if ($f.Name -match "CODE")   { Write-Host "    特化: 程式碼生成增強版" -ForegroundColor Cyan }
    if ($f.Name -match "HRR")    { Write-Host "    特化: HRR (高重複率減少優化)" }

    Write-Host ""
    Write-Host "  建議啟動參數:" -ForegroundColor White
    Write-Host "    --ctx-size    8192      (最大支援 131072)"
    Write-Host "    --temp        0.8       (創意用 1.0-1.2 / 程式碼用 0.6)"
    Write-Host "    --rep-penalty 1.1       (重要! 防止重複)"
    Write-Host "    --top-k       40"
    Write-Host "    --top-p       0.95"
    Write-Host "    --min-p       0.05"
    Write-Host ""

    $doSha = Read-Host "是否計算 SHA256 校驗碼? (y/N)"
    if ($doSha.ToLower() -eq "y") {
        Write-Info "計算中 (大檔案需要數秒)..."
        $sha = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
        Write-Host "  SHA256: $sha" -ForegroundColor DarkGray
    }

    Write-Host ""
    Read-Host "按 Enter 返回"
}

# ─── 刪除模型 ─────────────────────────────────────────────────
function Remove-Model {
    Clear-Host
    Write-Host ""
    Write-Host "=== 刪除模型 ===" -ForegroundColor Cyan
    Write-Host ""

    $files = Get-ModelList
    if ($files.Count -eq 0) {
        Write-Host "  [提示] 尚未下載任何模型" -ForegroundColor Yellow
        Read-Host "按 Enter 返回"; return
    }

    for ($i = 0; $i -lt $files.Count; $i++) {
        $sizeMB = [math]::Round($files[$i].Length / 1MB, 1)
        Write-Host ("  [{0}] {1,-55} ({2} MB)" -f ($i+1), $files[$i].Name, $sizeMB)
    }
    Write-Host ""
    $num = Read-Host "請輸入要刪除的模型編號 (0=取消)"
    if ($num -eq "0" -or [string]::IsNullOrWhiteSpace($num)) { return }

    $idx = [int]$num - 1
    if ($idx -lt 0 -or $idx -ge $files.Count) { Write-Err "無效編號"; Start-Sleep 2; return }

    $f = $files[$idx]
    $sizeMB = [math]::Round($f.Length / 1MB, 1)

    Write-Host ""
    Write-Warn "即將刪除: $($f.Name)"
    Write-Warn "檔案大小: ${sizeMB} MB  (此操作無法復原)"
    Write-Host ""
    $confirm = Read-Host "確認刪除? 請輸入 YES 確認"
    if ($confirm -ne "YES") {
        Write-Info "已取消刪除"
        Start-Sleep 1; return
    }

    Remove-Item $f.FullName -Force
    Write-Success "已刪除: $($f.Name)"
    Start-Sleep 2
}

# ─── 磁碟空間 ─────────────────────────────────────────────────
function Show-DiskInfo {
    Clear-Host
    Write-Host ""
    Write-Host "=== 磁碟空間資訊 ===" -ForegroundColor Cyan
    Write-Host ""

    $drive = Split-Path -Qualifier $ModelsDir
    $disk  = Get-PSDrive ($drive.TrimEnd(':'))
    $usedGB  = [math]::Round($disk.Used  / 1GB, 1)
    $freeGB  = [math]::Round($disk.Free  / 1GB, 1)
    $totalGB = [math]::Round(($disk.Used + $disk.Free) / 1GB, 1)

    Write-Host ("  {0,-14} {1}" -f "磁碟機:", $drive)
    Write-Host ("  {0,-14} {1} GB" -f "總容量:", $totalGB)
    Write-Host ("  {0,-14} {1} GB" -f "已使用:", $usedGB)
    Write-Host ("  {0,-14} " -f "可用空間:") -NoNewline
    Write-Host ("{0} GB" -f $freeGB) -ForegroundColor Green

    Write-Host ""
    Write-Host "  各量化類型所需空間:" -ForegroundColor White
    Write-Host "    IQ4_NL   約 12 GB"
    Write-Host "    Q5_1     約 16 GB"
    Write-Host "    Q8_0     約 22 GB"

    $files = Get-ModelList
    if ($files.Count -gt 0) {
        $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        $modelGB = [math]::Round($totalBytes / 1GB, 2)
        Write-Host ""
        Write-Host "  models 目錄已用空間:" -ForegroundColor White
        Write-Host ("    {0} 個模型，共 {1} GB" -f $files.Count, $modelGB)
    }

    Write-Host ""
    Read-Host "按 Enter 返回"
}

# ─── 清理臨時檔案 ─────────────────────────────────────────────
function Clear-Temp {
    Clear-Host
    Write-Host ""
    Write-Host "=== 清理不完整的下載檔案 ===" -ForegroundColor Cyan
    Write-Host ""

    $tmpFiles = @(Get-ChildItem -Path $ModelsDir -Include "*.tmp","*.part","*.download","*.incomplete" -File 2>$null)

    if ($tmpFiles.Count -eq 0) {
        Write-Info "未找到需要清理的臨時檔案"
    } else {
        Write-Host ("  找到 {0} 個臨時檔案:" -f $tmpFiles.Count) -ForegroundColor Yellow
        foreach ($f in $tmpFiles) {
            $sizeMB = [math]::Round($f.Length / 1MB, 1)
            Write-Host ("    {0}  ({1} MB)" -f $f.Name, $sizeMB)
        }
        Write-Host ""
        $clean = Read-Host "是否刪除以上臨時檔案? (y/N)"
        if ($clean.ToLower() -eq "y") {
            foreach ($f in $tmpFiles) {
                Remove-Item $f.FullName -Force
                Write-Success "已刪除: $($f.Name)"
            }
        } else {
            Write-Info "已取消清理"
        }
    }

    Write-Host ""
    Read-Host "按 Enter 返回"
}

# ─── 主選單 ───────────────────────────────────────────────────
while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  GPT-OSS 20B 模型管理工具" -ForegroundColor White
    Write-Host "  模型目錄: $ModelsDir" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $files = Get-ModelList
    if ($files.Count -gt 0) {
        Write-Host ("  已下載模型: {0} 個" -f $files.Count) -ForegroundColor Green
    } else {
        Write-Host "  已下載模型: 無" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  [1] 列出所有已下載模型"
    Write-Host "  [2] 查看模型詳細資訊"
    Write-Host "  [3] 刪除模型"
    Write-Host "  [4] 磁碟空間資訊"
    Write-Host "  [5] 清理不完整的下載檔案"
    Write-Host "  [0] 結束"
    Write-Host ""
    $choice = Read-Host "請選擇操作 (0-5)"

    switch ($choice) {
        "1" { Show-List }
        "2" { Show-Info }
        "3" { Remove-Model }
        "4" { Show-DiskInfo }
        "5" { Clear-Temp }
        "0" { Write-Host ""; exit 0 }
        default { Write-Err "無效選項"; Start-Sleep 1 }
    }
}

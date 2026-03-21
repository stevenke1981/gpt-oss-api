# GPT-OSS 20B Model Manager (Windows PowerShell)
# Usage: .\manage.ps1

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$ModelsDir = Join-Path $RootDir "models"

function info  ($m) { Write-Host "[INFO]    $m" -ForegroundColor Cyan }
function ok    ($m) { Write-Host "[OK]      $m" -ForegroundColor Green }
function warn  ($m) { Write-Host "[WARN]    $m" -ForegroundColor Yellow }
function err   ($m) { Write-Host "[ERROR]   $m" -ForegroundColor Red }

if (-not (Test-Path $ModelsDir)) { New-Item -ItemType Directory -Path $ModelsDir | Out-Null }

function Get-Models { @(Get-ChildItem -Path $ModelsDir -Filter "*.gguf" -File | Sort-Object Name) }

# --- list all models ---
function Show-List {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Downloaded Models" -ForegroundColor White
    Write-Host "  Dir: $ModelsDir" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $files = Get-Models
    if ($files.Count -eq 0) {
        warn "No models found. Run .\download.ps1 first."
        Write-Host ""; Read-Host "Press Enter to return"; return
    }

    $total = 0
    $i = 1
    foreach ($f in $files) {
        $mb = [math]::Round($f.Length / 1MB, 1)
        $total += $f.Length
        Write-Host ("  [{0}] {1}" -f $i, $f.Name) -ForegroundColor White
        Write-Host ("       {0} MB  |  {1}" -f $mb, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")) -ForegroundColor DarkGray
        $i++
    }

    $gb = [math]::Round($total / 1GB, 2)
    Write-Host ""
    Write-Host ("  Total: {0} models, {1} GB" -f $files.Count, $gb) -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter to return"
}

# --- model info ---
function Show-Info {
    Clear-Host
    Write-Host ""; Write-Host "=== Model Info ===" -ForegroundColor Cyan; Write-Host ""

    $files = Get-Models
    if ($files.Count -eq 0) { warn "No models found."; Read-Host "Press Enter"; return }

    for ($i = 0; $i -lt $files.Count; $i++) {
        $mb = [math]::Round($files[$i].Length / 1MB, 1)
        Write-Host ("  [{0}] {1}  ({2} MB)" -f ($i+1), $files[$i].Name, $mb)
    }
    Write-Host ""
    $n = Read-Host "Select number (0=cancel)"
    if ($n -eq "0" -or [string]::IsNullOrWhiteSpace($n)) { return }

    $idx = [int]$n - 1
    if ($idx -lt 0 -or $idx -ge $files.Count) { err "Invalid number"; Start-Sleep 2; return }

    $f  = $files[$idx]
    $mb = [math]::Round($f.Length / 1MB, 1)
    $gb = [math]::Round($f.Length / 1GB, 2)

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ("  Name : {0}" -f $f.Name) -ForegroundColor White
    Write-Host ("  Size : {0} MB  (~{1} GB)" -f $mb, $gb)
    Write-Host ("  Path : {0}" -f $f.FullName) -ForegroundColor DarkGray
    Write-Host ("  Date : {0}" -f $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "  Quantization:" -ForegroundColor White
    if ($f.Name -match "IQ4_NL") { Write-Host "    Type   : IQ4_NL (4-bit Imatrix) - creative/adult content" -ForegroundColor Yellow }
    if ($f.Name -match "Q5_1")   { Write-Host "    Type   : Q5_1 (5-bit) - balanced general use" -ForegroundColor Green }
    if ($f.Name -match "Q8_0")   { Write-Host "    Type   : Q8_0 (8-bit) - highest quality" -ForegroundColor Magenta }
    if ($f.Name -match "TRI")    { Write-Host "    Matrix : TRI-Matrix (3 datasets averaged)" }
    elseif ($f.Name -match "-DI-") { Write-Host "    Matrix : DI-Matrix (2 datasets averaged)" }
    else                          { Write-Host "    Matrix : Standard Imatrix" }
    if ($f.Name -match "CODE")   { Write-Host "    Special: Code generation enhanced" -ForegroundColor Cyan }

    Write-Host ""
    Write-Host "  Recommended params:" -ForegroundColor White
    Write-Host "    --ctx-size 8192  --temp 0.8  --repeat-penalty 1.1"
    Write-Host "    --top-k 40  --top-p 0.95  --min-p 0.05"
    Write-Host ""

    $s = Read-Host "Compute SHA256? (y/N)"
    if ($s -eq "y") {
        info "Computing SHA256..."
        $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
        Write-Host "  SHA256: $hash" -ForegroundColor DarkGray
    }

    Write-Host ""; Read-Host "Press Enter to return"
}

# --- delete model ---
function Remove-ModelFile {
    Clear-Host
    Write-Host ""; Write-Host "=== Delete Model ===" -ForegroundColor Cyan; Write-Host ""

    $files = Get-Models
    if ($files.Count -eq 0) { warn "No models found."; Read-Host "Press Enter"; return }

    for ($i = 0; $i -lt $files.Count; $i++) {
        $mb = [math]::Round($files[$i].Length / 1MB, 1)
        Write-Host ("  [{0}] {1}  ({2} MB)" -f ($i+1), $files[$i].Name, $mb)
    }
    Write-Host ""
    $n = Read-Host "Select number to delete (0=cancel)"
    if ($n -eq "0" -or [string]::IsNullOrWhiteSpace($n)) { return }

    $idx = [int]$n - 1
    if ($idx -lt 0 -or $idx -ge $files.Count) { err "Invalid number"; Start-Sleep 2; return }

    $f  = $files[$idx]
    $mb = [math]::Round($f.Length / 1MB, 1)

    Write-Host ""
    warn "About to delete: $($f.Name)"
    warn "Size: ${mb} MB  (this cannot be undone)"
    Write-Host ""
    $c = Read-Host "Type YES to confirm"
    if ($c -ne "YES") { info "Cancelled."; Start-Sleep 1; return }

    Remove-Item $f.FullName -Force
    ok "Deleted: $($f.Name)"
    Start-Sleep 2
}

# --- disk info ---
function Show-Disk {
    Clear-Host
    Write-Host ""; Write-Host "=== Disk Space ===" -ForegroundColor Cyan; Write-Host ""

    $drive = Split-Path -Qualifier $ModelsDir
    $d = Get-PSDrive ($drive.TrimEnd(':'))
    $free  = [math]::Round($d.Free  / 1GB, 1)
    $used  = [math]::Round($d.Used  / 1GB, 1)
    $total = [math]::Round(($d.Used + $d.Free) / 1GB, 1)

    Write-Host ("  Drive : {0}" -f $drive)
    Write-Host ("  Total : {0} GB" -f $total)
    Write-Host ("  Used  : {0} GB" -f $used)
    Write-Host ("  Free  : " -f "") -NoNewline
    Write-Host ("{0} GB" -f $free) -ForegroundColor Green

    Write-Host ""
    Write-Host "  Space needed per quantization type:" -ForegroundColor White
    Write-Host "    IQ4_NL  ~12 GB"
    Write-Host "    Q5_1    ~16 GB"
    Write-Host "    Q8_0    ~22 GB"

    $files = Get-Models
    if ($files.Count -gt 0) {
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        $modelGB = [math]::Round($bytes / 1GB, 2)
        Write-Host ""
        Write-Host ("  Models dir: {0} models, {1} GB used" -f $files.Count, $modelGB)
    }

    Write-Host ""; Read-Host "Press Enter to return"
}

# --- clean temp files ---
function Clear-Temp {
    Clear-Host
    Write-Host ""; Write-Host "=== Clean Temp Files ===" -ForegroundColor Cyan; Write-Host ""

    $tmp = @(Get-ChildItem -Path $ModelsDir -Include "*.tmp","*.part","*.download","*.incomplete" -File -ErrorAction SilentlyContinue)

    if ($tmp.Count -eq 0) {
        info "No temp files found."
    } else {
        warn "$($tmp.Count) temp file(s) found:"
        foreach ($f in $tmp) {
            $mb = [math]::Round($f.Length / 1MB, 1)
            Write-Host ("    {0}  ({1} MB)" -f $f.Name, $mb)
        }
        Write-Host ""
        $c = Read-Host "Delete all? (y/N)"
        if ($c -eq "y") {
            foreach ($f in $tmp) { Remove-Item $f.FullName -Force; ok "Deleted: $($f.Name)" }
        } else {
            info "Cancelled."
        }
    }

    Write-Host ""; Read-Host "Press Enter to return"
}

# --- main menu ---
while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  GPT-OSS 20B Model Manager" -ForegroundColor White
    Write-Host "  Models: $ModelsDir" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $files = Get-Models
    $cnt = $files.Count
    if ($cnt -gt 0) {
        Write-Host ("  Downloaded: {0} model(s)" -f $cnt) -ForegroundColor Green
    } else {
        Write-Host "  Downloaded: none" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  [1] List all models"
    Write-Host "  [2] Model details"
    Write-Host "  [3] Delete a model"
    Write-Host "  [4] Disk space info"
    Write-Host "  [5] Clean temp files"
    Write-Host "  [0] Exit"
    Write-Host ""
    $choice = Read-Host "Select (0-5)"

    switch ($choice) {
        "1" { Show-List }
        "2" { Show-Info }
        "3" { Remove-ModelFile }
        "4" { Show-Disk }
        "5" { Clear-Temp }
        "0" { Write-Host ""; exit 0 }
        default { err "Invalid option"; Start-Sleep 1 }
    }
}

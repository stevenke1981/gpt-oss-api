# LAN Firewall Setup for llama-server (Windows)
# Opens the llama-server port on Windows Firewall for LAN access
# Usage: .\firewall.ps1
# Requires: Run as Administrator

param([int]$Port = 0)

function info  ($m) { Write-Host "[INFO]    $m" -ForegroundColor Cyan }
function ok    ($m) { Write-Host "[OK]      $m" -ForegroundColor Green }
function warn  ($m) { Write-Host "[WARN]    $m" -ForegroundColor Yellow }
function die   ($m) { Write-Host "[ERROR]   $m" -ForegroundColor Red; Read-Host "Press Enter to exit"; exit 1 }

# --- check admin ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    warn "Not running as Administrator."
    warn "Re-launching with elevated privileges..."
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$ConfigFile = Join-Path $RootDir "config\settings.ini"
$RuleName   = "llama-server LAN"

# read port from config if not passed
if ($Port -eq 0) {
    if (Test-Path $ConfigFile) {
        $line = Get-Content $ConfigFile | Where-Object { $_ -match '^PORT\s*=' } | Select-Object -First 1
        if ($line) { $Port = [int]($line -split '=')[1].Trim() }
    }
    if ($Port -eq 0) { $Port = 8080 }
}

Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  llama-server LAN Firewall Setup" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# --- show local IPs ---
info "This machine's LAN IP addresses:"
$ips = Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.PrefixOrigin -ne 'WellKnown' } |
       Select-Object IPAddress, InterfaceAlias
foreach ($ip in $ips) {
    Write-Host ("    {0,-18} ({1})" -f $ip.IPAddress, $ip.InterfaceAlias) -ForegroundColor Green
}
Write-Host ""
info "Port to open: $Port"
Write-Host ""

# --- check existing rule ---
$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existing) {
    $existPort = ($existing | Get-NetFirewallPortFilter).LocalPort
    warn "Firewall rule already exists (port: $existPort)"
    $update = Read-Host "Update to port $Port ? (y/N)"
    if ($update -ne "y") { info "No changes made."; Read-Host "Press Enter to exit"; exit 0 }
    Remove-NetFirewallRule -DisplayName $RuleName
    info "Old rule removed."
}

# --- add inbound rule ---
New-NetFirewallRule `
    -DisplayName  $RuleName `
    -Direction    Inbound `
    -Protocol     TCP `
    -LocalPort    $Port `
    -Action       Allow `
    -Profile      Private,Domain `
    -Description  "Allow LAN access to llama-server API" | Out-Null

ok "Firewall rule added: '$RuleName'  TCP $Port  (Private + Domain networks)"

# --- update config bind address ---
Write-Host ""
info "Updating config HOST to 0.0.0.0 for LAN binding..."
if (Test-Path $ConfigFile) {
    $content = Get-Content $ConfigFile
    $updated = $content -replace '^HOST\s*=.*', 'HOST=0.0.0.0'
    Set-Content $ConfigFile $updated
    ok "config/settings.ini: HOST=0.0.0.0"
} else {
    warn "config/settings.ini not found. Set HOST manually in serve.ps1."
}

# --- summary ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Setup Complete" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  LAN clients can now connect to:" -ForegroundColor White
foreach ($ip in $ips) {
    Write-Host ("    http://{0}:{1}" -f $ip.IPAddress, $Port) -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  To revert (block LAN access):" -ForegroundColor DarkGray
Write-Host ("    Remove-NetFirewallRule -DisplayName '{0}'" -f $RuleName) -ForegroundColor DarkGray
Write-Host ""

Read-Host "Press Enter to exit"

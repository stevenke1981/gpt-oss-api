# llama.cpp Pre-built Installer (Windows PowerShell)
# Downloads the latest release from GitHub and installs llama-server
# Usage: .\install_llama.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Split-Path -Parent $ScriptDir
$InstallDir = Join-Path $RootDir "llama.cpp"
$API_URL    = "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"

function info  ($m) { Write-Host "[INFO]    $m" -ForegroundColor Cyan }
function ok    ($m) { Write-Host "[OK]      $m" -ForegroundColor Green }
function warn  ($m) { Write-Host "[WARN]    $m" -ForegroundColor Yellow }
function die   ($m) { Write-Host "[ERROR]   $m" -ForegroundColor Red; Read-Host "Press Enter to exit"; exit 1 }
function step  ($m) { Write-Host ""; Write-Host ">>> $m" -ForegroundColor White }

# --- detect GPU ---
function Get-GpuBackend {
    # NVIDIA
    if (Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue) {
        try {
            $out = & nvidia-smi.exe --query-gpu=name,driver_version --format=csv,noheader 2>$null
            if ($out) {
                $driverVer = (& nvidia-smi.exe --query-gpu=driver_version --format=csv,noheader 2>$null).Trim()
                # CUDA 13 needs driver >= 576, CUDA 12 needs driver >= 527
                $major = [int]($driverVer -split '\.')[0]
                if ($major -ge 576) { return "cuda13" }
                if ($major -ge 527) { return "cuda12" }
                return "cuda12"
            }
        } catch {}
    }
    # AMD ROCm / HIP
    if (Get-Command "rocminfo.exe" -ErrorAction SilentlyContinue) { return "hip" }
    if (Test-Path "C:\Program Files\AMD\ROCm") { return "hip" }
    # Intel Arc / SYCL
    if (Get-Command "ocloc.exe" -ErrorAction SilentlyContinue) { return "sycl" }
    # Vulkan fallback (most modern GPUs)
    $vk = Get-ItemProperty "HKLM:\SOFTWARE\Khronos\Vulkan\Drivers" -ErrorAction SilentlyContinue
    if ($vk) { return "vulkan" }
    return "cpu"
}

function Get-BackendLabel ($backend) {
    switch ($backend) {
        "cuda13"  { return "NVIDIA GPU (CUDA 13.x — driver >= 576)" }
        "cuda12"  { return "NVIDIA GPU (CUDA 12.x — driver >= 527)" }
        "hip"     { return "AMD GPU (ROCm / HIP)" }
        "sycl"    { return "Intel Arc GPU (SYCL)" }
        "vulkan"  { return "Vulkan (generic GPU)" }
        "cpu"     { return "CPU only (no GPU detected)" }
        default   { return $backend }
    }
}

# --- fetch latest release info from GitHub ---
function Get-LatestRelease {
    step "Fetching latest release info from GitHub"
    try {
        $rel = Invoke-RestMethod -Uri $API_URL -UseBasicParsing -Headers @{ "User-Agent" = "llama-installer" }
        return $rel
    } catch {
        die "Failed to reach GitHub API: $_"
    }
}

function Get-AssetUrl ($assets, $backend) {
    $pattern = switch ($backend) {
        "cuda13"  { "win-cuda-13" }
        "cuda12"  { "win-cuda-12" }
        "hip"     { "win-hip" }
        "sycl"    { "win-sycl" }
        "vulkan"  { "win-vulkan-x64" }
        "cpu"     { "win-cpu-x64" }
        default   { "win-cpu-x64" }
    }
    # Must start with "llama-b" to exclude cudart-* and other auxiliary packages
    $asset = $assets | Where-Object {
        $_.name -like "llama-b*" -and
        $_.name -like "*$pattern*" -and
        $_.name -like "*.zip"
    } | Select-Object -First 1
    return $asset
}

# --- download with progress ---
function Get-FileWithProgress ($url, $dest) {
    info "Downloading: $(Split-Path -Leaf $dest)"
    info "From: $url"

    # Try curl first (faster, shows progress bar)
    if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
        curl.exe -L --progress-bar "$url" -o "$dest"
        return
    }
    # Fallback: Invoke-WebRequest
    $ProgressPreference = "Continue"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

# --- extract zip ---
function Expand-Release ($zipPath, $targetDir) {
    step "Extracting to $targetDir"
    if (Test-Path $targetDir) {
        warn "Directory already exists: $targetDir"
        $ow = Read-Host "Overwrite? (y/N)"
        if ($ow -ne "y") { info "Skipping extraction"; return }
        Remove-Item $targetDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $targetDir | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $targetDir -Force
    ok "Extracted successfully"
}

# --- find llama-server in extracted dir ---
function Find-ServerBin ($dir) {
    $bin = Get-ChildItem -Path $dir -Recurse -Filter "llama-server.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bin) { return $bin.FullName }
    return $null
}

# --- verify installation ---
function Test-Installation ($binPath) {
    step "Verifying installation"
    try {
        $ver = & "$binPath" --version 2>&1 | Select-Object -First 1
        ok "llama-server works: $ver"
    } catch {
        warn "Could not run llama-server: $_"
    }
}

# --- main ---
Clear-Host
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  llama.cpp Pre-built Installer (Windows)" -ForegroundColor White
Write-Host "  Source: github.com/ggml-org/llama.cpp/releases" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: detect backend
step "Detecting hardware"
$backend = Get-GpuBackend
$label   = Get-BackendLabel $backend
info "Detected: $label"

# Show GPU detail if NVIDIA
if ($backend -in @("cuda12","cuda13")) {
    try {
        $gpuName = (& nvidia-smi.exe --query-gpu=name --format=csv,noheader 2>$null).Trim()
        info "GPU: $gpuName"
    } catch {}
}

# Allow manual override
Write-Host ""
Write-Host "  Available variants:" -ForegroundColor White
Write-Host "    [1] cpu      - CPU only (all machines)"       -ForegroundColor DarkGray
Write-Host "    [2] vulkan   - Vulkan GPU (most modern GPUs)" -ForegroundColor DarkGray
Write-Host "    [3] cuda12   - NVIDIA CUDA 12.x"              -ForegroundColor DarkGray
Write-Host "    [4] cuda13   - NVIDIA CUDA 13.x"              -ForegroundColor DarkGray
Write-Host "    [5] hip      - AMD ROCm / HIP"                -ForegroundColor DarkGray
Write-Host "    [6] sycl     - Intel Arc GPU"                 -ForegroundColor DarkGray
Write-Host ""
$override = Read-Host "Override auto-detected '$backend'? [1-6 or Enter to keep]"
switch ($override) {
    "1" { $backend = "cpu" }
    "2" { $backend = "vulkan" }
    "3" { $backend = "cuda12" }
    "4" { $backend = "cuda13" }
    "5" { $backend = "hip" }
    "6" { $backend = "sycl" }
}
info "Using backend: $backend ($(Get-BackendLabel $backend))"

# Step 2: fetch release
$release = Get-LatestRelease
$tag     = $release.tag_name
$asset   = Get-AssetUrl $release.assets $backend

if (-not $asset) {
    die "No matching asset found for backend '$backend' in release $tag.`nCheck manually: https://github.com/ggml-org/llama.cpp/releases"
}

$zipName  = $asset.name
$zipUrl   = $asset.browser_download_url
$sizeMB   = [math]::Round($asset.size / 1MB, 1)

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ("  Release : {0}" -f $tag)
Write-Host ("  Package : {0}" -f $zipName)
Write-Host ("  Size    : {0} MB" -f $sizeMB)
Write-Host ("  Install : {0}" -f $InstallDir)
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$go = Read-Host "Proceed? (Y/n)"
if ($go -eq "n") { exit 0 }

# Step 3: download
$tmpZip = Join-Path $env:TEMP $zipName
if (Test-Path $tmpZip) {
    warn "Temp file exists: $tmpZip"
    $reuse = Read-Host "Use cached download? (Y/n)"
    if ($reuse -eq "n") { Remove-Item $tmpZip -Force }
}

if (-not (Test-Path $tmpZip)) {
    step "Downloading $zipName"
    Get-FileWithProgress $zipUrl $tmpZip
    ok "Downloaded: $tmpZip"
} else {
    ok "Using cached: $tmpZip"
}

# Step 4: extract
Expand-Release $tmpZip $InstallDir

# Step 5: find binary
$serverBin = Find-ServerBin $InstallDir
if (-not $serverBin) {
    die "llama-server.exe not found in extracted files."
}
ok "llama-server: $serverBin"

# Step 6: verify
Test-Installation $serverBin

# Step 7: CUDA runtime check
if ($backend -in @("cuda12","cuda13")) {
    step "Checking CUDA runtime DLLs"
    $cudaDlls = @("cublas64_12.dll","cublas64_13.dll","cublasLt64_12.dll","cublasLt64_13.dll")
    $serverDir = Split-Path -Parent $serverBin
    $hasCuda = $cudaDlls | Where-Object { Test-Path (Join-Path $serverDir $_) }
    if ($hasCuda) {
        ok "CUDA runtime DLLs bundled in package"
    } else {
        warn "CUDA DLLs not found next to binary."
        info "If server fails, install CUDA Toolkit or copy cuBLAS DLLs:"
        Write-Host "  https://developer.nvidia.com/cuda-downloads" -ForegroundColor DarkGray
    }
}

# Summary
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
Write-Host ("  Release  : {0}" -f $tag)
Write-Host ("  Backend  : {0}" -f (Get-BackendLabel $backend))
Write-Host ("  Binary   : {0}" -f $serverBin)
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    .\download.ps1    download a GGUF model"
Write-Host "    .\serve.ps1       start the API server"
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Read-Host "Press Enter to exit"

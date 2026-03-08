# download-llama-cpp.ps1 — Download and extract llama.cpp Vulkan build for Windows
# Automatically fetches the latest release from GitHub with integrity verification

$ErrorActionPreference = "Stop"

# ── Load Configuration ─────────────────────────────────────────────────────────
$ConfigPath = Join-Path $PSScriptRoot "config.ps1"

if (-not (Test-Path $ConfigPath)) {
    Write-Error @"
Configuration file not found: $ConfigPath

Please create a configuration file first:
  1. Interactive: .\setup-config.ps1
  2. Manual:      cp config.ps1.example config.ps1
"@
    exit 1
}

# Load configuration
. $ConfigPath

$InstallDir = $LocalAIConfig.LlamaCppDir
$TempDir = "$env:TEMP\llama-cpp-download"

Write-Host "=== llama.cpp Vulkan Downloader ===" -ForegroundColor Cyan
Write-Host ""

# Check disk space (require at least 1 GB free)
$MinFreeSpaceGB = 1
$Drive = Split-Path $InstallDir -Qualifier
if ($Drive) {
    $DriveInfo = Get-PSDrive ($Drive.TrimEnd(':'))
    $FreeSpaceGB = [math]::Round($DriveInfo.Free / 1GB, 2)
    
    Write-Host "[security] Checking disk space on $Drive..." -ForegroundColor Yellow
    Write-Host "  Available: $FreeSpaceGB GB" -ForegroundColor Gray
    
    if ($FreeSpaceGB -lt $MinFreeSpaceGB) {
        Write-Error "Insufficient disk space. Need at least $MinFreeSpaceGB GB free, have $FreeSpaceGB GB."
        exit 1
    }
    Write-Host "  [ok] Sufficient disk space available" -ForegroundColor Green
}
Write-Host ""

# Create temp directory
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# Fetch latest release info from GitHub API
Write-Host "[1/5] Fetching latest release info from GitHub..." -ForegroundColor Yellow
try {
    $releaseUrl = "https://api.github.com/repos/ggerganov/llama.cpp/releases/latest"
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ "User-Agent" = "PowerShell" }
    
    # Validate response
    if (-not $release.tag_name) {
        throw "Invalid release response from GitHub API"
    }
    
    Write-Host "  Latest release: $($release.tag_name) ($($release.name))" -ForegroundColor Green
    Write-Host "  Published: $($release.published_at)" -ForegroundColor Gray
    Write-Host "  [security] Verify release at: https://github.com/ggerganov/llama.cpp/releases/latest" -ForegroundColor Yellow
} catch {
    Write-Host "  [failed] Could not fetch release info from GitHub" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}

# Find the Vulkan build asset
Write-Host ""
Write-Host "[2/5] Looking for Vulkan build..." -ForegroundColor Yellow
$vulkanAsset = $release.assets | Where-Object { 
    $_.name -match "vulkan-x64\.zip$" -or $_.name -match "bin-win-vulkan-x64\.zip$"
} | Select-Object -First 1

if (-not $vulkanAsset) {
    Write-Host "  [failed] Could not find Vulkan build in release assets" -ForegroundColor Red
    Write-Host "  Available assets:" -ForegroundColor Yellow
    $release.assets | ForEach-Object { Write-Host "    - $($_.name)" }
    exit 1
}

# Validate asset data
if (-not $vulkanAsset.browser_download_url -or -not $vulkanAsset.size) {
    Write-Error "Invalid asset data received from GitHub API"
    exit 1
}

Write-Host "  Found: $($vulkanAsset.name) ($([math]::Round($vulkanAsset.size / 1MB, 2)) MB)" -ForegroundColor Green
Write-Host "  [info] Asset URL: $($vulkanAsset.browser_download_url)" -ForegroundColor Gray

# Download the asset
Write-Host ""
Write-Host "[3/5] Downloading llama.cpp..." -ForegroundColor Yellow
$downloadPath = Join-Path $TempDir $vulkanAsset.name

try {
    # Check if already downloaded
    if (Test-Path $downloadPath) {
        $existingSize = (Get-Item $downloadPath).Length
        if ($existingSize -eq $vulkanAsset.size) {
            Write-Host "  [skip] Already downloaded: $downloadPath" -ForegroundColor Gray
        } else {
            Write-Host "  Incomplete download found, re-downloading..." -ForegroundColor Yellow
            Remove-Item $downloadPath -Force
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $vulkanAsset.browser_download_url -Destination $downloadPath -Description "Downloading $($vulkanAsset.name)"
        }
    } else {
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $vulkanAsset.browser_download_url -Destination $downloadPath -Description "Downloading $($vulkanAsset.name)"
    }
    
    # Verify file size after download
    $actualSize = (Get-Item $downloadPath).Length
    if ($actualSize -ne $vulkanAsset.size) {
        Write-Error "Downloaded file size mismatch!"
        Write-Error "  Expected: $($vulkanAsset.size) bytes"
        Write-Error "  Actual:   $actualSize bytes"
        Remove-Item $downloadPath -Force
        exit 1
    }
    
    Write-Host "  [done] Downloaded and verified: $downloadPath" -ForegroundColor Green
} catch {
    Write-Host "  [failed] Download error" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    
    # Clean up partial download
    if (Test-Path $downloadPath) {
        Remove-Item $downloadPath -Force
    }
    exit 1
}

# Extract to install directory
Write-Host ""
Write-Host "[4/5] Extracting to $InstallDir..." -ForegroundColor Yellow

# Check if directory already exists
if (Test-Path $InstallDir) {
    Write-Host "  Directory already exists. Contents:" -ForegroundColor Yellow
    Get-ChildItem $InstallDir -File | Select-Object -First 5 | ForEach-Object { 
        Write-Host "    - $($_.Name)" -ForegroundColor Gray
    }
    Write-Host ""
    $ans = Read-Host "  Overwrite existing installation? [y/N]"
    if ($ans -ne 'y') {
        Write-Host "  [aborted] Keeping existing installation" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Cleanup: Remove-Item -Recurse -Force '$TempDir'" -ForegroundColor Gray
        exit 0
    }
    Write-Host "  Removing old installation..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $InstallDir
}

try {
    # Create install directory
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    
    # Extract zip
    Write-Host "  Extracting archive..." -ForegroundColor Yellow
    Expand-Archive -Path $downloadPath -DestinationPath $TempDir -Force
    
    # The zip often contains a subdirectory; find and move contents
    $extractedDirs = Get-ChildItem -Path $TempDir -Directory | Where-Object { $_.Name -like "*llama*" }
    
    if ($extractedDirs) {
        # Move from subdirectory to install dir
        $sourceDir = $extractedDirs[0].FullName
        Write-Host "  Moving files from: $($extractedDirs[0].Name)" -ForegroundColor Gray
        Get-ChildItem -Path $sourceDir | Move-Item -Destination $InstallDir -Force
    } else {
        # No subdirectory, but files might be in temp root (less common)
        Get-ChildItem -Path $TempDir -File | Move-Item -Destination $InstallDir -Force
    }
    
    Write-Host "  [done] Extracted to: $InstallDir" -ForegroundColor Green
} catch {
    Write-Host "  [failed] Extraction error" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}

# Verify key files
Write-Host ""
Write-Host "[5/5] Verifying installation..." -ForegroundColor Yellow
$keyFiles = @("llama-server.exe", "ggml-vulkan.dll")
$allPresent = $true

foreach ($file in $keyFiles) {
    $path = Join-Path $InstallDir $file
    if (Test-Path $path) {
        $fileSize = [math]::Round((Get-Item $path).Length / 1MB, 2)
        Write-Host "  [OK] $file ($fileSize MB)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $file" -ForegroundColor Red
        $allPresent = $false
    }
}

# Cleanup temp files
Write-Host ""
Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
Write-Host "  [done]" -ForegroundColor Green

# Summary
Write-Host ""
if ($allPresent) {
    Write-Host "=== Installation complete! ===" -ForegroundColor Green
    Write-Host "llama.cpp is installed at: $InstallDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[security] Recommendations:" -ForegroundColor Yellow
    Write-Host "  - Verify the GitHub release: https://github.com/ggerganov/llama.cpp/releases/$($release.tag_name)" -ForegroundColor Gray
    Write-Host "  - Monitor security advisories: https://github.com/ggerganov/llama.cpp/security/advisories" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Download models: .\download-models.ps1" -ForegroundColor White
    Write-Host "  2. Start the backend: .\start-backend-windows.ps1" -ForegroundColor White
    exit 0
} else {
    Write-Host "=== Installation completed with warnings ===" -ForegroundColor Yellow
    Write-Host "Some expected files are missing. Check the installation at: $InstallDir" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

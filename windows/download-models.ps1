# download-models.ps1 — Download recommended GGUF models for Windows
# Downloads GGUF models to configured models directory with integrity verification

$ErrorActionPreference = "Stop"

# ── Load Configuration ─────────────────────────────────────────────────────────
$ConfigPath = Join-Path $PSScriptRoot "config.ps1"
$ChecksumsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "checksums.txt"

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

$ModelsDir = $LocalAIConfig.ModelsDir

Write-Host "=== Model Downloader for Windows ===" -ForegroundColor Cyan
Write-Host ""

# Load checksums if available (format: sha256 filename)
$Checksums = @{}
if (Test-Path $ChecksumsPath) {
    try {
        Get-Content $ChecksumsPath | ForEach-Object {
            # Skip comments and empty lines
            if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
            
            # Parse "sha256 filename" format
            if ($_ -match '^([a-fA-F0-9]{64})\s+(.+)$') {
                $hash = $matches[1]
                $filename = $matches[2].Trim()
                $Checksums[$filename] = $hash
            }
            elseif ($_ -match '^([^\s]+)\s+VERIFY_AFTER_DOWNLOAD$') {
                # Placeholder format - skip for now
                $filename = $matches[1]
                $Checksums[$filename] = $null
            }
        }
        
        if ($Checksums.Count -gt 0) {
            Write-Host "[info] Loaded $($Checksums.Count) checksum(s) from checksums.txt" -ForegroundColor Gray
        }
        else {
            Write-Warning "checksums.txt found but no valid checksums loaded. Add hashes to enable verification."
        }
    }
    catch {
        Write-Warning "Could not parse checksums.txt. File integrity verification will be limited."
        Write-Warning "Error: $_"
        $Checksums = @{}
    }
}
else {
    Write-Warning "checksums.txt not found at: $ChecksumsPath"
    Write-Warning "Skipping hash verification. See README for checksum instructions."
}
Write-Host ""

# Check disk space (require at least 15 GB free)
$MinFreeSpaceGB = 15
$Drive = Split-Path $ModelsDir -Qualifier
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

# Create models directory if it doesn't exist
if (-not (Test-Path $ModelsDir)) {
    Write-Host "[1/4] Creating models directory: $ModelsDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ModelsDir -Force | Out-Null
}
else {
    Write-Host "[1/4] Models directory exists: $ModelsDir" -ForegroundColor Green
}
Write-Host ""

# Helper function to verify file integrity
function Test-FileIntegrity {
    param(
        [string]$FilePath,
        [string]$FileName
    )
    
    $ExpectedHash = $Checksums[$FileName]
    
    if (-not $ExpectedHash) {
        Write-Warning "No checksum available for $FileName"
        Write-Host "  [info] To enable verification, update checksums.txt with:" -ForegroundColor Gray
        Write-Host "  (Get-FileHash -Path `"$FilePath`" -Algorithm SHA256).Hash" -ForegroundColor Gray
        return $true
    }
    
    Write-Host "  [security] Verifying file integrity..." -ForegroundColor Yellow
    
    # Check SHA256 hash
    Write-Host "  Calculating SHA256 hash (this may take a minute)..." -ForegroundColor Gray
    $ActualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    
    if ($ActualHash -ne $ExpectedHash) {
        Write-Error "SHA256 hash mismatch for $FileName!"
        Write-Error "  Expected: $ExpectedHash"
        Write-Error "  Actual:   $ActualHash"
        Write-Error "File may be corrupted or tampered with."
        return $false
    }
    Write-Host "  [ok] SHA256 hash verified" -ForegroundColor Green
    
    return $true
}

# Helper function to download a model
function Download-Model {
    param(
        [string]$Url,
        [string]$FileName
    )
    
    $FilePath = Join-Path $ModelsDir $FileName
    
    if (Test-Path $FilePath) {
        Write-Host "  [skip] $FileName already exists." -ForegroundColor Gray
        
        # Still verify integrity if it exists
        if ($Checksums.ContainsKey($FileName)) {
            if (-not (Test-FileIntegrity -FilePath $FilePath -FileName $FileName)) {
                Write-Error "Integrity check failed for existing file: $FileName"
                exit 1
            }
        }
    }
    else {
        Write-Host "  Downloading $FileName..." -ForegroundColor Yellow
        Write-Host "  URL: $Url" -ForegroundColor Gray
        
        try {
            # Use BITS transfer for resumable downloads (better for large files)
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $Url -Destination $FilePath -Description "Downloading $FileName"
            Write-Host "  [done] $FileName downloaded" -ForegroundColor Green
            
            # Verify integrity after download
            if ($Checksums.ContainsKey($FileName)) {
                if (-not (Test-FileIntegrity -FilePath $FilePath -FileName $FileName)) {
                    Write-Error "Integrity check failed for downloaded file: $FileName"
                    Remove-Item $FilePath -Force
                    exit 1
                }
            }
        }
        catch {
            Write-Host "  [failed] Could not download $FileName" -ForegroundColor Red
            Write-Host "  Error: $_" -ForegroundColor Red
            
            # Clean up partial download
            if (Test-Path $FilePath) {
                Remove-Item $FilePath -Force
            }
            throw
        }
    }
}

# Download CodeLlama 13B Q4 (code completion & chat, ~7.3 GB)
Write-Host "[2/4] Downloading CodeLlama 13B..." -ForegroundColor Yellow
Download-Model `
    -Url $LocalAIConfig.CodeLlamaUrl `
    -FileName $LocalAIConfig.CompletionModel

Write-Host ""

# Download Mistral 7B Instruct Q4 (fast general chat, ~4.4 GB)
Write-Host "[3/4] Downloading Mistral 7B Instruct..." -ForegroundColor Yellow
Download-Model `
    -Url $LocalAIConfig.MistralUrl `
    -FileName $LocalAIConfig.ChatModel

Write-Host ""
Write-Host "[4/4] Security recommendations:" -ForegroundColor Yellow
Write-Host "  - Verify model hashes match official sources" -ForegroundColor Gray
Write-Host "  - See checksums.txt for hash information" -ForegroundColor Gray
Write-Host "  - Report mismatches at: https://github.com/ggerganov/llama.cpp/security" -ForegroundColor Gray
Write-Host ""
Write-Host "=== Download complete! ===" -ForegroundColor Green
Write-Host "Models are in: $ModelsDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Verify files: Get-ChildItem `"$ModelsDir`"" -ForegroundColor White
Write-Host "  2. Start the backend: .\start-backend-windows.ps1" -ForegroundColor White
Write-Host ""

exit 0

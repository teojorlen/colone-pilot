# test-installation.ps1 — Validate Windows Installation
# Verifies that the local AI setup is properly configured

$ErrorActionPreference = "Stop"

Write-Host "=== LocalAI Installation Test ===" -ForegroundColor Cyan
Write-Host ""

$TestsPassed = 0
$TestsFailed = 0
$TestsWarning = 0

# ── Helper Functions ───────────────────────────────────────────────────────────

function Test-Result {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [bool]$IsWarning = $false
    )
    
    if ($Passed) {
        Write-Host "  [✓] $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "      $Message" -ForegroundColor Gray }
        $script:TestsPassed++
    }
    elseif ($IsWarning) {
        Write-Host "  [!] $TestName" -ForegroundColor Yellow
        if ($Message) { Write-Host "      $Message" -ForegroundColor Gray }
        $script:TestsWarning++
    }
    else {
        Write-Host "  [✗] $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "      $Message" -ForegroundColor Gray }
        $script:TestsFailed++
    }
}

# ── Test 1: Configuration File ────────────────────────────────────────────────
Write-Host "[1/7] Testing configuration..." -ForegroundColor Yellow

$ConfigPath = Join-Path $PSScriptRoot "config.ps1"

if (Test-Path $ConfigPath) {
    Test-Result "config.ps1 exists" $true
    
    try {
        . $ConfigPath
        Test-Result "config.ps1 loads successfully" $true
        
        # Verify required settings
        if ($LocalAIConfig) {
            Test-Result "LocalAIConfig variable defined" $true
            
            $RequiredKeys = @('BaseDir', 'ModelsDir', 'LlamaCppDir', 'ChatModel', 'CompletionModel')
            $MissingKeys = @()
            
            foreach ($key in $RequiredKeys) {
                if (-not $LocalAIConfig.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($LocalAIConfig[$key])) {
                    $MissingKeys += $key
                }
            }
            
            if ($MissingKeys.Count -eq 0) {
                Test-Result "All required configuration keys present" $true
            }
            else {
                Test-Result "Required configuration keys" $false "Missing: $($MissingKeys -join ', ')"
            }
        }
        else {
            Test-Result "LocalAIConfig variable" $false "Variable not found in config.ps1"
        }
    }
    catch {
        Test-Result "Load config.ps1" $false "Error: $_"
    }
}
else {
    Test-Result "config.ps1 exists" $false "Run .\setup-config.ps1 to create"
    Write-Host ""
    Write-Host "Cannot continue without configuration. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""

# ── Test 2: Directory Structure ───────────────────────────────────────────────
Write-Host "[2/7] Testing directories..." -ForegroundColor Yellow

$BaseDir = $LocalAIConfig.BaseDir
$ModelsDir = $LocalAIConfig.ModelsDir
$LlamaCppDir = $LocalAIConfig.LlamaCppDir

Test-Result "Base directory exists" (Test-Path $BaseDir) "Path: $BaseDir"
Test-Result "Models directory exists" (Test-Path $ModelsDir) "Path: $ModelsDir"
Test-Result "llama.cpp directory exists" (Test-Path $LlamaCppDir) "Path: $LlamaCppDir"

# Check if directories are writable
try {
    $TestFile = Join-Path $BaseDir "test-write.tmp"
    "test" | Out-File $TestFile -Force
    Remove-Item $TestFile -Force
    Test-Result "Base directory is writable" $true
}
catch {
    Test-Result "Base directory writable" $false "Error: $_"
}

Write-Host ""

# ── Test 3: Model Files ────────────────────────────────────────────────────────
Write-Host "[3/7] Testing model files..." -ForegroundColor Yellow

$ChatModel = $LocalAIConfig.ChatModel
$CompletionModel = $LocalAIConfig.CompletionModel

$ChatModelPath = Join-Path $ModelsDir $ChatModel
$CompletionModelPath = Join-Path $ModelsDir $CompletionModel

if (Test-Path $ChatModelPath) {
    $ChatModelSize = (Get-Item $ChatModelPath).Length / 1GB
    Test-Result "Chat model exists: $ChatModel" $true "Size: $([math]::Round($ChatModelSize, 2)) GB"
}
else {
    Test-Result "Chat model exists: $ChatModel" $false "Run .\download-models.ps1"
}

if (Test-Path $CompletionModelPath) {
    $CompletionModelSize = (Get-Item $CompletionModelPath).Length / 1GB
    Test-Result "Completion model exists: $CompletionModel" $true "Size: $([math]::Round($CompletionModelSize, 2)) GB"
}
else {
    Test-Result "Completion model exists: $CompletionModel" $false "Run .\download-models.ps1"
}

Write-Host ""

# ── Test 4: llama.cpp Binaries ─────────────────────────────────────────────────
Write-Host "[4/7] Testing llama.cpp binaries..." -ForegroundColor Yellow

$LlamaServerPath = Join-Path $LlamaCppDir "llama-server.exe"
$VulkanDllPath = Join-Path $LlamaCppDir "ggml-vulkan.dll"

Test-Result "llama-server.exe exists" (Test-Path $LlamaServerPath) "Path: $LlamaServerPath"
Test-Result "ggml-vulkan.dll exists" (Test-Path $VulkanDllPath) "Path: $VulkanDllPath"

# Check if llama-server is executable
if (Test-Path $LlamaServerPath) {
    try {
        $VersionCheck = & $LlamaServerPath --version 2>&1
        if ($LASTEXITCODE -eq 0 -or $VersionCheck -match "llama") {
            Test-Result "llama-server.exe is executable" $true
        }
        else {
            Test-Result "llama-server.exe executable" $false "Cannot run binary"
        }
    }
    catch {
        Test-Result "llama-server.exe executable" $false "Error: $_"
    }
}

Write-Host ""

# ── Test 5: Port Availability ─────────────────────────────────────────────────
Write-Host "[5/7] Testing port availability..." -ForegroundColor Yellow

$ChatPort = $LocalAIConfig.ChatPort
$CompletionPort = $LocalAIConfig.CompletionPort

function Test-PortAvailable {
    param([int]$Port)
    
    try {
        $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $Listener.Start()
        $Listener.Stop()
        return $true
    }
    catch {
        return $false
    }
}

$ChatPortAvailable = Test-PortAvailable -Port $ChatPort
$CompletionPortAvailable = Test-PortAvailable -Port $CompletionPort

Test-Result "Chat port $ChatPort available" $ChatPortAvailable "$(if (-not $ChatPortAvailable) { 'Port already in use' })"
Test-Result "Completion port $CompletionPort available" $CompletionPortAvailable "$(if (-not $CompletionPortAvailable) { 'Port already in use' })"

Write-Host ""

# ── Test 6: Checksums ──────────────────────────────────────────────────────────
Write-Host "[6/7] Testing checksum verification..." -ForegroundColor Yellow

$ChecksumsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "checksums.txt"

if (Test-Path $ChecksumsPath) {
    Test-Result "checksums.txt exists" $true
    
    # Parse checksums
    $ChecksumCount = 0
    $PlaceholderCount = 0
    
    Get-Content $ChecksumsPath | ForEach-Object {
        if ($_ -match '^([a-fA-F0-9]{64})\s+') {
            $ChecksumCount++
        }
        elseif ($_ -match 'VERIFY_AFTER_DOWNLOAD') {
            $PlaceholderCount++
        }
    }
    
    if ($ChecksumCount -gt 0) {
        Test-Result "Valid checksums found" $true "Count: $ChecksumCount"
    }
    else {
        Test-Result "Valid checksums" $false "Only placeholders found" -IsWarning $true
        Write-Host "      Update checksums.txt with actual SHA256 hashes" -ForegroundColor Gray
    }
}
else {
    Test-Result "checksums.txt exists" $false "File not found" -IsWarning $true
}

Write-Host ""

# ── Test 7: Disk Space ─────────────────────────────────────────────────────────
Write-Host "[7/7] Testing disk space..." -ForegroundColor Yellow

$Drive = Split-Path $BaseDir -Qualifier
if ($Drive) {
    $DriveInfo = Get-PSDrive ($Drive.TrimEnd(':'))
    $FreeSpaceGB = [math]::Round($DriveInfo.Free / 1GB, 2)
    $UsedSpaceGB = [math]::Round($DriveInfo.Used / 1GB, 2)
    $TotalSpaceGB = [math]::Round(($DriveInfo.Free + $DriveInfo.Used) / 1GB, 2)
    
    Write-Host "  Drive: $Drive" -ForegroundColor Gray
    Write-Host "  Total: $TotalSpaceGB GB" -ForegroundColor Gray
    Write-Host "  Used:  $UsedSpaceGB GB" -ForegroundColor Gray
    Write-Host "  Free:  $FreeSpaceGB GB" -ForegroundColor Gray
    
    $MinFreeSpaceGB = 10
    Test-Result "Sufficient disk space" ($FreeSpaceGB -ge $MinFreeSpaceGB) "Need at least $MinFreeSpaceGB GB free"
}
else {
    Test-Result "Check disk space" $false "Cannot determine drive"
}

Write-Host ""

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "  Passed:   $TestsPassed" -ForegroundColor Green
Write-Host "  Failed:   $TestsFailed" -ForegroundColor Red
Write-Host "  Warnings: $TestsWarning" -ForegroundColor Yellow
Write-Host ""

if ($TestsFailed -eq 0 -and $TestsWarning -eq 0) {
    Write-Host "✓ All tests passed! Installation is ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Start the backend: .\start-backend-windows.ps1" -ForegroundColor White
    Write-Host "  2. Or dual backend:   .\start-dual-backend.ps1" -ForegroundColor White
    exit 0
}
elseif ($TestsFailed -eq 0) {
    Write-Host "✓ All critical tests passed (some warnings)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Installation is functional but consider addressing warnings above." -ForegroundColor Gray
    exit 0
}
else {
    Write-Host "✗ Some tests failed. Please fix the issues above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:" -ForegroundColor Cyan
    Write-Host "  - Missing config:  .\setup-config.ps1" -ForegroundColor White
    Write-Host "  - Missing models:  .\download-models.ps1" -ForegroundColor White
    Write-Host "  - Missing binaries: .\download-llama-cpp.ps1" -ForegroundColor White
    exit 1
}

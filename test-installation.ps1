# test-installation.ps1
# Validation script for Local AI Windows installation
# Tests configuration loading, path validation, and script functionality

$ErrorActionPreference = "Stop"

$TestsPassed = 0
$TestsFailed = 0
$Warnings = 0

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Local AI Installation Test Suite (Windows)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

function Test-Passed {
    param([string]$Message)
    Write-Host "[✓] PASS: $Message" -ForegroundColor Green
    $script:TestsPassed++
}

function Test-Failed {
    param([string]$Message)
    Write-Host "[✗] FAIL: $Message" -ForegroundColor Red
    $script:TestsFailed++
}

function Test-Warning {
    param([string]$Message)
    Write-Host "[⚠] WARN: $Message" -ForegroundColor Yellow
    $script:Warnings++
}

# ── Test 1: Configuration File Exists ───────────────────────────────────────

Write-Host "[Test 1] Configuration file validation" -ForegroundColor Yellow
$ConfigPath = Join-Path $PSScriptRoot "windows\config.ps1"

if (Test-Path $ConfigPath) {
    Test-Passed "Configuration file exists: $ConfigPath"
    
    # Test: Can load configuration
    try {
        . $ConfigPath
        Test-Passed "Configuration file loads without errors"
    }
    catch {
        Test-Failed "Configuration file has syntax errors: $_"
    }
    
    # Test: Required keys present
    $requiredKeys = @(
        "BaseDir", "LlamaCppDir", "ModelsDir", "ChatModel", "CompletionModel",
        "GpuLayers", "Threads", "ChatContextSize", "CompletionContextSize",
        "ChatPort", "CompletionPort"
    )
    
    foreach ($key in $requiredKeys) {
        if ($LocalAIConfig.ContainsKey($key)) {
            Test-Passed "Config contains required key: $key"
        }
        else {
            Test-Failed "Config missing required key: $key"
        }
    }
}
else {
    Test-Failed "Configuration file not found: $ConfigPath"
    Test-Warning "Run .\windows\setup-config.ps1 to create configuration"
}

Write-Host ""

# ── Test 2: Path Validation ─────────────────────────────────────────────────

Write-Host "[Test 2] Path validation and security" -ForegroundColor Yellow

if ($LocalAIConfig) {
    # Test: Paths are absolute
    $paths = @{
        "BaseDir" = $LocalAIConfig.BaseDir
        "LlamaCppDir" = $LocalAIConfig.LlamaCppDir
        "ModelsDir" = $LocalAIConfig.ModelsDir
    }
    
    foreach ($pathName in $paths.Keys) {
        $path = $paths[$pathName]
        if ([System.IO.Path]::IsPathRooted($path)) {
            Test-Passed "$pathName is an absolute path: $path"
        }
        else {
            Test-Failed "$pathName is not an absolute path: $path"
        }
    }
    
    # Test: No hardcoded personal paths
    $personalPaths = @("C:\AI", "tjorl", "teo", "/home/teo")
    $foundPersonal = $false
    
    foreach ($key in $LocalAIConfig.Keys) {
        $value = $LocalAIConfig[$key]
        if ($value -is [string]) {
            foreach ($personalPath in $personalPaths) {
                if ($value -like "*$personalPath*") {
                    Test-Failed "Found hardcoded path '$personalPath' in $key"
                    $foundPersonal = $true
                }
            }
        }
    }
    
    if (-not $foundPersonal) {
        Test-Passed "No hardcoded personal paths found in configuration"
    }
}

Write-Host ""

# ── Test 3: Parameter Validation ────────────────────────────────────────────

Write-Host "[Test 3] Parameter range validation" -ForegroundColor Yellow

if ($LocalAIConfig) {
    # Test: Port ranges
    $ports = @{
        "ChatPort" = $LocalAIConfig.ChatPort
        "CompletionPort" = $LocalAIConfig.CompletionPort
    }
    
    foreach ($portName in $ports.Keys) {
        $port = $ports[$portName]
        if ($port -ge 1024 -and $port -le 65535) {
            Test-Passed "$portName is in valid range: $port"
        }
        else {
            Test-Failed "$portName is outside valid range (1024-65535): $port"
        }
    }
    
    # Test: GPU layers
    if ($LocalAIConfig.GpuLayers -ge 0 -and $LocalAIConfig.GpuLayers -le 99) {
        Test-Passed "GpuLayers is in valid range: $($LocalAIConfig.GpuLayers)"
    }
    else {
        Test-Failed "GpuLayers is outside valid range (0-99): $($LocalAIConfig.GpuLayers)"
    }
    
    # Test: Context sizes
    $contexts = @{
        "ChatContextSize" = $LocalAIConfig.ChatContextSize
        "CompletionContextSize" = $LocalAIConfig.CompletionContextSize
    }
    
    foreach ($contextName in $contexts.Keys) {
        $context = $contexts[$contextName]
        if ($context -ge 128 -and $context -le 131072) {
            Test-Passed "$contextName is in valid range: $context"
        }
        else {
            Test-Failed "$contextName is outside valid range (128-131072): $context"
        }
    }
    
    # Test: Threads
    if ($LocalAIConfig.Threads -ge 1 -and $LocalAIConfig.Threads -le 256) {
        Test-Passed "Threads is in valid range: $($LocalAIConfig.Threads)"
    }
    else {
        Test-Failed "Threads is outside valid range (1-256): $($LocalAIConfig.Threads)"
    }
}

Write-Host ""

# ── Test 4: Script Loadability ──────────────────────────────────────────────

Write-Host "[Test 4] Script syntax validation" -ForegroundColor Yellow

$scripts = @(
    "windows\setup-config.ps1",
    "windows\start-backend-windows.ps1",
    "windows\start-dual-backend.ps1",
    "windows\download-llama-cpp.ps1",
    "windows\download-models.ps1",
    "windows\stop-backend-windows.ps1",
    "windows\install-autostart.ps1",
    "windows\install-autostart-dual.ps1",
    "windows\uninstall-windows.ps1"
)

foreach ($scriptPath in $scripts) {
    $fullPath = Join-Path $PSScriptRoot $scriptPath
    
    if (Test-Path $fullPath) {
        # Try to parse the script
        $errors = @()
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $fullPath -Raw), [ref]$errors)
        
        if ($errors.Count -eq 0) {
            Test-Passed "Script has valid syntax: $scriptPath"
        }
        else {
            Test-Failed "Script has syntax errors: $scriptPath"
            foreach ($error in $errors) {
                Write-Host "    $error" -ForegroundColor Gray
            }
        }
    }
    else {
        Test-Failed "Script not found: $scriptPath"
    }
}

Write-Host ""

# ── Test 5: Security Checks ─────────────────────────────────────────────────

Write-Host "[Test 5] Security validation" -ForegroundColor Yellow

# Test: .gitignore exists
$gitignorePath = Join-Path $PSScriptRoot ".gitignore"
if (Test-Path $gitignorePath) {
    Test-Passed ".gitignore file exists"
    
    $gitignoreContent = Get-Content $gitignorePath -Raw
    
    # Check for important exclusions
    $requiredExclusions = @("*.gguf", "config.ps1", "config.sh", ".env", "*.log")
    foreach ($exclusion in $requiredExclusions) {
        if ($gitignoreContent -like "*$exclusion*") {
            Test-Passed ".gitignore excludes: $exclusion"
        }
        else {
            Test-Warning ".gitignore missing exclusion: $exclusion"
        }
    }
}
else {
    Test-Failed ".gitignore file not found"
}

# Test: checksums.json exists
$checksumsPath = Join-Path $PSScriptRoot "checksums.json"
if (Test-Path $checksumsPath) {
    Test-Passed "checksums.json file exists"
    
    try {
        $checksums = Get-Content $checksumsPath -Raw | ConvertFrom-Json
        Test-Passed "checksums.json is valid JSON"
    }
    catch {
        Test-Failed "checksums.json has invalid JSON: $_"
    }
}
else {
    Test-Warning "checksums.json not found (optional but recommended)"
}

Write-Host ""

# ── Test 6: Migration Detection ─────────────────────────────────────────────

Write-Host "[Test 6] Legacy installation detection" -ForegroundColor Yellow

# Test: Check if legacy paths exist
$legacyPath = "C:\AI"
if (Test-Path $legacyPath) {
    Test-Warning "Legacy installation found at C:\AI - migration available"
    Write-Host "    Run setup-config.ps1 to migrate to new location" -ForegroundColor Gray
}
else {
    Test-Passed "No legacy installation detected"
}

Write-Host ""

# ── Test 7: File Structure ──────────────────────────────────────────────────

Write-Host "[Test 7] Repository structure validation" -ForegroundColor Yellow

$requiredDirs = @("windows", "linux")
foreach ($dir in $requiredDirs) {
    $dirPath = Join-Path $PSScriptRoot $dir
    if (Test-Path $dirPath) {
        Test-Passed "Required directory exists: $dir"
    }
    else {
        Test-Failed "Required directory missing: $dir"
    }
}

$requiredFiles = @(
    "README.md",
    "SECURITY.md",
    "IDE-CONFIGURATION.md",
    "windows\config.ps1.example",
    "linux\config.sh.example"
)

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $PSScriptRoot $file
    if (Test-Path $filePath) {
        Test-Passed "Required file exists: $file"
    }
    else {
        Test-Failed "Required file missing: $file"
    }
}

Write-Host ""

# ── Summary ─────────────────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Test Results Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Passed:   $TestsPassed" -ForegroundColor Green
Write-Host "  Failed:   $TestsFailed" -ForegroundColor Red
Write-Host "  Warnings: $Warnings" -ForegroundColor Yellow
Write-Host ""

if ($TestsFailed -eq 0) {
    Write-Host "✓ All critical tests passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Ensure configuration exists: cd windows; .\setup-config.ps1" -ForegroundColor White
    Write-Host "  2. Download dependencies:      .\download-llama-cpp.ps1" -ForegroundColor White
    Write-Host "  3. Download models:             .\download-models.ps1" -ForegroundColor White
    Write-Host "  4. Start backend:               .\start-backend-windows.ps1" -ForegroundColor White
    exit 0
}
else {
    Write-Host "✗ Some tests failed. Please fix issues above before proceeding." -ForegroundColor Red
    exit 1
}

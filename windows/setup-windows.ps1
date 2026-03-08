# setup-windows.ps1 — Complete setup for local-ai on Windows
# This script is idempotent and safe to run multiple times.
# It will skip steps that are already completed.

$ErrorActionPreference = "Continue"  # Continue on non-critical errors

$ScriptDir = $PSScriptRoot

# ── Load or Create Configuration ───────────────────────────────────────────────
$ConfigPath = Join-Path $ScriptDir "config.ps1"

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Configuration file not found. Running setup wizard..." -ForegroundColor Yellow
    Write-Host ""
    
    $setupConfigScript = Join-Path $ScriptDir "setup-config.ps1"
    if (Test-Path $setupConfigScript) {
        & $setupConfigScript -NonInteractive
        
        if (-not (Test-Path $ConfigPath)) {
            Write-Error "Failed to create configuration file. Please run: .\setup-config.ps1"
            exit 1
        }
    }
    else {
        Write-Error @"
Configuration files missing. Please ensure these files exist:
  - config.ps1.example
  - setup-config.ps1

Or manually copy: cp config.ps1.example config.ps1
"@
        exit 1
    }
}

# Load configuration
. $ConfigPath

$LlamaCppDir = $LocalAIConfig.LlamaCppDir
$ModelsDir = $LocalAIConfig.ModelsDir
$LogDir = $LocalAIConfig.LogDir

$RequiredModels = @(
    "codellama-13b.Q4_K_M.gguf",
    "mistral-7b-instruct.Q4_K_M.gguf"
)

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  local-ai Windows Setup" -ForegroundColor Cyan
Write-Host "  GPU-accelerated LLM inference for RX 9070XT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 1: Download llama.cpp
# ============================================================================
Write-Host "[1/4] Checking llama.cpp installation..." -ForegroundColor Yellow

$llamaServerExe = Join-Path $LlamaCppDir "llama-server.exe"
$vulkanDll = Join-Path $LlamaCppDir "ggml-vulkan.dll"

if ((Test-Path $llamaServerExe) -and (Test-Path $vulkanDll)) {
    Write-Host "  [OK] llama.cpp already installed at: $LlamaCppDir" -ForegroundColor Green
    Write-Host "      llama-server.exe: $(((Get-Item $llamaServerExe).Length / 1MB).ToString('F1')) MB" -ForegroundColor Gray
    Write-Host "      ggml-vulkan.dll:  $(((Get-Item $vulkanDll).Length / 1MB).ToString('F1')) MB" -ForegroundColor Gray
} else {
    Write-Host "  llama.cpp not found. Downloading..." -ForegroundColor Yellow
    
    $downloadScript = Join-Path $ScriptDir "download-llama-cpp.ps1"
    if (Test-Path $downloadScript) {
        & $downloadScript
        
        # Verify installation was successful
        if (-not ((Test-Path $llamaServerExe) -and (Test-Path $vulkanDll))) {
            Write-Host "  [ERROR] Failed to download llama.cpp" -ForegroundColor Red
            Write-Host "  You can manually run: .\download-llama-cpp.ps1" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "  [ERROR] download-llama-cpp.ps1 not found" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Step 2: Download models
# ============================================================================
Write-Host "[2/4] Checking model files..." -ForegroundColor Yellow

$missingModels = @()
foreach ($model in $RequiredModels) {
    $modelPath = Join-Path $ModelsDir $model
    if (Test-Path $modelPath) {
        $sizeMB = ((Get-Item $modelPath).Length / 1MB).ToString('F1')
        Write-Host "  [OK] $model ($sizeMB MB)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $model" -ForegroundColor Yellow
        $missingModels += $model
    }
}

if ($missingModels.Count -gt 0) {
    Write-Host ""
    Write-Host "  Downloading missing models..." -ForegroundColor Yellow
    
    $downloadScript = Join-Path $ScriptDir "download-models.ps1"
    if (Test-Path $downloadScript) {
        & $downloadScript
        
        # Verify models were downloaded successfully
        $stillMissing = @()
        foreach ($model in $missingModels) {
            $modelPath = Join-Path $ModelsDir $model
            if (-not (Test-Path $modelPath)) {
                $stillMissing += $model
            }
        }
        
        if ($stillMissing.Count -gt 0) {
            Write-Host "  [ERROR] Some models failed to download:" -ForegroundColor Red
            foreach ($model in $stillMissing) {
                Write-Host "    - $model" -ForegroundColor Red
            }
            Write-Host "  You can manually run: .\download-models.ps1" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "  [ERROR] download-models.ps1 not found" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ============================================================================
# Step 3: Verify GPU and Vulkan (optional)
# ============================================================================
Write-Host "[3/4] Verifying Vulkan support..." -ForegroundColor Yellow

$vulkanDllExists = Test-Path $vulkanDll
if ($vulkanDllExists) {
    Write-Host "  [OK] Vulkan backend available (ggml-vulkan.dll found)" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] ggml-vulkan.dll not found - GPU acceleration may not work" -ForegroundColor Yellow
}

# Try to find vulkaninfo
$vulkanInfo = Get-Command vulkaninfo*.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($vulkanInfo) {
    Write-Host "  [OK] vulkaninfo found: $($vulkanInfo.Name)" -ForegroundColor Green
    Write-Host "      Run 'vulkaninfo | Select-String AMD' to verify GPU" -ForegroundColor Gray
} else {
    Write-Host "  [INFO] vulkaninfo not found (optional - not required for operation)" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# Step 4: Configure auto-start (optional, interactive)
# ============================================================================
Write-Host "[4/4] Checking auto-start configuration..." -ForegroundColor Yellow

$taskName = "LocalAI-LlamaServer"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "  [OK] Auto-start already configured" -ForegroundColor Green
    Write-Host "      Task: $taskName" -ForegroundColor Gray
    Write-Host "      State: $($existingTask.State)" -ForegroundColor Gray
    
    if ($existingTask.State -eq 'Disabled') {
        Write-Host ""
        $ans = Read-Host "  Auto-start is disabled. Enable it? [y/N]"
        if ($ans -eq 'y') {
            Enable-ScheduledTask -TaskName $taskName | Out-Null
            Write-Host "  [OK] Auto-start enabled" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  Auto-start not configured." -ForegroundColor Gray
    Write-Host ""
    $ans = Read-Host "  Configure auto-start on boot? (requires Administrator) [y/N]"
    
    if ($ans -eq 'y') {
        # Check if running as admin
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Host ""
            Write-Host "  [INFO] Auto-start setup requires Administrator privileges." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  To configure auto-start:" -ForegroundColor Cyan
            Write-Host "    1. Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor White
            Write-Host "    2. Navigate to: $ScriptDir" -ForegroundColor White
            Write-Host "    3. Run: .\install-autostart.ps1" -ForegroundColor White
            Write-Host ""
        } else {
            $installScript = Join-Path $ScriptDir "install-autostart.ps1"
            if (Test-Path $installScript) {
                & $installScript
            } else {
                Write-Host "  [ERROR] install-autostart.ps1 not found" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  [SKIP] Auto-start not configured. The server will need to be started manually." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  To configure later (requires Administrator PowerShell):" -ForegroundColor Gray
        Write-Host "    .\install-autostart.ps1" -ForegroundColor Gray
    }
}

Write-Host ""

# ============================================================================
# Summary
# ============================================================================
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Installation Summary:" -ForegroundColor Cyan
Write-Host "  llama.cpp:  $LlamaCppDir" -ForegroundColor White
Write-Host "  Models:     $ModelsDir" -ForegroundColor White
$autoStartStatus = if ($existingTask) { 'Configured' } else { 'Not configured' }
Write-Host "  Auto-start: $autoStartStatus" -ForegroundColor White
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host ""

$isServerRunning = Get-Process -Name "llama-server" -ErrorAction SilentlyContinue
if ($isServerRunning) {
    Write-Host "  Server is already running!" -ForegroundColor Green
    Write-Host "    API endpoint: http://localhost:8080" -ForegroundColor White
    Write-Host ""
    Write-Host "  Test it:" -ForegroundColor Yellow
    Write-Host "    Invoke-RestMethod http://localhost:8080/health" -ForegroundColor White
} else {
    if ($existingTask) {
        Write-Host "  1. Start the server (via scheduled task):" -ForegroundColor Yellow
        Write-Host "       Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor White
        Write-Host ""
        Write-Host "     OR start manually:" -ForegroundColor Yellow
        Write-Host "       .\start-backend-windows.ps1" -ForegroundColor White
    } else {
        Write-Host "  1. Start the server:" -ForegroundColor Yellow
        Write-Host "       .\start-backend-windows.ps1" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  2. Test the API:" -ForegroundColor Yellow
    Write-Host "       Invoke-RestMethod http://localhost:8080/health" -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Configure IDE extensions to use: http://localhost:8080" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Useful Commands:" -ForegroundColor Cyan
Write-Host "  Stop server:      .\stop-backend-windows.ps1" -ForegroundColor White
Write-Host "  Check status:     Get-Process llama-server" -ForegroundColor White
Write-Host "  Switch model:     .\start-backend-windows.ps1 -Model mistral" -ForegroundColor White
Write-Host "  Uninstall:        .\uninstall-windows.ps1" -ForegroundColor White
Write-Host ""

Write-Host "For troubleshooting, see: WINDOWS_GPU_SETUP.md" -ForegroundColor Gray
Write-Host ""

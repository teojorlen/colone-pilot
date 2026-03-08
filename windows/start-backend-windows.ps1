# start-backend-windows.ps1
# Starts llama-server.exe (llama.cpp Vulkan build) on Windows for GPU-accelerated
# LLM inference using the RX 9070XT without requiring ROCm.
#
# Prerequisites:
#   - Configuration file created (run .\setup-config.ps1 if missing)
#   - llama.cpp Vulkan build installed
#   - GGUF model files downloaded
#   - AMD Adrenalin driver 24.x or later installed
#
# Usage:
#   .\start-backend-windows.ps1
#   .\start-backend-windows.ps1 -Model mistral -GpuLayers 99
#   .\start-backend-windows.ps1 -ListModels

[CmdletBinding()]
param(
    # Which model to load: mistral (default - better for chat) or codellama (better for code completion)
    [ValidateSet("codellama", "mistral")]
    [string]$Model = "mistral",

    # Number of transformer layers to offload to GPU (overrides config)
    [int]$GpuLayers = -1,

    # API port (overrides config)
    [int]$Port = -1,

    # Context size in tokens (overrides config)
    [int]$CtxSize = -1,

    # CPU threads (overrides config)
    [int]$Threads = -1,

    # Print available models and exit
    [switch]$ListModels
)

# ── Load Configuration ─────────────────────────────────────────────────────────
$ConfigPath = Join-Path $PSScriptRoot "config.ps1"

if (-not (Test-Path $ConfigPath)) {
    Write-Error @"
Configuration file not found: $ConfigPath

Please create a configuration file first:
  1. Interactive: .\setup-config.ps1
  2. Manual:      cp config.ps1.example config.ps1

Then edit config.ps1 to customize your installation paths.
"@
    exit 1
}

# Load configuration
. $ConfigPath

# Use config values as defaults if parameters weren't specified
if ($GpuLayers -eq -1) { $GpuLayers = $LocalAIConfig.GpuLayers }
if ($Port -eq -1) { $Port = $LocalAIConfig.ChatPort }
if ($CtxSize -eq -1) { $CtxSize = $LocalAIConfig.ChatContextSize }
if ($Threads -eq -1) { $Threads = $LocalAIConfig.Threads }

# ── Input Validation (Security) ────────────────────────────────────────────────
# Validate port range
if ($Port -lt 1024 -or $Port -gt 65535) {
    Write-Error "Port must be between 1024 and 65535 (got: $Port)"
    exit 1
}

# Validate GPU layers
if ($GpuLayers -lt 0 -or $GpuLayers -gt 99) {
    Write-Error "GpuLayers must be between 0 and 99 (got: $GpuLayers)"
    exit 1
}

# Validate context size
if ($CtxSize -lt 128 -or $CtxSize -gt 131072) {
    Write-Error "CtxSize must be between 128 and 131072 (got: $CtxSize)"
    exit 1
}

# Validate threads
if ($Threads -lt 1 -or $Threads -gt 256) {
    Write-Error "Threads must be between 1 and 256 (got: $Threads)"
    exit 1
}

# Extract commonly used paths from config
$LlamaCppDir = $LocalAIConfig.LlamaCppDir
$ModelsDir = $LocalAIConfig.ModelsDir

$ModelFiles = @{
    "codellama" = "codellama-13b.Q4_K_M.gguf"
    "mistral"   = "mistral-7b-instruct.Q4_K_M.gguf"
}

# ── List models ────────────────────────────────────────────────────────────────
if ($ListModels) {
    Write-Host "`nAvailable models in $ModelsDir :" -ForegroundColor Cyan
    Get-ChildItem -Path $ModelsDir -Filter "*.gguf" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Name |
    ForEach-Object { Write-Host "  $_" }
    exit 0
}

# ── Validate paths ─────────────────────────────────────────────────────────────
$ServerExe = Join-Path $LlamaCppDir "llama-server.exe"
if (-not (Test-Path $ServerExe)) {
    Write-Error @"
llama-server.exe not found at: $ServerExe

Download the Vulkan build from:
  https://github.com/ggerganov/llama.cpp/releases
  -> llama-b<VERSION>-bin-win-vulkan-x64.zip

Extract it to: $LlamaCppDir
See WINDOWS_GPU_SETUP.md for full instructions.
"@
    exit 1
}

$ModelFile = Join-Path $ModelsDir $ModelFiles[$Model]
if (-not (Test-Path $ModelFile)) {
    Write-Error @"
Model file not found: $ModelFile

Download models with:
  .\download-models.ps1

Or copy GGUF files from WSL:
  $($LocalAIConfig.WSLModelsPath)\$($ModelFiles[$Model])
  -> $ModelFile

Or copy from a custom location.
See windows/README.md for details.
"@
    exit 1
}

# ── Check if port is already in use ───────────────────────────────────────────
$inUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($inUse) {
    Write-Warning "Port $Port is already in use. Is the server already running?"
    Write-Host "  Existing process: $(($inUse | Select-Object -First 1).OwningProcess)" -ForegroundColor Yellow
    $ans = Read-Host "Kill it and continue? [y/N]"
    if ($ans -eq 'y') {
        $inUse | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }
    else {
        exit 1
    }
}

# ── Launch server ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== local-ai Windows backend (llama.cpp Vulkan) ===" -ForegroundColor Cyan
Write-Host "  Model       : $Model ($($ModelFiles[$Model]))"
Write-Host "  GPU layers  : $GpuLayers  (use -GpuLayers 99 to push all layers to VRAM)"
Write-Host "  Context     : $CtxSize tokens"
Write-Host "  Threads     : $Threads"
Write-Host "  API         : http://127.0.0.1:$Port"
Write-Host ""
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""

& $ServerExe `
    --model        $ModelFile `
    --n-gpu-layers $GpuLayers `
    --ctx-size     $CtxSize `
    --threads      $Threads `
    --port         $Port `
    --host         127.0.0.1

# Server exited
Write-Host ""
Write-Host "Server stopped." -ForegroundColor Yellow

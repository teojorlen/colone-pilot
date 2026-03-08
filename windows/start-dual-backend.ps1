# start-dual-backend.ps1
# Starts TWO llama-server instances for optimal IDE integration:
#   - Port 8080: Mistral Instruct (chat, editing, Q&A)
#   - Port 8081: CodeLlama (code completion/autocomplete)
#
# This gives you the best of both worlds:
#   - Mistral for coherent, helpful chat responses
#   - CodeLlama for accurate code completion
#
# Usage:
#   .\start-dual-backend.ps1
#   .\start-dual-backend.ps1 -GpuLayers 99  (offload everything to GPU)
#   .\start-dual-backend.ps1 -ChatCtxSize 16384  (increase chat context)
#   .\start-dual-backend.ps1 -CompletionCtxSize 1024  (reduce completion context for faster responses)

[CmdletBinding()]
param(
    # Number of transformer layers to offload to GPU (overrides config)
    [int]$GpuLayers = -1,
    
    # Context size for chat model (overrides config)
    [int]$ChatCtxSize = -1,
    
    # Context size for completion model (overrides config)
    [int]$CompletionCtxSize = -1,
    
    # CPU threads (overrides config)
    [int]$Threads = -1,

    # Skip interactive prompts and stop any existing servers automatically
    [switch]$Force
)

$ErrorActionPreference = "Stop"

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
if ($ChatCtxSize -eq -1) { $ChatCtxSize = $LocalAIConfig.ChatContextSize }
if ($CompletionCtxSize -eq -1) { $CompletionCtxSize = $LocalAIConfig.CompletionContextSize }
if ($Threads -eq -1) { $Threads = $LocalAIConfig.Threads }

Write-Host "=== Starting Dual Backend Setup ===" -ForegroundColor Cyan
Write-Host ""

# ── Extract paths from configuration ───────────────────────────────────────────
$LlamaCppDir = $LocalAIConfig.LlamaCppDir
$ModelsDir = $LocalAIConfig.ModelsDir

$MistralModel = Join-Path $ModelsDir $LocalAIConfig.ChatModel
$CodeLlamaModel = Join-Path $ModelsDir $LocalAIConfig.CompletionModel
$ServerExe = Join-Path $LlamaCppDir "llama-server.exe"

# ── Validate ───────────────────────────────────────────────────────────────────
if (-not (Test-Path $ServerExe)) {
    Write-Error "llama-server.exe not found at: $ServerExe"
    exit 1
}

if (-not (Test-Path $MistralModel)) {
    Write-Error "Mistral model not found: $MistralModel"
    exit 1
}

if (-not (Test-Path $CodeLlamaModel)) {
    Write-Error "CodeLlama model not found: $CodeLlamaModel"
    exit 1
}

# ── Check for existing processes ───────────────────────────────────────────────
$chatPort = $LocalAIConfig.ChatPort
$completionPort = $LocalAIConfig.CompletionPort

$portChat = Get-NetTCPConnection -LocalPort $chatPort -State Listen -ErrorAction SilentlyContinue
$portCompletion = Get-NetTCPConnection -LocalPort $completionPort -State Listen -ErrorAction SilentlyContinue

if ($portChat -or $portCompletion) {
    Write-Warning "One or more ports already in use:"
    if ($portChat) { Write-Host "  Port $chatPort (Mistral)" -ForegroundColor Yellow }
    if ($portCompletion) { Write-Host "  Port $completionPort (CodeLlama)" -ForegroundColor Yellow }
    Write-Host ""
    if ($Force) {
        Write-Host "  -Force specified: stopping existing servers..." -ForegroundColor Yellow
        & "$PSScriptRoot\stop-backend-windows.ps1"
        Start-Sleep -Seconds 2
    }
    else {
        $ans = Read-Host "Stop existing servers and continue? [y/N]"
        if ($ans -eq 'y') {
            & "$PSScriptRoot\stop-backend-windows.ps1"
            Start-Sleep -Seconds 2
        }
        else {
            exit 1
        }
    }
}

# ── Start Mistral on chat port (for chat) ─────────────────────────────────────
Write-Host "[1/2] Starting Mistral 7B Instruct on port $chatPort..." -ForegroundColor Green
Write-Host "  Purpose: Chat, Q&A, code explanations" -ForegroundColor Gray
Write-Host "  Model: $MistralModel" -ForegroundColor Gray
Write-Host ""

$mistralArgs = @(
    '--model', $MistralModel
    '--host', '127.0.0.1'
    '--port', $chatPort
    '--ctx-size', $ChatCtxSize
    '--threads', $Threads
    '--n-gpu-layers', $GpuLayers
    # Let llama.cpp auto-detect chat template from model metadata
)

if (-not $LocalAIConfig.EnableLogging) {
    $mistralArgs += '--log-disable'
}

$mistralStartParams = @{ FilePath = $ServerExe; ArgumentList = $mistralArgs; WindowStyle = 'Minimized' }
if ($LocalAIConfig.EnableLogging) {
    $null = New-Item -ItemType Directory -Path $LocalAIConfig.LogDir -Force
    $mistralStartParams['RedirectStandardOutput'] = Join-Path $LocalAIConfig.LogDir 'mistral.log'
    $mistralStartParams['RedirectStandardError'] = Join-Path $LocalAIConfig.LogDir 'mistral-error.log'
}
Start-Process @mistralStartParams

Write-Host "  Started Mistral on http://localhost:$chatPort" -ForegroundColor Green
Write-Host ""

# Wait for Mistral to start
Start-Sleep -Seconds 5

# ── Start CodeLlama on completion port (for autocomplete) ──────────────────────
Write-Host "[2/2] Starting CodeLlama 13B on port $completionPort..." -ForegroundColor Green
Write-Host "  Purpose: Code completion, autocomplete" -ForegroundColor Gray
Write-Host "  Model: $CodeLlamaModel" -ForegroundColor Gray
Write-Host ""

$codeLlamaArgs = @(
    '--model', $CodeLlamaModel
    '--host', '127.0.0.1'
    '--port', $completionPort
    '--ctx-size', $CompletionCtxSize
    '--threads', $Threads
    '--n-gpu-layers', $GpuLayers
)

if (-not $LocalAIConfig.EnableLogging) {
    $codeLlamaArgs += '--log-disable'
}

$codeLlamaStartParams = @{ FilePath = $ServerExe; ArgumentList = $codeLlamaArgs; WindowStyle = 'Minimized' }
if ($LocalAIConfig.EnableLogging) {
    $null = New-Item -ItemType Directory -Path $LocalAIConfig.LogDir -Force
    $codeLlamaStartParams['RedirectStandardOutput'] = Join-Path $LocalAIConfig.LogDir 'codellama.log'
    $codeLlamaStartParams['RedirectStandardError'] = Join-Path $LocalAIConfig.LogDir 'codellama-error.log'
}
Start-Process @codeLlamaStartParams

Write-Host "  Started CodeLlama on http://localhost:$completionPort" -ForegroundColor Green
Write-Host ""

# Wait for CodeLlama to start
Start-Sleep -Seconds 5

# ── Verify both servers ────────────────────────────────────────────────────────
Write-Host "=== Verifying servers ===" -ForegroundColor Cyan
Write-Host ""

try {
    $mistralHealth = Invoke-RestMethod -Uri "http://localhost:$chatPort/health" -TimeoutSec 5
    if ($mistralHealth.status -eq "ok") {
        Write-Host "  ✓ Mistral (port $chatPort): Running" -ForegroundColor Green
    }
}
catch {
    Write-Warning "  ✗ Mistral (port $chatPort): Not responding"
}

try {
    $codeHealth = Invoke-RestMethod -Uri "http://localhost:$completionPort/health" -TimeoutSec 5
    if ($codeHealth.status -eq "ok") {
        Write-Host "  ✓ CodeLlama (port $completionPort): Running" -ForegroundColor Green
    }
}
catch {
    Write-Warning "  ✗ CodeLlama (port $completionPort): Not responding"
}

Write-Host ""
Write-Host "=== Dual backend is ready! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Mistral (chat):           http://localhost:$chatPort  (context: $ChatCtxSize tokens)" -ForegroundColor White
Write-Host "  CodeLlama (autocomplete): http://localhost:$completionPort  (context: $CompletionCtxSize tokens)" -ForegroundColor White
Write-Host "  GPU Layers: $GpuLayers  |  Threads: $Threads" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Update Continue config to use both models" -ForegroundColor White
Write-Host "  2. Restart VS Code" -ForegroundColor White
Write-Host "  3. Start coding!" -ForegroundColor White
Write-Host ""
Write-Host "To stop both servers: .\stop-backend-windows.ps1" -ForegroundColor Gray
Write-Host ""

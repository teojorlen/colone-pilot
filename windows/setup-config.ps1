# setup-config.ps1
# Interactive configuration wizard for Local AI Windows setup
# Creates a customized config.ps1 based on user preferences and system detection

[CmdletBinding()]
param(
    # Non-interactive mode (use defaults)
    [switch]$NonInteractive,
    
    # Force overwrite existing config
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ── Helper Functions ────────────────────────────────────────────────────────

function Write-Title {
    param([string]$Text)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "▶ $Text" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Text)
    Write-Host "✓ $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Gray
}

function Get-UserChoice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 0
    )
    
    Write-Host $Prompt -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { "*" } else { " " }
        Write-Host "  [$($i + 1)]$marker $($Options[$i])" -ForegroundColor Gray
    }
    
    $choice = Read-Host "Choice [1-$($Options.Count)] (default: $($Default + 1))"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return $Default
    }
    
    $choiceNum = 0
    if ([int]::TryParse($choice, [ref]$choiceNum)) {
        if ($choiceNum -ge 1 -and $choiceNum -le $Options.Count) {
            return $choiceNum - 1
        }
    }
    
    Write-Warning "Invalid choice, using default"
    return $Default
}

function Test-LegacyInstallation {
    $legacyPath = "C:\AI"
    $hasLlama = Test-Path "$legacyPath\llama.cpp\llama-server.exe"
    $hasModels = Test-Path "$legacyPath\models\*.gguf"
    
    return @{
        Exists = (Test-Path $legacyPath)
        HasLlama = $hasLlama
        HasModels = $hasModels
        Path = $legacyPath
    }
}

# ── Main Script ─────────────────────────────────────────────────────────────

Write-Title "Local AI Configuration Wizard"

# Check if config already exists
$configPath = Join-Path $PSScriptRoot "config.ps1"
$configExists = Test-Path $configPath

if ($configExists -and -not $Force) {
    Write-Warning "Configuration file already exists: $configPath"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  1. Keep existing config (exit)" -ForegroundColor Gray
    Write-Host "  2. Overwrite with new config" -ForegroundColor Gray
    Write-Host "  3. Edit existing config in notepad" -ForegroundColor Gray
    Write-Host ""
    
    $choice = Read-Host "Choice [1-3]"
    
    switch ($choice) {
        "1" { 
            Write-Host "Keeping existing config." -ForegroundColor Green
            exit 0 
        }
        "2" { 
            Write-Step "Will create new config..."
        }
        "3" { 
            notepad $configPath
            exit 0
        }
        default {
            Write-Host "Keeping existing config." -ForegroundColor Green
            exit 0
        }
    }
}

Write-Host "This wizard will help you create a customized configuration." -ForegroundColor Gray
Write-Host ""

# ── Step 1: Check for legacy installation ──────────────────────────────────

$legacy = Test-LegacyInstallation

if ($legacy.Exists) {
    Write-Step "Detected existing installation at C:\AI"
    Write-Info "  Llama.cpp: $(if ($legacy.HasLlama) { 'Found' } else { 'Not found' })"
    Write-Info "  Models:    $(if ($legacy.HasModels) { 'Found' } else { 'Not found' })"
    Write-Host ""
    
    if (-not $NonInteractive) {
        Write-Host "Would you like to migrate from the existing C:\AI installation?" -ForegroundColor Yellow
        Write-Host "  [Y] Yes - Use C:\AI and keep existing files" -ForegroundColor Gray
        Write-Host "  [N] No  - Use new location (AppData\Local\LocalAI)" -ForegroundColor Gray
        Write-Host ""
        
        $migrate = Read-Host "Migrate [Y/n]"
        $useLegacyPath = $migrate -ne "n" -and $migrate -ne "N"
    }
    else {
        $useLegacyPath = $true
    }
}
else {
    $useLegacyPath = $false
}

# ── Step 2: Choose base directory ──────────────────────────────────────────

if (-not $useLegacyPath) {
    Write-Step "Choose installation location"
    
    if (-not $NonInteractive) {
        $baseChoice = Get-UserChoice `
            -Prompt "Where should Local AI be installed?" `
            -Options @(
                "AppData\Local\LocalAI (Recommended - No admin needed, per-user)",
                "C:\AI (System-wide - Requires admin for initial setup)"
            ) `
            -Default 0
        
        if ($baseChoice -eq 0) {
            $baseDir = "$env:LOCALAPPDATA\LocalAI"
        }
        else {
            $baseDir = "C:\AI"
        }
    }
    else {
        $baseDir = "$env:LOCALAPPDATA\LocalAI"
    }
}
else {
    $baseDir = "C:\AI"
}

Write-Success "Installation path: $baseDir"

# ── Step 3: GPU configuration ───────────────────────────────────────────────

Write-Step "Configure GPU offloading"

if (-not $NonInteractive) {
    Write-Host "How many layers should be offloaded to GPU?" -ForegroundColor White
    Write-Host "  - 40: Balanced (recommended for 16GB VRAM)" -ForegroundColor Gray
    Write-Host "  - 99: Maximum (pushes all layers to GPU)" -ForegroundColor Gray
    Write-Host "  - 0:  CPU only (no GPU acceleration)" -ForegroundColor Gray
    Write-Host ""
    
    $gpuInput = Read-Host "GPU layers [0-99] (default: 40)"
    $gpuLayers = if ([string]::IsNullOrWhiteSpace($gpuInput)) { 40 } else { [int]$gpuInput }
}
else {
    $gpuLayers = 40
}

Write-Success "GPU layers: $gpuLayers"

# ── Step 4: Context sizes ───────────────────────────────────────────────────

Write-Step "Configure context sizes"

if (-not $NonInteractive) {
    Write-Host "Chat context size (larger = longer conversations but slower)?" -ForegroundColor White
    Write-Host "  Common values: 2048, 4096, 8192, 16384" -ForegroundColor Gray
    Write-Host ""
    
    $chatCtxInput = Read-Host "Chat context tokens (default: 8192)"
    $chatContextSize = if ([string]::IsNullOrWhiteSpace($chatCtxInput)) { 8192 } else { [int]$chatCtxInput }
    
    Write-Host ""
    Write-Host "Completion context size (smaller = faster autocomplete)?" -ForegroundColor White
    Write-Host "  Common values: 1024, 2048, 4096" -ForegroundColor Gray
    Write-Host ""
    
    $compCtxInput = Read-Host "Completion context tokens (default: 2048)"
    $completionContextSize = if ([string]::IsNullOrWhiteSpace($compCtxInput)) { 2048 } else { [int]$compCtxInput }
}
else {
    $chatContextSize = 8192
    $completionContextSize = 2048
}

Write-Success "Chat context: $chatContextSize tokens"
Write-Success "Completion context: $completionContextSize tokens"

# ── Step 5: Ports ───────────────────────────────────────────────────────────

Write-Step "Configure ports"

if (-not $NonInteractive) {
    $chatPortInput = Read-Host "Chat port (default: 8080)"
    $chatPort = if ([string]::IsNullOrWhiteSpace($chatPortInput)) { 8080 } else { [int]$chatPortInput }
    
    $compPortInput = Read-Host "Completion port (default: 8081)"
    $completionPort = if ([string]::IsNullOrWhiteSpace($compPortInput)) { 8081 } else { [int]$compPortInput }
}
else {
    $chatPort = 8080
    $completionPort = 8081
}

Write-Success "Chat port: $chatPort"
Write-Success "Completion port: $completionPort"

# ── Step 6: Generate config file ────────────────────────────────────────────

Write-Step "Creating configuration file..."

# Read the example config
$examplePath = Join-Path $PSScriptRoot "config.ps1.example"
if (-not (Test-Path $examplePath)) {
    Write-Error "config.ps1.example not found. Please ensure it exists in the same directory."
    exit 1
}

$configContent = Get-Content $examplePath -Raw

# Replace values
$configContent = $configContent -replace '\$BaseDir = "\$env:LOCALAPPDATA\\LocalAI"', "`$BaseDir = `"$baseDir`""
$configContent = $configContent -replace '\$GpuLayers = 40', "`$GpuLayers = $gpuLayers"
$configContent = $configContent -replace '\$ChatContextSize = 8192', "`$ChatContextSize = $chatContextSize"
$configContent = $configContent -replace '\$CompletionContextSize = 2048', "`$CompletionContextSize = $completionContextSize"
$configContent = $configContent -replace '\$ChatPort = 8080', "`$ChatPort = $chatPort"
$configContent = $configContent -replace '\$CompletionPort = 8081', "`$CompletionPort = $completionPort"

# Add migration note if using legacy path
if ($useLegacyPath) {
    $configContent = "# NOTE: Using existing C:\AI installation (migrated from legacy setup)`n`n" + $configContent
}

# Write config file
$configContent | Set-Content -Path $configPath -Encoding UTF8

Write-Success "Configuration saved to: $configPath"

# ── Step 7: Summary ─────────────────────────────────────────────────────────

Write-Title "Configuration Complete!"

Write-Host "Summary:" -ForegroundColor Cyan
Write-Info "  Base Directory:    $baseDir"
Write-Info "  GPU Layers:        $gpuLayers"
Write-Info "  Chat Context:      $chatContextSize tokens"
Write-Info "  Completion Context: $completionContextSize tokens"
Write-Info "  Chat Port:         $chatPort"
Write-Info "  Completion Port:   $completionPort"
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Info "  1. Review config (optional): notepad $configPath"
Write-Info "  2. Run setup:                .\setup-windows.ps1"
Write-Info "  3. Start backend:            .\start-dual-backend.ps1"
Write-Host ""

if ($useLegacyPath -and ($legacy.HasLlama -or $legacy.HasModels)) {
    Write-Host "Migration Notes:" -ForegroundColor Yellow
    Write-Info "  Your existing llama.cpp and models in C:\AI will be used."
    Write-Info "  No files will be moved or deleted."
    Write-Host ""
}

Write-Success "Configuration wizard completed successfully!"

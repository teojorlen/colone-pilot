# install-autostart-dual.ps1 — Configure dual llama-server setup to start automatically on Windows boot
# Starts both Mistral (port 8080) and CodeLlama (port 8081) as background processes
# Uses Windows Task Scheduler
#
# ⚠️ IMPORTANT: This script MUST be run as Administrator
# Right-click PowerShell → "Run as Administrator" before executing this script

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$TaskName = "LocalAI-DualBackend"
$ScriptDir = $PSScriptRoot
$StartScript = Join-Path $ScriptDir "start-dual-backend.ps1"

# ── Load Configuration ─────────────────────────────────────────────────────────
$ConfigPath = Join-Path $ScriptDir "config.ps1"

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

$LogDir = $LocalAIConfig.LogDir
$ChatPort = $LocalAIConfig.ChatPort
$CompletionPort = $LocalAIConfig.CompletionPort

Write-Host "=== Auto-start Configuration for Dual Backend ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will configure:" -ForegroundColor Yellow
Write-Host "  - Mistral 7B Instruct (port $ChatPort) for chat" -ForegroundColor White
Write-Host "  - CodeLlama 13B (port $CompletionPort) for autocomplete" -ForegroundColor White
Write-Host ""

# Validate start script exists
if (-not (Test-Path $StartScript)) {
    Write-Host "[error] start-dual-backend.ps1 not found at: $StartScript" -ForegroundColor Red
    Write-Host "Make sure you're running this from the windows/ directory" -ForegroundColor Yellow
    exit 1
}

# Create log directory
if (-not (Test-Path $LogDir)) {
    Write-Host "[1/4] Creating log directory: $LogDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
else {
    Write-Host "[1/4] Log directory exists: $LogDir" -ForegroundColor Green
}

# Remove old single-server task if it exists
Write-Host ""
Write-Host "[2/4] Checking for old single-server task..." -ForegroundColor Yellow
$oldTask = Get-ScheduledTask -TaskName "LocalAI-LlamaServer" -ErrorAction SilentlyContinue

if ($oldTask) {
    Write-Host "  Found old task: LocalAI-LlamaServer" -ForegroundColor Yellow
    $ans = Read-Host "  Remove old single-server task? [y/N]"
    if ($ans -eq 'y') {
        Unregister-ScheduledTask -TaskName "LocalAI-LlamaServer" -Confirm:$false
        Write-Host "  Removed old task" -ForegroundColor Green
    }
}

# Check if dual task already exists
Write-Host ""
Write-Host "[3/4] Checking for existing dual backend task..." -ForegroundColor Yellow
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "  Task already exists: $TaskName" -ForegroundColor Yellow
    $ans = Read-Host "  Remove and recreate? [y/N]"
    if ($ans -eq 'y') {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  Removed existing task" -ForegroundColor Green
    }
    else {
        Write-Host "  [aborted] Keeping existing task" -ForegroundColor Yellow
        exit 0
    }
}

# Create scheduled task
Write-Host ""
Write-Host "[4/4] Creating scheduled task..." -ForegroundColor Yellow

# Task action: Run PowerShell with the dual start script (hidden window, max GPU layers)
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$StartScript`" -GpuLayers 99"

# Trigger: At system startup
$trigger = New-ScheduledTaskTrigger -AtStartup

# Settings: Run whether user is logged on or not, don't stop if idle
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false `
    -DontStopOnIdleEnd

# Principal: Run with highest privileges as SYSTEM
$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Register the task
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Auto-start dual llama-server setup (Mistral 8080 + CodeLlama 8081)" `
        -ErrorAction Stop | Out-Null
    
    Write-Host "  [done] Task created: $TaskName" -ForegroundColor Green
}
catch {
    Write-Host "  [failed] Could not create scheduled task" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host ""
Write-Host "=== Auto-start configured! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Both servers will now start automatically on system boot:" -ForegroundColor Cyan
Write-Host "  - Mistral (port 8080): Chat, Q&A, explanations" -ForegroundColor White
Write-Host "  - CodeLlama (port 8081): Code completion" -ForegroundColor White
Write-Host ""
Write-Host "Management commands:" -ForegroundColor Cyan
Write-Host "  Start task:   Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  Stop servers: .\stop-backend-windows.ps1" -ForegroundColor White
Write-Host "  Check status: Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  View details: Get-ScheduledTaskInfo -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""
Write-Host "To activate without rebooting:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""
Write-Host "To uninstall:" -ForegroundColor Gray
Write-Host "  .\uninstall-windows.ps1" -ForegroundColor White
Write-Host ""
Write-Host "⚠️  The task runs as SYSTEM with elevated privileges." -ForegroundColor Yellow
Write-Host "    See SECURITY.md for implications." -ForegroundColor Yellow
Write-Host ""

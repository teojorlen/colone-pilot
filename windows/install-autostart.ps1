# install-autostart.ps1 — Configure llama-server to start automatically on Windows boot
# Uses Windows Task Scheduler to run the backend as a background process
#
# ⚠️ IMPORTANT: This script MUST be run as Administrator
# Right-click PowerShell → "Run as Administrator" before executing this script

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$TaskName = "LocalAI-LlamaServer"
$ScriptDir = $PSScriptRoot
$StartScript = Join-Path $ScriptDir "start-backend-windows.ps1"

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

Write-Host "=== Auto-start Configuration for llama-server ===" -ForegroundColor Cyan
Write-Host ""

# Validate start script exists
if (-not (Test-Path $StartScript)) {
    Write-Host "[error] start-backend-windows.ps1 not found at: $StartScript" -ForegroundColor Red
    exit 1
}

# Create log directory
if (-not (Test-Path $LogDir)) {
    Write-Host "[1/3] Creating log directory: $LogDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
} else {
    Write-Host "[1/3] Log directory exists: $LogDir" -ForegroundColor Green
}

# Check if task already exists
Write-Host ""
Write-Host "[2/3] Checking for existing scheduled task..." -ForegroundColor Yellow
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "  Task already exists: $TaskName" -ForegroundColor Yellow
    $ans = Read-Host "  Remove and recreate? [y/N]"
    if ($ans -eq 'y') {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  Removed existing task" -ForegroundColor Green
    } else {
        Write-Host "  [aborted] Keeping existing task" -ForegroundColor Yellow
        exit 0
    }
}

# Create scheduled task
Write-Host ""
Write-Host "[3/3] Creating scheduled task..." -ForegroundColor Yellow

# Task action: Run PowerShell with the start script (hidden window)
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$StartScript`""

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
        -Description "Auto-start llama-server.exe for GPU-accelerated LLM inference" `
        -ErrorAction Stop | Out-Null
    
    Write-Host "  [done] Task created: $TaskName" -ForegroundColor Green
} catch {
    Write-Host "  [failed] Could not create scheduled task" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host ""
Write-Host "=== Auto-start configured! ===" -ForegroundColor Green
Write-Host ""
Write-Host "The llama-server will now start automatically on system boot." -ForegroundColor Cyan
Write-Host ""
Write-Host "Management commands:" -ForegroundColor Cyan
Write-Host "  - Start now:    Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  - Stop:         Stop-ScheduledTask -TaskName '$TaskName' (note: may restart immediately)" -ForegroundColor White
Write-Host "  - View status:  Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo" -ForegroundColor White
Write-Host "  - View logs:    Get-Content '$LogDir\llama-server.log' -Tail 50" -ForegroundColor White
Write-Host "  - Disable:      Disable-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host "  - Remove:       Unregister-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""
Write-Host "Note: The server runs as SYSTEM, so it starts even before user login." -ForegroundColor Gray
Write-Host "To start the task now without rebooting, run:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor White
Write-Host ""

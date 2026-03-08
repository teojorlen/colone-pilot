# uninstall-windows.ps1 — Remove local-ai Windows installation
# Stops services, removes scheduled tasks, and optionally deletes downloaded files

$ErrorActionPreference = "Continue"

$TaskNames = @("LocalAI-LlamaServer", "LocalAI-DualBackend")  # Support both old and new task names

# ── Try to Load Configuration (optional for uninstall) ───────────────────────────
$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "config.ps1"

# Try to load config, but use defaults if not available
if (Test-Path $ConfigPath) {
    . $ConfigPath
    $LlamaCppDir = $LocalAIConfig.LlamaCppDir
    $ModelsDir = $LocalAIConfig.ModelsDir
    $LogDir = $LocalAIConfig.LogDir
    $AIDir = Split-Path $LocalAIConfig.BaseDir -Parent
    if ([string]::IsNullOrEmpty($AIDir)) { $AIDir = $LocalAIConfig.BaseDir }
}
else {
    # Fallback: try both common locations
    Write-Warning "Config not found. Will check both legacy (C:\AI) and new location."
    $LlamaCppDir = "C:\AI\llama.cpp"
    $ModelsDir = "C:\AI\models"
    $LogDir = "C:\AI\logs"
    $AIDir = "C:\AI"
    
    # Also check new default location
    $newBaseDir = "$env:LOCALAPPDATA\LocalAI"
    $alternativeDirs = @{
        LlamaCpp = "$newBaseDir\llama.cpp"
        Models = "$newBaseDir\models"
        Log = "$newBaseDir\logs"
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  local-ai Windows Uninstaller" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Step 1: Stop running processes
# ============================================================================
Write-Host "[1/4] Stopping llama-server processes..." -ForegroundColor Yellow

$processes = Get-Process -Name "llama-server" -ErrorAction SilentlyContinue

if ($processes) {
    Write-Host "  Found $($processes.Count) running process(es)" -ForegroundColor Yellow
    foreach ($proc in $processes) {
        try {
            Stop-Process -Id $proc.Id -Force
            Write-Host "  [stopped] PID $($proc.Id)" -ForegroundColor Green
        } catch {
            Write-Host "  [failed] PID $($proc.Id): $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  [OK] No running processes found" -ForegroundColor Green
}

Write-Host ""

# ============================================================================
# Step 2: Remove scheduled task(s)
# ============================================================================
Write-Host "[2/4] Removing scheduled task(s)..." -ForegroundColor Yellow

$removedAny = $false
foreach ($taskName in $TaskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($task) {
        try {
            # Check if we have admin rights
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            
            if ($isAdmin) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-Host "  [removed] Scheduled task: $taskName" -ForegroundColor Green
                $removedAny = $true
            } else {
                Write-Host "  [WARNING] Administrator privileges required to remove scheduled task" -ForegroundColor Yellow
                Write-Host "  Run as Administrator to fully uninstall, or manually remove with:" -ForegroundColor Yellow
                Write-Host "    Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" -ForegroundColor White
            }
        } catch {
            Write-Host "  [failed] Could not remove task '$taskName': $_" -ForegroundColor Red
        }
    }
}

if (-not $removedAny) {
    $task = Get-ScheduledTask -TaskName $TaskNames[0] -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "  [OK] No scheduled tasks found" -ForegroundColor Green
    }
}
    } catch {
        Write-Host "  [failed] Could not remove scheduled task: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [OK] No scheduled task found" -ForegroundColor Green
}

Write-Host ""

# ============================================================================
# Step 3: Remove downloaded files (optional, with confirmation)
# ============================================================================
Write-Host "[3/4] Checking downloaded files..." -ForegroundColor Yellow

$dirsToCheck = @(
    @{ Path = $LlamaCppDir; Description = "llama.cpp installation" },
    @{ Path = $ModelsDir; Description = "Model files" },
    @{ Path = $LogDir; Description = "Log files" }
)

$existingDirs = @()
$totalSize = 0

foreach ($dir in $dirsToCheck) {
    if (Test-Path $dir.Path) {
        $size = (Get-ChildItem -Path $dir.Path -Recurse -File -ErrorAction SilentlyContinue | 
                 Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 1)
        
        Write-Host "  [found] $($dir.Description): $($dir.Path) ($sizeMB MB)" -ForegroundColor Yellow
        $existingDirs += $dir
        $totalSize += $size
    } else {
        Write-Host "  [skip] $($dir.Description): not found" -ForegroundColor Gray
    }
}

if ($existingDirs.Count -gt 0) {
    $totalSizeGB = [math]::Round($totalSize / 1GB, 2)
    Write-Host ""
    Write-Host "  Total disk space used: $totalSizeGB GB" -ForegroundColor Cyan
    Write-Host ""
    
    $ans = Read-Host "  Delete all downloaded files? [y/N]"
    
    if ($ans -eq 'y') {
        Write-Host ""
        foreach ($dir in $existingDirs) {
            try {
                Write-Host "  Removing: $($dir.Path)..." -ForegroundColor Yellow
                Remove-Item -Path $dir.Path -Recurse -Force
                Write-Host "  [removed] $($dir.Description)" -ForegroundColor Green
            } catch {
                Write-Host "  [failed] Could not remove $($dir.Description): $_" -ForegroundColor Red
            }
        }
        
        # Try to remove parent C:\AI directory if empty
        if ((Test-Path $AIDir) -and (Get-ChildItem $AIDir -ErrorAction SilentlyContinue).Count -eq 0) {
            try {
                Remove-Item -Path $AIDir -Force
                Write-Host "  [removed] $AIDir (empty directory)" -ForegroundColor Green
            } catch {
                # Silently ignore - not critical
            }
        }
    } else {
        Write-Host ""
        Write-Host "  [skip] Files kept. You can manually delete them later:" -ForegroundColor Yellow
        foreach ($dir in $existingDirs) {
            Write-Host "    Remove-Item -Recurse -Force '$($dir.Path)'" -ForegroundColor White
        }
    }
} else {
    Write-Host "  [OK] No files to remove" -ForegroundColor Green
}

Write-Host ""

# ============================================================================
# Step 4: Clean up workspace scripts (optional)
# ============================================================================
Write-Host "[4/4] Workspace cleanup..." -ForegroundColor Yellow

Write-Host "  The following scripts remain in your workspace:" -ForegroundColor Gray
Write-Host "    - setup-windows.ps1" -ForegroundColor Gray
Write-Host "    - download-llama-cpp.ps1" -ForegroundColor Gray
Write-Host "    - download-models.ps1" -ForegroundColor Gray
Write-Host "    - start-backend-windows.ps1" -ForegroundColor Gray
Write-Host "    - stop-backend-windows.ps1" -ForegroundColor Gray
Write-Host "    - install-autostart.ps1" -ForegroundColor Gray
Write-Host "    - uninstall-windows.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "  These are part of the repository and are NOT removed by uninstall." -ForegroundColor Gray
Write-Host "  To completely remove, delete the entire workspace folder." -ForegroundColor Gray

Write-Host ""

# ============================================================================
# Summary
# ============================================================================
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Uninstall Complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "What was removed:" -ForegroundColor Cyan
Write-Host "  - llama-server processes: stopped" -ForegroundColor White
$taskStatus = if ($task) { 'removed' } else { 'none' }
Write-Host "  - Scheduled task:         $taskStatus" -ForegroundColor White
$filesStatus = if ($ans -eq 'y') { 'removed' } else { 'kept' }
Write-Host "  - Downloaded files:       $filesStatus" -ForegroundColor White
Write-Host ""

if ($ans -ne 'y') {
    Write-Host "Note: Downloaded files (~$totalSizeGB GB) are still on disk at C:\AI\" -ForegroundColor Yellow
    Write-Host "To reclaim space, manually delete them or re-run this script." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "To reinstall, run: .\setup-windows.ps1" -ForegroundColor Cyan
Write-Host ""

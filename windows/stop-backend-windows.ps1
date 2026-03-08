# stop-backend-windows.ps1 — Stop the llama-server process

$ErrorActionPreference = "Stop"

Write-Host "=== Stopping llama-server ===" -ForegroundColor Cyan
Write-Host ""

# Find llama-server.exe processes
$processes = Get-Process -Name "llama-server" -ErrorAction SilentlyContinue

if (-not $processes) {
    Write-Host "No llama-server.exe processes found." -ForegroundColor Yellow
    Write-Host ""
    
    # Check if scheduled tasks exist and are running
    $tasks = @("LocalAI-LlamaServer", "LocalAI-DualBackend")
    $stoppedAny = $false
    
    foreach ($taskName in $tasks) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq 'Running') {
            Write-Host "Scheduled task '$taskName' is active. Stopping task..." -ForegroundColor Yellow
            Stop-ScheduledTask -TaskName $taskName
            $stoppedAny = $true
        }
    }
    
    if ($stoppedAny) {
        Start-Sleep -Seconds 2
        Write-Host "Task(s) stopped." -ForegroundColor Green
    }
    
    exit 0
}

# Show processes
Write-Host "Found $($processes.Count) llama-server process(es):" -ForegroundColor Yellow
$processes | Format-Table Id, CPU, WorkingSet, StartTime -AutoSize

# Stop them
Write-Host ""
Write-Host "Stopping processes..." -ForegroundColor Yellow
$processes | ForEach-Object {
    try {
        Stop-Process -Id $_.Id -Force
        Write-Host "  [stopped] PID $($_.Id)" -ForegroundColor Green
    } catch {
        Write-Host "  [failed] PID $($_.Id): $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ""

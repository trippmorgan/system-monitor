#===============================================================================
# stop.ps1 - Stop Radio Free Albany Background Processes (Windows)
#===============================================================================
# PURPOSE:
#   Cleanly stops all Radio Free Albany background processes started by launch.ps1.
#   Kills both the data refresh loop and the HTTP server.
#
# USAGE:
#   .\system-monitor\dashboard\stop.ps1
#===============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path (Split-Path -Parent $ScriptDir) "config.ps1"

if (Test-Path $ConfigFile) {
    . $ConfigFile
}

$DASHBOARD_DIR = if ($DASHBOARD_DIR) { $DASHBOARD_DIR } else { $ScriptDir }
$LOG_DIR = if ($LOG_DIR) { $LOG_DIR } else { Join-Path (Split-Path -Parent $ScriptDir) "logs" }
$PidFile = Join-Path $DASHBOARD_DIR ".refresh.pid"
$ServerPidFile = Join-Path $DASHBOARD_DIR ".server.pid"
$LaunchLog = Join-Path $LOG_DIR "launcher.log"

Write-Host "Stopping Radio Free Albany..."

# Stop the watchdog first (so it doesn't restart things we're killing)
$WatchdogPidFile = Join-Path $DASHBOARD_DIR ".watchdog.pid"
if (Test-Path $WatchdogPidFile) {
    $ProcId = Get-Content $WatchdogPidFile -ErrorAction SilentlyContinue
    if ($ProcId) {
        $proc = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
            Write-Host "  Stopped watchdog (PID $ProcId)" -ForegroundColor Green
        } else {
            Write-Host "  Watchdog already stopped (PID $ProcId)" -ForegroundColor Yellow
        }
    }
    Remove-Item $WatchdogPidFile -Force
}

# Stop the background data refresh process
if (Test-Path $PidFile) {
    $ProcId = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($ProcId) {
        $proc = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
            Write-Host "  Stopped data refresh (PID $ProcId)" -ForegroundColor Green
        } else {
            Write-Host "  Data refresh already stopped (PID $ProcId)" -ForegroundColor Yellow
        }
    }
    Remove-Item $PidFile -Force
}

# Stop the HTTP server process
if (Test-Path $ServerPidFile) {
    $ProcId = Get-Content $ServerPidFile -ErrorAction SilentlyContinue
    if ($ProcId) {
        $proc = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
            Write-Host "  Stopped web server (PID $ProcId)" -ForegroundColor Green
        } else {
            Write-Host "  Web server already stopped (PID $ProcId)" -ForegroundColor Yellow
        }
    }
    Remove-Item $ServerPidFile -Force
}

# Also kill any lingering python http.server on the dashboard port
$Port = if ($DASHBOARD_PORT) { $DASHBOARD_PORT } else { 8787 }
$PortProcess = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Listen' } |
    Select-Object -ExpandProperty OwningProcess -Unique
if ($PortProcess) {
    $PortProcess | ForEach-Object {
        Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  Killed process on port $Port" -ForegroundColor Green
}

# Clean up generated refresh script
$RefreshScript = Join-Path $DASHBOARD_DIR ".refresh-loop.ps1"
if (Test-Path $RefreshScript) {
    Remove-Item $RefreshScript -Force
}

# Log the stop event
if (Test-Path $LaunchLog) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] [INFO] Dashboard stopped by stop.ps1" | Add-Content -Path $LaunchLog
}

Write-Host "Done."

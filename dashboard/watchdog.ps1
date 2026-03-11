#===============================================================================
# watchdog.ps1 - Radio Free Albany Process Watchdog (Windows)
#===============================================================================
# PURPOSE:
#   Monitors the HTTP server and data refresh loop. Automatically restarts
#   any process that dies. Runs 24/7 as a background process or scheduled task.
#
# USAGE:
#   .\dashboard\watchdog.ps1              # Run in foreground (ctrl-C to stop)
#   .\dashboard\watchdog.ps1 -Install     # Register as Windows Scheduled Task
#   .\dashboard\watchdog.ps1 -Uninstall   # Remove the scheduled task
#   .\dashboard\watchdog.ps1 -Status      # Show current process health
#
# LOGGING:
#   .\logs\watchdog.log
#===============================================================================
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status
)

#-------------------------------------------------------------------------------
# Load Configuration
#-------------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path (Split-Path -Parent $ScriptDir) "config.ps1"

if (Test-Path $ConfigFile) {
    . $ConfigFile
} else {
    $DASHBOARD_DIR = $ScriptDir
    $DASHBOARD_PORT = 8787
    $CHECK_INTERVAL = 30
    $NEWS_REFRESH_INTERVAL = 5
    $LOG_DIR = Join-Path (Split-Path -Parent $ScriptDir) "logs"
}

$DASHBOARD_DIR  = if ($DASHBOARD_DIR)  { $DASHBOARD_DIR }  else { $ScriptDir }
$LOG_DIR        = if ($LOG_DIR)        { $LOG_DIR }        else { Join-Path (Split-Path -Parent $ScriptDir) "logs" }
$Port           = if ($DASHBOARD_PORT) { $DASHBOARD_PORT } else { 8787 }
$Interval       = if ($CHECK_INTERVAL) { $CHECK_INTERVAL } else { 30 }
$NewsInterval   = if ($NEWS_REFRESH_INTERVAL) { $NEWS_REFRESH_INTERVAL } else { 5 }
$PythonCmd      = if ($PYTHON_EXE)     { $PYTHON_EXE }     else { $null }

$ServerPidFile  = Join-Path $DASHBOARD_DIR ".server.pid"
$RefreshPidFile = Join-Path $DASHBOARD_DIR ".refresh.pid"
$WatchdogPidFile= Join-Path $DASHBOARD_DIR ".watchdog.pid"
$WatchdogLog    = Join-Path $LOG_DIR "watchdog.log"
$ServerLog      = Join-Path $LOG_DIR "server.log"
$ServerErrLog   = Join-Path $LOG_DIR "server-error.log"
$RefreshLog     = Join-Path $LOG_DIR "refresh.log"
$StatsScript    = Join-Path $DASHBOARD_DIR "system-stats.ps1"
$NewsScript     = Join-Path $DASHBOARD_DIR "news-fetcher.ps1"

$WatchdogInterval = 60  # seconds between health checks
$TaskName = "RadioFreeAlbany-Watchdog"

if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

#-------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------
function Write-WatchdogLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    $line | Add-Content -Path $WatchdogLog
    if ($Level -eq "ERROR") {
        Write-Host $line -ForegroundColor Red
    } elseif ($Level -eq "WARN") {
        Write-Host $line -ForegroundColor Yellow
    } elseif ($Level -eq "OK") {
        Write-Host $line -ForegroundColor Green
    } else {
        Write-Host $line
    }
}

#-------------------------------------------------------------------------------
# Scheduled Task: Install
#-------------------------------------------------------------------------------
if ($Install) {
    Write-Host ""
    Write-Host "Installing Radio Free Albany Watchdog as Scheduled Task..." -ForegroundColor Cyan
    Write-Host ""

    # Remove existing task if present
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  Removed existing task" -ForegroundColor Yellow
    }

    $ScriptPath = $MyInvocation.MyCommand.Path
    $Action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

    # Trigger: at user logon
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

    # Settings: restart on failure, don't stop on idle, run indefinitely
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Days 0) `
        -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Description "Monitors Radio Free Albany dashboard and auto-restarts crashed processes" `
        -RunLevel Limited | Out-Null

    Write-Host "  Scheduled task '$TaskName' registered" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Trigger:  At logon ($env:USERNAME)" -ForegroundColor White
    Write-Host "  Action:   watchdog.ps1 (hidden window)" -ForegroundColor White
    Write-Host "  Restarts: Up to 3 on failure (1 min apart)" -ForegroundColor White
    Write-Host ""
    Write-Host "  To start now:   Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Cyan
    Write-Host "  To remove:      .\dashboard\watchdog.ps1 -Uninstall" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

#-------------------------------------------------------------------------------
# Scheduled Task: Uninstall
#-------------------------------------------------------------------------------
if ($Uninstall) {
    Write-Host ""
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task '$TaskName' removed." -ForegroundColor Green
    } else {
        Write-Host "No scheduled task '$TaskName' found." -ForegroundColor Yellow
    }

    # Also stop any running watchdog process
    if (Test-Path $WatchdogPidFile) {
        $wdPid = Get-Content $WatchdogPidFile -ErrorAction SilentlyContinue
        if ($wdPid) {
            $proc = Get-Process -Id $wdPid -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-Process -Id $wdPid -Force -ErrorAction SilentlyContinue
                Write-Host "Stopped running watchdog (PID $wdPid)" -ForegroundColor Green
            }
        }
        Remove-Item $WatchdogPidFile -Force
    }
    Write-Host ""
    exit 0
}

#-------------------------------------------------------------------------------
# Status Check (one-shot, no loop)
#-------------------------------------------------------------------------------
if ($Status) {
    Write-Host ""
    Write-Host "+==================================================+" -ForegroundColor Cyan
    Write-Host "|     Radio Free Albany - Watchdog Status           |" -ForegroundColor Cyan
    Write-Host "+==================================================+" -ForegroundColor Cyan
    Write-Host ""

    # Watchdog process
    $wdAlive = $false
    if (Test-Path $WatchdogPidFile) {
        $wdPid = Get-Content $WatchdogPidFile -ErrorAction SilentlyContinue
        if ($wdPid) {
            $proc = Get-Process -Id $wdPid -ErrorAction SilentlyContinue
            if ($proc) { $wdAlive = $true }
        }
    }
    if ($wdAlive) {
        Write-Host "  Watchdog:     PID $wdPid" -ForegroundColor Green
    } else {
        Write-Host "  Watchdog:     NOT RUNNING" -ForegroundColor Red
    }

    # HTTP Server
    $serverAlive = $false
    $serverPid = $null
    if (Test-Path $ServerPidFile) {
        $serverPid = Get-Content $ServerPidFile -ErrorAction SilentlyContinue
        if ($serverPid) {
            $proc = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
            if ($proc) { $serverAlive = $true }
        }
    }
    $portListening = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Listen' }

    if ($serverAlive -and $portListening) {
        Write-Host "  HTTP Server:  PID $serverPid on port $Port" -ForegroundColor Green
    } elseif ($portListening) {
        Write-Host "  HTTP Server:  Port $Port listening (PID unknown)" -ForegroundColor Yellow
    } else {
        Write-Host "  HTTP Server:  DOWN" -ForegroundColor Red
    }

    # Refresh Loop
    $refreshAlive = $false
    $refreshPid = $null
    if (Test-Path $RefreshPidFile) {
        $refreshPid = Get-Content $RefreshPidFile -ErrorAction SilentlyContinue
        if ($refreshPid) {
            $proc = Get-Process -Id $refreshPid -ErrorAction SilentlyContinue
            if ($proc) { $refreshAlive = $true }
        }
    }
    if ($refreshAlive) {
        Write-Host "  Data Refresh: PID $refreshPid" -ForegroundColor Green
    } else {
        Write-Host "  Data Refresh: DOWN" -ForegroundColor Red
    }

    # Scheduled Task
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "  Sched. Task:  $($task.State)" -ForegroundColor Green
    } else {
        Write-Host "  Sched. Task:  Not installed" -ForegroundColor Yellow
    }

    # Recent log entries
    Write-Host ""
    Write-Host "  Recent watchdog log:" -ForegroundColor Cyan
    if (Test-Path $WatchdogLog) {
        Get-Content $WatchdogLog -Tail 8 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "    (no log yet)" -ForegroundColor DarkGray
    }
    Write-Host ""
    exit 0
}

#===============================================================================
# MAIN WATCHDOG LOOP
#===============================================================================

# Prevent duplicate watchdog instances
if (Test-Path $WatchdogPidFile) {
    $existingPid = Get-Content $WatchdogPidFile -ErrorAction SilentlyContinue
    if ($existingPid) {
        $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($existingProc) {
            Write-WatchdogLog "Another watchdog is already running (PID $existingPid). Exiting." "WARN"
            exit 0
        }
    }
}

# Write our PID
$PID | Set-Content $WatchdogPidFile
Write-WatchdogLog "Watchdog started (PID $PID)"
Write-WatchdogLog "Monitoring port $Port | Check interval: ${WatchdogInterval}s"

$restartCount = 0

#-------------------------------------------------------------------------------
# Restart Functions
#-------------------------------------------------------------------------------
function Restart-HttpServer {
    if (-not $PythonCmd) {
        Write-WatchdogLog "Cannot restart HTTP server - Python not found" "ERROR"
        return $false
    }

    # Kill any zombie on the port first
    $zombies = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Listen' } |
        Select-Object -ExpandProperty OwningProcess -Unique
    if ($zombies) {
        $zombies | ForEach-Object {
            Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
    }

    # Start fresh Flask DJ server
    $DjServer = Join-Path $DASHBOARD_DIR "dj-server.py"
    $proc = Start-Process -FilePath $PythonCmd `
        -ArgumentList $DjServer, "--port", $Port, "--host", "127.0.0.1", "--directory", $DASHBOARD_DIR `
        -WindowStyle Hidden `
        -RedirectStandardOutput $ServerLog `
        -RedirectStandardError $ServerErrLog `
        -PassThru

    $proc.Id | Set-Content $ServerPidFile
    Start-Sleep -Seconds 2

    $listening = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Listen' }

    if ($listening) {
        Write-WatchdogLog "HTTP server restarted (PID $($proc.Id)) on port $Port" "OK"
        return $true
    } else {
        Write-WatchdogLog "HTTP server restart failed - not listening after 2s" "ERROR"
        return $false
    }
}

function Restart-RefreshLoop {
    $RefreshScript = Join-Path $DASHBOARD_DIR ".refresh-loop.ps1"

    # Regenerate the refresh loop script (it may have been cleaned up by stop.ps1)
    if (-not (Test-Path $RefreshScript)) {
        @"
`$ErrorActionPreference = 'Continue'
`$logFile = '$RefreshLog'

function Write-RefreshLog {
    param([string]`$Message)
    `$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[`$ts] `$Message" | Add-Content -Path `$logFile
}

Write-RefreshLog "Refresh loop started (PID `$PID) [watchdog restart]"
Write-RefreshLog "Stats: every $Interval seconds | News: every $NewsInterval minutes"

while (`$true) {
    Start-Sleep -Seconds $Interval
    try {
        & '$StatsScript' 2>`$null
    } catch {
        Write-RefreshLog "Stats refresh error: `$_"
    }
    `$min = (Get-Date).Minute
    if ((`$min % $NewsInterval) -eq 0) {
        try {
            & '$NewsScript' 2>`$null
            Write-RefreshLog "News refreshed"
        } catch {
            Write-RefreshLog "News refresh error: `$_"
        }
    }
}
"@ | Set-Content -Path $RefreshScript -Encoding UTF8
    }

    $proc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $RefreshScript `
        -WindowStyle Hidden `
        -PassThru

    $proc.Id | Set-Content $RefreshPidFile
    Start-Sleep -Seconds 1

    $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($alive) {
        Write-WatchdogLog "Refresh loop restarted (PID $($proc.Id))" "OK"
        return $true
    } else {
        Write-WatchdogLog "Refresh loop restart failed" "ERROR"
        return $false
    }
}

#-------------------------------------------------------------------------------
# Main Loop
#-------------------------------------------------------------------------------
try {
    while ($true) {
        $issues = @()

        # CHECK 1: HTTP Server alive on port?
        $portListening = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Listen' }

        if (-not $portListening) {
            $issues += "HTTP server down"
            Write-WatchdogLog "HTTP server not listening on port $Port - restarting" "WARN"
            Restart-HttpServer
            $restartCount++
        }

        # CHECK 2: Refresh loop PID alive?
        $refreshAlive = $false
        if (Test-Path $RefreshPidFile) {
            $rPid = Get-Content $RefreshPidFile -ErrorAction SilentlyContinue
            if ($rPid) {
                $proc = Get-Process -Id $rPid -ErrorAction SilentlyContinue
                if ($proc) { $refreshAlive = $true }
            }
        }

        if (-not $refreshAlive) {
            $issues += "Refresh loop down"
            Write-WatchdogLog "Refresh loop not running - restarting" "WARN"
            Restart-RefreshLoop
            $restartCount++
        }

        # Log periodic heartbeat (every 10 checks = ~10 min)
        if (($restartCount -eq 0) -and ((Get-Date).Minute % 10 -eq 0) -and ((Get-Date).Second -lt $WatchdogInterval)) {
            Write-WatchdogLog "Heartbeat: all systems operational"
        }

        Start-Sleep -Seconds $WatchdogInterval
    }
} finally {
    # Cleanup PID file on exit
    if (Test-Path $WatchdogPidFile) {
        Remove-Item $WatchdogPidFile -Force -ErrorAction SilentlyContinue
    }
    Write-WatchdogLog "Watchdog stopped"
}

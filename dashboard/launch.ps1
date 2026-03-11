#===============================================================================
# launch.ps1 - Command Center Dashboard Launcher (Windows)
#===============================================================================
# PURPOSE:
#   Starts the complete Command Center ecosystem including:
#   - Initial data fetch (system stats + news)
#   - Background refresh loop (stats every 30s, news every 5min)
#   - Python HTTP server for the web dashboard
#   - Opens dashboard in default browser
#
# USAGE:
#   .\system-monitor\dashboard\launch.ps1
#
# TO STOP:
#   .\system-monitor\dashboard\stop.ps1
#
# PORTS:
#   Dashboard served on http://localhost:8787
#
# LOGS:
#   .\system-monitor\logs\launcher.log    - Launch events
#   .\system-monitor\logs\server.log      - HTTP server output
#   .\system-monitor\logs\refresh.log     - Background refresh output
#===============================================================================

#-------------------------------------------------------------------------------
# Load Configuration
#-------------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path (Split-Path -Parent $ScriptDir) "config.ps1"

if (Test-Path $ConfigFile) {
    . $ConfigFile
} else {
    Write-Host "Warning: config.ps1 not found, using defaults" -ForegroundColor Yellow
    $DASHBOARD_DIR = $ScriptDir
    $DASHBOARD_PORT = 8787
    $CHECK_INTERVAL = 30
    $NEWS_REFRESH_INTERVAL = 5
    $ENABLE_BROWSER_OPEN = 1
    $LOG_DIR = Join-Path (Split-Path -Parent $ScriptDir) "logs"
}

$DASHBOARD_DIR = if ($DASHBOARD_DIR) { $DASHBOARD_DIR } else { $ScriptDir }
$LOG_DIR = if ($LOG_DIR) { $LOG_DIR } else { Join-Path (Split-Path -Parent $ScriptDir) "logs" }
$PidFile = Join-Path $DASHBOARD_DIR ".refresh.pid"
$ServerPidFile = Join-Path $DASHBOARD_DIR ".server.pid"
$Port = if ($DASHBOARD_PORT) { $DASHBOARD_PORT } else { 8787 }
$Interval = if ($CHECK_INTERVAL) { $CHECK_INTERVAL } else { 30 }
$NewsInterval = if ($NEWS_REFRESH_INTERVAL) { $NEWS_REFRESH_INTERVAL } else { 5 }

# Ensure log directory exists
if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

$LaunchLog = Join-Path $LOG_DIR "launcher.log"
$ServerLog = Join-Path $LOG_DIR "server.log"
$ServerErrLog = Join-Path $LOG_DIR "server-error.log"
$RefreshLog = Join-Path $LOG_DIR "refresh.log"

#-------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    $line | Add-Content -Path $LaunchLog
    if ($Level -eq "ERROR") {
        Write-Host $line -ForegroundColor Red
    } elseif ($Level -eq "WARN") {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line
    }
}

Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host "|       Radio Free Albany - Launcher           |" -ForegroundColor Cyan
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host ""

Write-Log "Dashboard launcher starting"
Write-Log "DASHBOARD_DIR: $DASHBOARD_DIR"
Write-Log "PYTHON_EXE: $PYTHON_EXE"
Write-Log "Port: $Port | Refresh: ${Interval}s | News: ${NewsInterval}min"

#-------------------------------------------------------------------------------
# Cleanup - Kill any existing processes from previous runs
#-------------------------------------------------------------------------------
if (Test-Path $ServerPidFile) {
    $OldPid = Get-Content $ServerPidFile -ErrorAction SilentlyContinue
    if ($OldPid) {
        $proc = Get-Process -Id $OldPid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $OldPid -Force -ErrorAction SilentlyContinue
            Write-Log "Killed old server process (PID $OldPid)"
        }
    }
    Remove-Item $ServerPidFile -Force
}

if (Test-Path $PidFile) {
    $OldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($OldPid) {
        $proc = Get-Process -Id $OldPid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $OldPid -Force -ErrorAction SilentlyContinue
            Write-Log "Killed old refresh process (PID $OldPid)"
        }
    }
    Remove-Item $PidFile -Force
}

# Kill any existing server on our port
$PortProcess = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Listen' } |
    Select-Object -ExpandProperty OwningProcess -Unique
if ($PortProcess) {
    $PortProcess | ForEach-Object {
        Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
        Write-Log "Killed existing process on port $Port (PID $_)"
    }
}

#-------------------------------------------------------------------------------
# Step 1: Initial Data Fetch
#-------------------------------------------------------------------------------
Write-Host ""
Write-Host "[1/4] " -ForegroundColor Green -NoNewline
Write-Host "Fetching initial data..."

$StatsScript = Join-Path $DASHBOARD_DIR "system-stats.ps1"
$NewsScript = Join-Path $DASHBOARD_DIR "news-fetcher.ps1"

if (Test-Path $StatsScript) {
    try {
        & $StatsScript
        Write-Log "Initial stats fetch OK"
    } catch {
        Write-Log "Stats fetch failed: $_" "ERROR"
    }
}
if (Test-Path $NewsScript) {
    try {
        & $NewsScript
        Write-Log "Initial news fetch OK"
    } catch {
        Write-Log "News fetch failed: $_" "ERROR"
    }
}

#-------------------------------------------------------------------------------
# Step 2: Start HTTP Server (as a real OS process - survives terminal close)
#-------------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/4] " -ForegroundColor Green -NoNewline
Write-Host "Starting web server on port $Port..."

$PythonCmd = if ($PYTHON_EXE) { $PYTHON_EXE } else { $null }

if ($PythonCmd) {
    # Start Flask DJ server as a detached process
    $DjServer = Join-Path $DASHBOARD_DIR "dj-server.py"
    $ServerProc = Start-Process -FilePath $PythonCmd `
        -ArgumentList $DjServer, "--port", $Port, "--host", "127.0.0.1", "--directory", $DASHBOARD_DIR `
        -WindowStyle Hidden `
        -RedirectStandardOutput $ServerLog `
        -RedirectStandardError $ServerErrLog `
        -PassThru

    $ServerProc.Id | Set-Content $ServerPidFile
    Write-Log "HTTP server started (PID $($ServerProc.Id)) on port $Port"

    # Wait and verify it's actually listening
    Start-Sleep -Seconds 2
    $listening = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Listen' }
    if ($listening) {
        Write-Log "HTTP server verified listening on port $Port"
    } else {
        Write-Log "HTTP server may not be listening - check $ServerErrLog" "WARN"
        if (Test-Path $ServerErrLog) {
            $errContent = Get-Content $ServerErrLog -Tail 5 -ErrorAction SilentlyContinue
            if ($errContent) {
                Write-Log "Server stderr: $($errContent -join ' | ')" "ERROR"
            }
        }
    }
} else {
    Write-Log "Python not found - cannot start HTTP server" "ERROR"
}

#-------------------------------------------------------------------------------
# Step 3: Start Background Refresh Loop (as a detached PowerShell process)
#-------------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/4] " -ForegroundColor Green -NoNewline
Write-Host "Starting background refresh (every ${Interval}s)..."

# Write the refresh loop as a standalone script so it runs independently
$RefreshScript = Join-Path $DASHBOARD_DIR ".refresh-loop.ps1"
@"
`$ErrorActionPreference = 'Continue'
`$logFile = '$RefreshLog'

function Write-RefreshLog {
    param([string]`$Message)
    `$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[`$ts] `$Message" | Add-Content -Path `$logFile
}

Write-RefreshLog "Refresh loop started (PID `$PID)"
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

$RefreshProc = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $RefreshScript `
    -WindowStyle Hidden `
    -PassThru

$RefreshProc.Id | Set-Content $PidFile
Write-Log "Refresh loop started (PID $($RefreshProc.Id))"

#-------------------------------------------------------------------------------
# Step 4: Open Dashboard in Browser
#-------------------------------------------------------------------------------
$DashboardUrl = "http://localhost:$Port/index.html"

Write-Host ""
if ($ENABLE_BROWSER_OPEN -eq 1) {
    Write-Host "[4/4] " -ForegroundColor Green -NoNewline
    Write-Host "Opening dashboard in browser..."
    Start-Process $DashboardUrl
    Write-Log "Browser opened: $DashboardUrl"
} else {
    Write-Host "[4/4] " -ForegroundColor Green -NoNewline
    Write-Host "Browser auto-open disabled"
}

#-------------------------------------------------------------------------------
# Verify everything is running
#-------------------------------------------------------------------------------
Start-Sleep -Seconds 1
$serverAlive = Get-Process -Id (Get-Content $ServerPidFile) -ErrorAction SilentlyContinue
$refreshAlive = Get-Process -Id (Get-Content $PidFile) -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Dashboard launched!" -ForegroundColor Green
Write-Host ""
Write-Host "Dashboard URL: " -NoNewline
Write-Host $DashboardUrl -ForegroundColor Cyan
Write-Host ""
Write-Host "Background processes:"
if ($serverAlive) {
    Write-Host "  Web server:   PID $(Get-Content $ServerPidFile) on port $Port" -ForegroundColor Green
} else {
    Write-Host "  Web server:   FAILED - check $ServerErrLog" -ForegroundColor Red
}
if ($refreshAlive) {
    Write-Host "  Data refresh: PID $(Get-Content $PidFile)" -ForegroundColor Green
} else {
    Write-Host "  Data refresh: FAILED - check $RefreshLog" -ForegroundColor Red
}
Write-Host ""
Write-Host "Logs:"
Write-Host "  $LaunchLog"
Write-Host "  $ServerLog"
Write-Host "  $RefreshLog"
Write-Host ""
Write-Host "To stop: .\dashboard\stop.ps1" -ForegroundColor Cyan
Write-Host ""

Write-Log "Launch complete - server=$(if($serverAlive){'OK'}else{'FAILED'}) refresh=$(if($refreshAlive){'OK'}else{'FAILED'})"

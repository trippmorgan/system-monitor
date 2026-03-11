$ErrorActionPreference = 'Continue'
$logFile = 'C:\Users\PlayoutONE\system-monitor\logs\refresh.log'

function Write-RefreshLog {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $Message" | Add-Content -Path $logFile
}

Write-RefreshLog "Refresh loop started (PID $PID)"
Write-RefreshLog "Stats: every 30 seconds | News: every 2 minutes"

while ($true) {
    Start-Sleep -Seconds 30
    try {
        & 'C:\Users\PlayoutONE\system-monitor\dashboard\system-stats.ps1' 2>$null
    } catch {
        Write-RefreshLog "Stats refresh error: $_"
    }
    $min = (Get-Date).Minute
    if (($min % 2) -eq 0) {
        try {
            & 'C:\Users\PlayoutONE\system-monitor\dashboard\news-fetcher.ps1' 2>$null
            Write-RefreshLog "News refreshed"
        } catch {
            Write-RefreshLog "News refresh error: $_"
        }
    }
}

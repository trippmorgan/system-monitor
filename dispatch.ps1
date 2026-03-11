#===============================================================================
# dispatch.ps1 - Agent Selection Menu (Windows)
#===============================================================================

$MonitorHome = if ($env:MONITOR_HOME) { $env:MONITOR_HOME } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

Clear-Host
Write-Host "+========================================+" -ForegroundColor Cyan
Write-Host "|       SYSTEM MONITOR DISPATCH          |" -ForegroundColor Cyan
Write-Host "+========================================+" -ForegroundColor Cyan
Write-Host "|  1) System Tech   - health & services  |"
Write-Host "|  2) News Curator  - headlines & news   |"
Write-Host "|  3) Orchestrator  - help me decide     |"
Write-Host "|  0) Exit                               |"
Write-Host "+========================================+" -ForegroundColor Cyan
Write-Host ""

$choice = Read-Host "Select agent [1-3]"

switch ($choice) {
    '1' {
        Write-Host "Launching System Tech agent..."
        $AgentDir = Join-Path $MonitorHome "agents\system-tech"
        if (Test-Path $AgentDir) {
            Set-Location $AgentDir
            if (Get-Command claude -ErrorAction SilentlyContinue) {
                & claude
            } else {
                Write-Host "Claude CLI not found." -ForegroundColor Red
            }
        } else {
            Write-Host "Agent directory not found: $AgentDir" -ForegroundColor Red
        }
    }
    '2' {
        Write-Host "Launching News Curator agent..."
        $AgentDir = Join-Path $MonitorHome "agents\news-curator"
        if (Test-Path $AgentDir) {
            Set-Location $AgentDir
            if (Get-Command claude -ErrorAction SilentlyContinue) {
                & claude
            } else {
                Write-Host "Claude CLI not found." -ForegroundColor Red
            }
        } else {
            Write-Host "Agent directory not found: $AgentDir" -ForegroundColor Red
        }
    }
    '3' {
        Write-Host "Launching Orchestrator..."
        $AgentDir = Join-Path $MonitorHome "agents\orchestrator"
        if (Test-Path $AgentDir) {
            Set-Location $AgentDir
            if (Get-Command claude -ErrorAction SilentlyContinue) {
                & claude
            } else {
                Write-Host "Claude CLI not found." -ForegroundColor Red
            }
        } else {
            Write-Host "Agent directory not found: $AgentDir" -ForegroundColor Red
        }
    }
    '0' {
        Write-Host "Goodbye."
        exit 0
    }
    default {
        Write-Host "Invalid choice." -ForegroundColor Red
        exit 1
    }
}

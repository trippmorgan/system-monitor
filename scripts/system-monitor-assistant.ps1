#===============================================================================
# system-monitor-assistant.ps1 - Continuous Background Monitor (Windows)
#===============================================================================
# PURPOSE:
#   Monitors system metrics continuously and alerts only on significant changes.
#   Checks metrics every 30 seconds.
#
# USAGE:
#   .\system-monitor\scripts\system-monitor-assistant.ps1
#
# FEATURES:
#   - Change-based alerting (only alerts when values change)
#   - Two-tier thresholds: WARNING and CRITICAL for each metric
#   - Windows service monitoring
#   - Auto-refreshes dashboard data when changes detected
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
    $LOG_DIR = "$env:USERPROFILE\system-monitor\logs"
    $DASHBOARD_DIR = "$env:USERPROFILE\system-monitor\dashboard"
    $CPU_WARN = 70; $CPU_CRIT = 90
    $MEM_WARN = 70; $MEM_CRIT = 90
    $DISK_WARN = 80; $DISK_CRIT = 90
    $GPU_TEMP_WARN = 70; $GPU_TEMP_CRIT = 85
    $CHECK_INTERVAL = 30
    $ENABLE_GPU_MONITORING = 1
}

$ALERT_LOG = if ($ALERT_LOG) { $ALERT_LOG } else { Join-Path $LOG_DIR "alerts.log" }

if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------
function Write-LogAlert {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] ALERT: $Message" | Add-Content -Path $ALERT_LOG
    Write-Host "[ALERT] $Message" -ForegroundColor Red
}

function Write-LogInfo {
    param([string]$Message)
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] $Message"
}

#-------------------------------------------------------------------------------
# Data Collection
#-------------------------------------------------------------------------------
function Get-CurrentStats {
    # CPU usage percentage
    try {
        $cpuLoad = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue, 0)
    } catch {
        $cpuLoad = 0
    }

    # Memory percentage
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $memPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 0)
    } catch {
        $memPct = 0
    }

    # Disk percentage (C: drive)
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 0)
    } catch {
        $diskPct = 0
    }

    # GPU temperature
    $gpuTemp = 0
    if ($ENABLE_GPU_MONITORING -eq 1 -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        try {
            $gpuTemp = [int](& nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null)
        } catch {
            $gpuTemp = 0
        }
    }

    # Service status checks
    $services = @{}
    $svcList = if ($MONITORED_SERVICES) { $MONITORED_SERVICES } else { @('Spooler', 'W32Time', 'Winmgmt', 'WinRM') }
    foreach ($svcName in $svcList) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $services[$svcName] = $svc.Status.ToString().ToLower()
        } else {
            $services[$svcName] = "not_found"
        }
    }

    return @{
        cpu = $cpuLoad
        mem = $memPct
        disk = $diskPct
        gpu_temp = $gpuTemp
        services = $services
    }
}

#-------------------------------------------------------------------------------
# Alert Logic
#-------------------------------------------------------------------------------
function Compare-AndAlert {
    param([hashtable]$Stats)

    # CPU check
    if ($Stats.cpu -gt $CPU_CRIT) {
        Write-LogAlert "CRITICAL: CPU at $($Stats.cpu)% (threshold: ${CPU_CRIT}%)"
    } elseif ($Stats.cpu -gt $CPU_WARN) {
        Write-LogAlert "WARNING: CPU at $($Stats.cpu)% (threshold: ${CPU_WARN}%)"
    }

    # Memory check
    if ($Stats.mem -gt $MEM_CRIT) {
        Write-LogAlert "CRITICAL: Memory at $($Stats.mem)% (threshold: ${MEM_CRIT}%)"
    } elseif ($Stats.mem -gt $MEM_WARN) {
        Write-LogAlert "WARNING: Memory at $($Stats.mem)% (threshold: ${MEM_WARN}%)"
    }

    # Disk check
    if ($Stats.disk -gt $DISK_CRIT) {
        Write-LogAlert "CRITICAL: Disk at $($Stats.disk)% (threshold: ${DISK_CRIT}%)"
    } elseif ($Stats.disk -gt $DISK_WARN) {
        Write-LogAlert "WARNING: Disk at $($Stats.disk)% (threshold: ${DISK_WARN}%)"
    }

    # GPU temperature check
    if ($Stats.gpu_temp -gt $GPU_TEMP_CRIT) {
        Write-LogAlert "CRITICAL: GPU temperature at $($Stats.gpu_temp)C (threshold: ${GPU_TEMP_CRIT}C)"
    } elseif ($Stats.gpu_temp -gt $GPU_TEMP_WARN) {
        Write-LogAlert "WARNING: GPU temperature at $($Stats.gpu_temp)C (threshold: ${GPU_TEMP_WARN}C)"
    }

    # Service checks
    foreach ($svcName in $Stats.services.Keys) {
        if ($Stats.services[$svcName] -ne 'running') {
            Write-LogAlert "Service DOWN: $svcName is $($Stats.services[$svcName])"
        }
    }
}

#-------------------------------------------------------------------------------
# Dashboard Integration
#-------------------------------------------------------------------------------
function Update-Dashboard {
    Write-LogInfo "Refreshing dashboard data..."
    $statsScript = Join-Path $DASHBOARD_DIR "system-stats.ps1"
    if (Test-Path $statsScript) {
        & $statsScript 2>$null
    }
}

#===============================================================================
# Main Monitoring Loop
#===============================================================================
Write-Host ""
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host "|      System Monitor Assistant Started        |" -ForegroundColor Cyan
Write-Host "+==============================================+" -ForegroundColor Cyan
Write-Host ""
Write-LogInfo "Monitoring system... (Ctrl+C to stop)"
Write-LogInfo "Thresholds: CPU=${CPU_WARN}/${CPU_CRIT}% | MEM=${MEM_WARN}/${MEM_CRIT}% | DISK=${DISK_WARN}/${DISK_CRIT}% | GPU=${GPU_TEMP_WARN}/${GPU_TEMP_CRIT}C"
Write-Host ""

$LastStatsHash = ""
$Interval = if ($CHECK_INTERVAL) { $CHECK_INTERVAL } else { 30 }

while ($true) {
    $CurrentStats = Get-CurrentStats
    $CurrentHash = ($CurrentStats | ConvertTo-Json -Compress)

    if ($CurrentHash -ne $LastStatsHash) {
        Compare-AndAlert -Stats $CurrentStats
        Update-Dashboard
        $LastStatsHash = $CurrentHash
    }

    Write-LogInfo "Status: CPU=$($CurrentStats.cpu)% | MEM=$($CurrentStats.mem)% | Sleeping ${Interval}s..."
    Start-Sleep -Seconds $Interval
}

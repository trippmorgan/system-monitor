#===============================================================================
# system-stats.ps1 - System Statistics JSON Generator (Windows)
#===============================================================================
# PURPOSE:
#   Collects current system metrics and outputs them as JSON for the
#   Radio Free Albany web dashboard. Called by the background refresh loop.
#
# USAGE:
#   .\system-monitor\dashboard\system-stats.ps1
#
# OUTPUT:
#   .\system-monitor\dashboard\news-cache\stats.json
#
# METRICS COLLECTED:
#   - CPU utilization percentage and core count
#   - Memory usage (used, total, percent)
#   - Disk usage (percent, available)
#   - GPU stats (temp, utilization, VRAM) - NVIDIA only
#   - System uptime (text and days)
#   - Network connections (established TCP)
#   - Service status (configurable Windows services)
#   - Recent alerts count and messages
#===============================================================================

#-------------------------------------------------------------------------------
# Load Configuration
#-------------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path (Split-Path -Parent $ScriptDir) "config.ps1"

if (Test-Path $ConfigFile) {
    . $ConfigFile
} else {
    $MONITOR_HOME = "$env:USERPROFILE\Documents\system-monitor"
    $NEWS_CACHE_DIR = "$MONITOR_HOME\dashboard\news-cache"
    $LOG_DIR = "$MONITOR_HOME\logs"
    $ENABLE_GPU_MONITORING = 1
}

$StatsFile = "$NEWS_CACHE_DIR\stats.json"
$AlertLog = "$LOG_DIR\alerts.log"

#-------------------------------------------------------------------------------
# Collect System Metrics
#-------------------------------------------------------------------------------

# CPU utilization (percentage) and core count
try {
    $CpuLoad = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue, 2)
} catch {
    $CpuLoad = 0
}
$Cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

# Memory usage in MB
$OS = Get-CimInstance Win32_OperatingSystem
$MemTotalMB = [math]::Round($OS.TotalVisibleMemorySize / 1KB, 0)
$MemFreeMB = [math]::Round($OS.FreePhysicalMemory / 1KB, 0)
$MemUsedMB = $MemTotalMB - $MemFreeMB
$MemPct = [math]::Round(($MemUsedMB / $MemTotalMB) * 100, 0)

# Disk usage for C: drive
$Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$DiskPct = [math]::Round((($Disk.Size - $Disk.FreeSpace) / $Disk.Size) * 100, 0)
$DiskAvailGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
$DiskAvail = "$DiskAvailGB GB"

# GPU stats via nvidia-smi (gracefully handles missing GPU)
$GpuTemp = "N/A"
$GpuUtil = "N/A"
$GpuMem = "N/A"

if ($ENABLE_GPU_MONITORING -eq 1) {
    $NvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($NvidiaSmi) {
        try {
            $GpuInfo = & nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null
            if ($GpuInfo) {
                $GpuData = $GpuInfo -split ','
                $GpuTemp = $GpuData[0].Trim()
                $GpuUtil = $GpuData[1].Trim()
                $GpuMemUsed = $GpuData[2].Trim()
                $GpuMemTotal = $GpuData[3].Trim()
                $GpuMem = "$GpuMemUsed/$GpuMemTotal"
            }
        } catch {
            # Silently handle GPU query failures
        }
    }
}

# System uptime (human-readable and raw days)
$BootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$UptimeSpan = (Get-Date) - $BootTime
$UptimeDays = [math]::Floor($UptimeSpan.TotalDays)
$UptimeHours = $UptimeSpan.Hours
$UptimeMinutes = $UptimeSpan.Minutes

if ($UptimeDays -gt 0) {
    $UptimeText = "$UptimeDays days, $UptimeHours hours"
} elseif ($UptimeHours -gt 0) {
    $UptimeText = "$UptimeHours hours, $UptimeMinutes minutes"
} else {
    $UptimeText = "$UptimeMinutes minutes"
}

# Network connections (established TCP connections)
try {
    $NetConn = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
} catch {
    $NetConn = 0
}

# Service status checks
$ServiceStatus = @{}
if ($MONITORED_SERVICES) {
    foreach ($ServiceName in $MONITORED_SERVICES) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($Service) {
            $ServiceStatus[$ServiceName] = $Service.Status.ToString().ToLower()
        } else {
            $ServiceStatus[$ServiceName] = "not_found"
        }
    }
} else {
    # Default services to check
    $DefaultServices = @('Spooler', 'W32Time', 'Winmgmt', 'WinRM')
    foreach ($ServiceName in $DefaultServices) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($Service) {
            $ServiceStatus[$ServiceName] = $Service.Status.ToString().ToLower()
        } else {
            $ServiceStatus[$ServiceName] = "not_found"
        }
    }
}

# Alert count and recent alerts
$AlertCount = 0
$RecentAlerts = ""
if (Test-Path $AlertLog) {
    $AlertCount = (Get-Content $AlertLog | Measure-Object -Line).Lines
    $RecentAlertLines = Get-Content $AlertLog -Tail 3 -ErrorAction SilentlyContinue
    if ($RecentAlertLines) {
        $RecentAlerts = ($RecentAlertLines | ForEach-Object { $_ -replace '"', '\"' }) -join '|'
    }
}

#-------------------------------------------------------------------------------
# Build JSON object
#-------------------------------------------------------------------------------
$Stats = @{
    timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    cpu = @{
        load = $CpuLoad
        cores = $Cores
    }
    memory = @{
        used = $MemUsedMB
        total = $MemTotalMB
        percent = $MemPct
    }
    disk = @{
        percent = $DiskPct
        available = $DiskAvail
    }
    gpu = @{
        temp = $GpuTemp
        util = $GpuUtil
        mem = $GpuMem
    }
    uptime = @{
        text = $UptimeText
        days = $UptimeDays
    }
    network = @{
        connections = $NetConn
    }
    services = $ServiceStatus
    alerts = @{
        count = $AlertCount
        recent = $RecentAlerts
    }
}

#-------------------------------------------------------------------------------
# Output JSON to file
#-------------------------------------------------------------------------------
# Ensure directory exists
if (-not (Test-Path (Split-Path $StatsFile -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path $StatsFile -Parent) -Force | Out-Null
}

# Write JSON with proper formatting
$Stats | ConvertTo-Json -Depth 5 | Set-Content -Path $StatsFile -Encoding UTF8

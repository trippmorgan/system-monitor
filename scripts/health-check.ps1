#===============================================================================
# health-check.ps1 - System Health Check Script (Windows)
#===============================================================================
# PURPOSE:
#   Generates a comprehensive daily health report for system monitoring.
#   Checks CPU, memory, disk, GPU, services, and event logs.
#
# USAGE:
#   .\system-monitor\scripts\health-check.ps1
#
# OUTPUT:
#   - Daily report: .\system-monitor\logs\daily-report-YYYY-MM-DD.log
#   - Alerts:       .\system-monitor\logs\alerts.log (appended)
#
# SCHEDULING:
#   Use Task Scheduler to run daily at 8:00 AM
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
    $MEM_CRIT = 90
    $SWAP_WARN = 50
    $DISK_WARN = 80
    $GPU_TEMP_CRIT = 80
    $UPTIME_CRIT = 30
    $EVENT_ERROR_THRESHOLD = 100
    $ENABLE_GPU_MONITORING = 1
}

$ALERT_LOG = if ($ALERT_LOG) { $ALERT_LOG } else { Join-Path $LOG_DIR "alerts.log" }
$Date = Get-Date -Format 'yyyy-MM-dd'
$Time = Get-Date -Format 'HH:mm:ss'
$Report = Join-Path $LOG_DIR "daily-report-$Date.log"

if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------
function Write-Alert {
    param([string]$Message)
    "[$Date $Time] ALERT: $Message" | Add-Content -Path $ALERT_LOG
    Write-Host "[ALERT] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    $Message | Add-Content -Path $Report
    Write-Host $Message
}

#-------------------------------------------------------------------------------
# Report Header
#-------------------------------------------------------------------------------
"=============================================" | Add-Content -Path $Report
"System Health Report - $Date $Time" | Add-Content -Path $Report
"=============================================" | Add-Content -Path $Report
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# CPU Load Check
#-------------------------------------------------------------------------------
Write-Info "--- CPU Load ---"
try {
    $CpuLoad = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue, 2)
} catch {
    $CpuLoad = 0
}
$Cores = $env:NUMBER_OF_PROCESSORS
Write-Info "CPU Usage: ${CpuLoad}% (Cores: $Cores)"
$CpuWarnThreshold = if ($CPU_WARN) { $CPU_WARN } else { 70 }
if ($CpuLoad -gt $CpuWarnThreshold) {
    Write-Alert "High CPU usage: ${CpuLoad}% (threshold: ${CpuWarnThreshold}%)"
}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# Memory Usage Check
#-------------------------------------------------------------------------------
Write-Info "--- Memory Usage ---"
$OS = Get-CimInstance Win32_OperatingSystem
$MemTotalMB = [math]::Round($OS.TotalVisibleMemorySize / 1KB, 0)
$MemFreeMB = [math]::Round($OS.FreePhysicalMemory / 1KB, 0)
$MemUsedMB = $MemTotalMB - $MemFreeMB
$MemPercent = [math]::Round(($MemUsedMB / $MemTotalMB) * 100, 0)
Write-Info "Memory: ${MemUsedMB}MB / ${MemTotalMB}MB (${MemPercent}%)"
if ($MemPercent -gt $MEM_CRIT) {
    Write-Alert "High memory usage: ${MemPercent}% (threshold: ${MEM_CRIT}%)"
}

# Page file (swap equivalent)
try {
    $PageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    if ($PageFile) {
        $SwapTotal = $PageFile.AllocatedBaseSize
        $SwapUsed = $PageFile.CurrentUsage
        if ($SwapTotal -gt 0) {
            $SwapPercent = [math]::Round(($SwapUsed / $SwapTotal) * 100, 0)
            Write-Info "Page File: ${SwapUsed}MB / ${SwapTotal}MB (${SwapPercent}%)"
            if ($SwapPercent -gt $SWAP_WARN) {
                Write-Alert "High page file usage: ${SwapPercent}% (threshold: ${SWAP_WARN}%)"
            }
        }
    }
} catch {}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# Disk Usage Check
#-------------------------------------------------------------------------------
Write-Info "--- Disk Usage ---"
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
foreach ($Disk in $Disks) {
    $DiskPct = [math]::Round((($Disk.Size - $Disk.FreeSpace) / $Disk.Size) * 100, 0)
    $DiskAvailGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
    Write-Info "$($Disk.DeviceID) ${DiskPct}% used ($DiskAvailGB GB available)"
    if ($DiskPct -gt $DISK_WARN) {
        Write-Alert "Low disk space on $($Disk.DeviceID): ${DiskPct}% used (threshold: ${DISK_WARN}%)"
    }
}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# GPU Status Check (NVIDIA only)
#-------------------------------------------------------------------------------
Write-Info "--- GPU Status ---"
if ($ENABLE_GPU_MONITORING -eq 1 -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    try {
        $GpuInfo = & nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null
        if ($GpuInfo) {
            $GpuData = $GpuInfo -split ','
            $GpuName = $GpuData[0].Trim()
            $GpuTemp = [int]$GpuData[1].Trim()
            $GpuUtil = $GpuData[2].Trim()
            $GpuMemUsed = $GpuData[3].Trim()
            $GpuMemTotal = $GpuData[4].Trim()
            Write-Info "GPU: $GpuName"
            Write-Info "Temperature: ${GpuTemp}C | Utilization: ${GpuUtil}% | VRAM: ${GpuMemUsed}/${GpuMemTotal} MB"
            if ($GpuTemp -gt $GPU_TEMP_CRIT) {
                Write-Alert "High GPU temperature: ${GpuTemp}C (threshold: ${GPU_TEMP_CRIT}C)"
            }
        }
    } catch {}
} else {
    Write-Info "No NVIDIA GPU detected"
}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# System Uptime Check
#-------------------------------------------------------------------------------
Write-Info "--- System Uptime ---"
$BootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$UptimeSpan = (Get-Date) - $BootTime
$UptimeDays = [math]::Floor($UptimeSpan.TotalDays)
$UptimeHours = $UptimeSpan.Hours

if ($UptimeDays -gt 0) {
    $UptimeText = "$UptimeDays days, $UptimeHours hours"
} else {
    $UptimeText = "$UptimeHours hours, $($UptimeSpan.Minutes) minutes"
}
Write-Info "Uptime: $UptimeText"
if ($UptimeDays -gt $UPTIME_CRIT) {
    Write-Alert "System uptime exceeds $UPTIME_CRIT days ($UptimeDays days). Consider rebooting."
}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# Failed/Stopped Services Check
#-------------------------------------------------------------------------------
Write-Info "--- Service Status ---"
$ServicesToCheck = if ($MONITORED_SERVICES) { $MONITORED_SERVICES } else { @('Spooler', 'W32Time', 'Winmgmt', 'WinRM') }
$FailedCount = 0
foreach ($SvcName in $ServicesToCheck) {
    $Svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    if ($Svc) {
        if ($Svc.Status -ne 'Running') {
            Write-Info "  $SvcName : $($Svc.Status)"
            $FailedCount++
        } else {
            Write-Info "  $SvcName : Running"
        }
    } else {
        Write-Info "  $SvcName : Not Found"
    }
}
if ($FailedCount -gt 0) {
    Write-Alert "$FailedCount service(s) not running"
} else {
    Write-Info "All monitored services running normally"
}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# Top Memory Consumers
#-------------------------------------------------------------------------------
Write-Info "--- Top Memory Consumers ---"
$TopMem = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
foreach ($Proc in $TopMem) {
    $MemMB = [math]::Round($Proc.WorkingSet64 / 1MB, 0)
    $line = "  {0,-30} {1,6} MB" -f $Proc.ProcessName, $MemMB
    $line | Add-Content -Path $Report
    Write-Host $line
}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# Top CPU Consumers
#-------------------------------------------------------------------------------
Write-Info "--- Top CPU Consumers ---"
$TopCpu = Get-Process | Where-Object { $_.CPU -gt 0 } | Sort-Object CPU -Descending | Select-Object -First 5
foreach ($Proc in $TopCpu) {
    $CpuSec = [math]::Round($Proc.CPU, 1)
    $line = "  {0,-30} {1,8}s CPU time" -f $Proc.ProcessName, $CpuSec
    $line | Add-Content -Path $Report
    Write-Host $line
}
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# Network Connections
#-------------------------------------------------------------------------------
Write-Info "--- Active Connections ---"
try {
    $ConnCount = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
} catch {
    $ConnCount = 0
}
Write-Info "Established connections: $ConnCount"
"" | Add-Content -Path $Report

#-------------------------------------------------------------------------------
# Windows Event Log Error Check
#-------------------------------------------------------------------------------
Write-Info "--- Recent Errors (last 24h) ---"
$ErrorThreshold = if ($EVENT_ERROR_THRESHOLD) { $EVENT_ERROR_THRESHOLD } else { 100 }
try {
    $Since = (Get-Date).AddHours(-24)
    $ErrorCount = (Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=$Since} -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Info "System event log errors: $ErrorCount"
    if ($ErrorCount -gt $ErrorThreshold) {
        Write-Alert "High number of system errors in last 24h: $ErrorCount (threshold: $ErrorThreshold)"
    }
} catch {
    Write-Info "Could not query event log"
}
"" | Add-Content -Path $Report

"=============================================" | Add-Content -Path $Report
Write-Host "Report saved to: $Report"

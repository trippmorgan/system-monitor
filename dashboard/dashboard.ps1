#===============================================================================
# dashboard.ps1 - Terminal-Based System Dashboard (Windows)
#===============================================================================
# PURPOSE:
#   Displays a quick system status overview directly in the terminal.
#   Alternative to the web-based Radio Free Albany for quick checks.
#
# USAGE:
#   .\system-monitor\dashboard\dashboard.ps1
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
    $LOG_DIR = "$env:USERPROFILE\system-monitor\logs"
    $ENABLE_GPU_MONITORING = 1
}

$DASHBOARD_DIR = if ($DASHBOARD_DIR) { $DASHBOARD_DIR } else { $ScriptDir }
$ALERT_LOG = if ($ALERT_LOG) { $ALERT_LOG } else { Join-Path $LOG_DIR "alerts.log" }

#===============================================================================
# Dashboard Display
#===============================================================================
Clear-Host

$DateStr = Get-Date -Format 'dddd, MMMM dd, yyyy'
Write-Host ""
Write-Host "+==============================================================================+" -ForegroundColor Cyan
Write-Host "|                    SYSTEM DASHBOARD - $DateStr" -ForegroundColor Cyan
Write-Host "+==============================================================================+" -ForegroundColor Cyan
Write-Host ""

#-------------------------------------------------------------------------------
# System Status
#-------------------------------------------------------------------------------
Write-Host ">> SYSTEM STATUS" -ForegroundColor Blue
Write-Host ("-" * 80)

# CPU
try {
    $CpuLoad = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue, 1)
} catch {
    $CpuLoad = 0
}
$Cores = $env:NUMBER_OF_PROCESSORS
$CpuColor = if ($CpuLoad -gt 90) { "Red" } elseif ($CpuLoad -gt 70) { "Yellow" } else { "Green" }
$CpuStatus = if ($CpuLoad -gt 90) { "HIGH" } elseif ($CpuLoad -gt 70) { "WARN" } else { "OK" }
Write-Host "  CPU:      " -NoNewline
Write-Host "${CpuLoad}% usage" -NoNewline
Write-Host "    Cores: $Cores" -NoNewline
Write-Host "    Status: " -NoNewline
Write-Host $CpuStatus -ForegroundColor $CpuColor

# Memory
$OS = Get-CimInstance Win32_OperatingSystem
$MemTotalMB = [math]::Round($OS.TotalVisibleMemorySize / 1KB, 0)
$MemFreeMB = [math]::Round($OS.FreePhysicalMemory / 1KB, 0)
$MemUsedMB = $MemTotalMB - $MemFreeMB
$MemPct = [math]::Round(($MemUsedMB / $MemTotalMB) * 100, 0)
$MemColor = if ($MemPct -gt 90) { "Red" } elseif ($MemPct -gt 70) { "Yellow" } else { "Green" }
$MemStatus = if ($MemPct -gt 90) { "HIGH" } elseif ($MemPct -gt 70) { "WARN" } else { "OK" }
Write-Host "  Memory:   " -NoNewline
Write-Host "${MemUsedMB}MB / ${MemTotalMB}MB (${MemPct}%)" -NoNewline
Write-Host "    Status: " -NoNewline
Write-Host $MemStatus -ForegroundColor $MemColor

# Disk (all fixed drives)
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
foreach ($Disk in $Disks) {
    $DiskPct = [math]::Round((($Disk.Size - $Disk.FreeSpace) / $Disk.Size) * 100, 0)
    $DiskUsedGB = [math]::Round(($Disk.Size - $Disk.FreeSpace) / 1GB, 1)
    $DiskTotalGB = [math]::Round($Disk.Size / 1GB, 1)
    $DiskColor = if ($DiskPct -gt 90) { "Red" } elseif ($DiskPct -gt 80) { "Yellow" } else { "Green" }
    $DiskStatus = if ($DiskPct -gt 90) { "LOW" } elseif ($DiskPct -gt 80) { "WARN" } else { "OK" }
    Write-Host "  Disk $($Disk.DeviceID)   " -NoNewline
    Write-Host "${DiskUsedGB}GB / ${DiskTotalGB}GB (${DiskPct}%)" -NoNewline
    Write-Host "    Status: " -NoNewline
    Write-Host $DiskStatus -ForegroundColor $DiskColor
}

# GPU
if ($ENABLE_GPU_MONITORING -eq 1 -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    try {
        $GpuInfo = & nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null
        if ($GpuInfo) {
            $GpuData = $GpuInfo -split ','
            $GpuTemp = [int]$GpuData[0].Trim()
            $GpuUtil = $GpuData[1].Trim()
            $GpuMem = $GpuData[2].Trim()
            $GpuMemTot = $GpuData[3].Trim()
            $GpuColor = if ($GpuTemp -gt 80) { "Red" } else { "Green" }
            $GpuStatus = if ($GpuTemp -gt 80) { "HOT" } else { "OK" }
            Write-Host "  GPU:      " -NoNewline
            Write-Host "Temp: ${GpuTemp}C | Util: ${GpuUtil}% | VRAM: ${GpuMem}/${GpuMemTot}MB" -NoNewline
            Write-Host "    Status: " -NoNewline
            Write-Host $GpuStatus -ForegroundColor $GpuColor
        }
    } catch {}
}

# Uptime
$BootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$UptimeSpan = (Get-Date) - $BootTime
$UptimeDays = [math]::Floor($UptimeSpan.TotalDays)
if ($UptimeDays -gt 0) {
    $UptimeText = "$UptimeDays days, $($UptimeSpan.Hours) hours"
} else {
    $UptimeText = "$($UptimeSpan.Hours) hours, $($UptimeSpan.Minutes) minutes"
}
$UptimeColor = if ($UptimeDays -gt 14) { "Yellow" } else { "Green" }
$UptimeStatus = if ($UptimeDays -gt 14) { "REBOOT SOON" } else { "OK" }
Write-Host "  Uptime:   " -NoNewline
Write-Host $UptimeText -NoNewline
Write-Host "    Status: " -NoNewline
Write-Host $UptimeStatus -ForegroundColor $UptimeColor

# Network
try {
    $NetConn = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Measure-Object).Count
} catch {
    $NetConn = 0
}
Write-Host "  Network:  $NetConn active connections"

Write-Host ""

#-------------------------------------------------------------------------------
# Services
#-------------------------------------------------------------------------------
Write-Host ">> KEY SERVICES" -ForegroundColor Blue
Write-Host ("-" * 80)

$ServicesToCheck = if ($MONITORED_SERVICES) { $MONITORED_SERVICES } else { @('Spooler', 'W32Time', 'Winmgmt', 'WinRM') }
foreach ($SvcName in $ServicesToCheck) {
    $Svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    if ($Svc -and $Svc.Status -eq 'Running') {
        Write-Host ("  {0,-25}" -f $SvcName) -NoNewline
        Write-Host "Running" -ForegroundColor Green
    } elseif ($Svc) {
        Write-Host ("  {0,-25}" -f $SvcName) -NoNewline
        Write-Host $Svc.Status -ForegroundColor Red
    } else {
        Write-Host ("  {0,-25}" -f $SvcName) -NoNewline
        Write-Host "Not Found" -ForegroundColor DarkGray
    }
}

Write-Host ""

#-------------------------------------------------------------------------------
# Recent Alerts
#-------------------------------------------------------------------------------
Write-Host ">> RECENT ALERTS" -ForegroundColor Blue
Write-Host ("-" * 80)

if ((Test-Path $ALERT_LOG) -and (Get-Item $ALERT_LOG).Length -gt 0) {
    Get-Content $ALERT_LOG -Tail 5 | ForEach-Object {
        Write-Host "  ! " -ForegroundColor Yellow -NoNewline
        Write-Host $_
    }
} else {
    Write-Host "  OK - No recent alerts" -ForegroundColor Green
}

Write-Host ""

#-------------------------------------------------------------------------------
# Top Processes
#-------------------------------------------------------------------------------
Write-Host ">> TOP PROCESSES (by Memory)" -ForegroundColor Blue
Write-Host ("-" * 80)

Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object {
    $MemMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
    $CpuSec = if ($_.CPU) { [math]::Round($_.CPU, 1) } else { 0 }
    Write-Host ("  {0,-30} {1,6} MB  {2,8}s CPU" -f $_.ProcessName, $MemMB, $CpuSec)
}

Write-Host ""

#-------------------------------------------------------------------------------
# News Headlines (from cached news.json)
#-------------------------------------------------------------------------------
Write-Host ">> NEWS HEADLINES" -ForegroundColor Magenta
Write-Host ("-" * 80)

$NewsJson = Join-Path $DASHBOARD_DIR "news-cache\news.json"
$PythonCmd = if ($PYTHON_EXE) { $PYTHON_EXE } else { $null }

if ((Test-Path $NewsJson) -and $PythonCmd) {
    $PyScript = @"
import json
try:
    with open(r'$($NewsJson -replace "'", "\'")') as f:
        news = json.load(f)
    for item in news[:8]:
        title = item.get('title', '')[:70]
        source = item.get('source', '')
        print(f'  * {title}')
        print(f'    {source}')
except Exception as e:
    print(f'  Error reading news: {e}')
"@
    & $PythonCmd -c $PyScript
} else {
    Write-Host "  No cached news. Run news-fetcher.ps1 first."
}

Write-Host ""
Write-Host ("-" * 80) -ForegroundColor Cyan
Write-Host "  Quick Actions:" -ForegroundColor White
Write-Host "    Run health check:  .\scripts\health-check.ps1"
Write-Host "    Run cleanup:       .\scripts\cleanup.ps1"
$ReportDate = Get-Date -Format 'yyyy-MM-dd'
Write-Host "    View full report:  Get-Content .\logs\daily-report-$ReportDate.log"
Write-Host ("-" * 80) -ForegroundColor Cyan
Write-Host ""

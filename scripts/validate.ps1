#===============================================================================
# validate.ps1 - System Monitor Validation Script (Windows)
#===============================================================================
# PURPOSE:
#   Validates the system-monitor installation by checking:
#   - Required dependencies are available
#   - Configuration is valid
#   - Directories exist and are writable
#   - Basic functionality works
#
# USAGE:
#   .\system-monitor\scripts\validate.ps1
#===============================================================================

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MonitorHome = Split-Path -Parent $ScriptDir

# Load config early so $PYTHON_EXE is available for dependency checks
$ConfigFile = Join-Path $MonitorHome "config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

# Counters
$Pass = 0
$Fail = 0
$Warn = 0

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------
function Test-CheckPass {
    param([string]$Message)
    Write-Host "  " -NoNewline
    Write-Host "OK" -ForegroundColor Green -NoNewline
    Write-Host " $Message"
    $script:Pass++
}

function Test-CheckFail {
    param([string]$Message)
    Write-Host "  " -NoNewline
    Write-Host "FAIL" -ForegroundColor Red -NoNewline
    Write-Host " $Message"
    $script:Fail++
}

function Test-CheckWarn {
    param([string]$Message)
    Write-Host "  " -NoNewline
    Write-Host "WARN" -ForegroundColor Yellow -NoNewline
    Write-Host " $Message"
    $script:Warn++
}

function Test-CheckInfo {
    param([string]$Message)
    Write-Host "  " -NoNewline
    Write-Host "INFO" -ForegroundColor Cyan -NoNewline
    Write-Host " $Message"
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ">> $Title" -ForegroundColor Cyan
    Write-Host ("-" * 50)
}

#===============================================================================
# Validation Checks
#===============================================================================
Write-Host ""
Write-Host "+==================================================+" -ForegroundColor Cyan
Write-Host "|     System Monitor - Validation Check (Windows)   |" -ForegroundColor Cyan
Write-Host "+==================================================+" -ForegroundColor Cyan

#-------------------------------------------------------------------------------
# Section 1: Required Dependencies
#-------------------------------------------------------------------------------
Write-Section "Required Dependencies"

# PowerShell
Test-CheckPass "PowerShell $($PSVersionTable.PSVersion)"

# Python (uses auto-detected path from config.ps1)
if ($PYTHON_EXE -and (Test-Path $PYTHON_EXE)) {
    $PyVer = & $PYTHON_EXE --version 2>&1
    Test-CheckPass "$PyVer at $PYTHON_EXE"
} else {
    Test-CheckFail "Python not found (required for dashboard server and news fetching)"
}

# curl (usually built into Windows 10+)
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    Test-CheckPass "curl.exe (HTTP requests)"
} elseif (Get-Command curl -ErrorAction SilentlyContinue) {
    Test-CheckPass "curl (HTTP requests - PowerShell alias)"
} else {
    Test-CheckWarn "curl not found (news fetching uses Python instead)"
}

# Get-Service (Windows service monitoring)
if (Get-Command Get-Service -ErrorAction SilentlyContinue) {
    Test-CheckPass "Get-Service (Windows service monitoring)"
} else {
    Test-CheckFail "Get-Service not available"
}

# Get-Counter (performance monitoring)
if (Get-Command Get-Counter -ErrorAction SilentlyContinue) {
    Test-CheckPass "Get-Counter (CPU performance monitoring)"
} else {
    Test-CheckWarn "Get-Counter not available (CPU monitoring limited)"
}

# Get-CimInstance (WMI queries)
if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
    Test-CheckPass "Get-CimInstance (system metrics via WMI)"
} else {
    Test-CheckFail "Get-CimInstance not available (required for system stats)"
}

#-------------------------------------------------------------------------------
# Section 2: Optional Dependencies
#-------------------------------------------------------------------------------
Write-Section "Optional Dependencies"

# nvidia-smi
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    try {
        $Gpu = & nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1
        if ($Gpu) {
            Test-CheckPass "nvidia-smi (GPU: $Gpu)"
        } else {
            Test-CheckWarn "nvidia-smi found but no GPU detected"
        }
    } catch {
        Test-CheckWarn "nvidia-smi found but query failed"
    }
} else {
    Test-CheckInfo "nvidia-smi not found (GPU monitoring disabled)"
}

# Get-NetTCPConnection
if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
    Test-CheckPass "Get-NetTCPConnection (network monitoring)"
} else {
    Test-CheckWarn "Get-NetTCPConnection not available (network stats limited)"
}

#-------------------------------------------------------------------------------
# Section 3: Configuration
#-------------------------------------------------------------------------------
Write-Section "Configuration"

$ConfigFile = Join-Path $MonitorHome "config.ps1"
if (Test-Path $ConfigFile) {
    Test-CheckPass "config.ps1 exists"
    try {
        . $ConfigFile
        Test-CheckPass "config.ps1 loads without errors"
        if ($LOG_DIR) { Test-CheckPass "LOG_DIR defined: $LOG_DIR" } else { Test-CheckFail "LOG_DIR not defined" }
        if ($DASHBOARD_DIR) { Test-CheckPass "DASHBOARD_DIR defined" } else { Test-CheckFail "DASHBOARD_DIR not defined" }
        if ($CPU_WARN) { Test-CheckPass "Thresholds defined (CPU_WARN=$CPU_WARN)" } else { Test-CheckFail "Thresholds not defined" }
    } catch {
        Test-CheckFail "config.ps1 has errors: $_"
    }
} else {
    Test-CheckFail "config.ps1 not found at $ConfigFile"
}

# User override config
$UserConfig = "$env:USERPROFILE\.config\system-monitor\config.ps1"
if (Test-Path $UserConfig) {
    Test-CheckInfo "User override config found: $UserConfig"
}

#-------------------------------------------------------------------------------
# Section 4: Directory Structure
#-------------------------------------------------------------------------------
Write-Section "Directory Structure"

foreach ($dir in @('scripts', 'dashboard', 'logs')) {
    $dirPath = Join-Path $MonitorHome $dir
    if (Test-Path $dirPath) {
        Test-CheckPass "$dir\"
    } else {
        Test-CheckFail "$dir\ directory missing"
    }
}

# Logs writable
$LogDir = if ($LOG_DIR) { $LOG_DIR } else { Join-Path $MonitorHome "logs" }
if (Test-Path $LogDir) {
    try {
        $TestFile = Join-Path $LogDir ".write-test"
        "test" | Set-Content $TestFile -ErrorAction Stop
        Remove-Item $TestFile -Force
        Test-CheckPass "logs\ is writable"
    } catch {
        Test-CheckFail "logs\ is not writable"
    }
} else {
    Test-CheckWarn "logs\ does not exist yet (will be created on first run)"
}

# News cache
$NewsCacheDir = Join-Path $MonitorHome "dashboard\news-cache"
if (Test-Path $NewsCacheDir) {
    Test-CheckPass "dashboard\news-cache\"
} else {
    Test-CheckWarn "dashboard\news-cache\ missing (will be created on first run)"
}

#-------------------------------------------------------------------------------
# Section 5: PowerShell Scripts
#-------------------------------------------------------------------------------
Write-Section "PowerShell Scripts"

$Scripts = @(
    "scripts\health-check.ps1",
    "scripts\cleanup.ps1",
    "scripts\system-monitor-assistant.ps1",
    "scripts\validate.ps1",
    "dashboard\launch.ps1",
    "dashboard\stop.ps1",
    "dashboard\dashboard.ps1",
    "dashboard\system-stats.ps1",
    "dashboard\news-fetcher.ps1",
    "dashboard\watchdog.ps1"
)

foreach ($script in $Scripts) {
    $path = Join-Path $MonitorHome $script
    if (Test-Path $path) {
        Test-CheckPass $script
    } else {
        Test-CheckFail "$script not found"
    }
}

#-------------------------------------------------------------------------------
# Section 6: Dashboard Files
#-------------------------------------------------------------------------------
Write-Section "Dashboard Files"

$IndexHtml = Join-Path $MonitorHome "dashboard\index.html"
if (Test-Path $IndexHtml) {
    Test-CheckPass "index.html"
} else {
    Test-CheckFail "index.html not found"
}

#-------------------------------------------------------------------------------
# Section 7: Functionality Tests
#-------------------------------------------------------------------------------
Write-Section "Functionality Tests"

# CPU reading
try {
    $CpuTest = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue, 1)
    Test-CheckPass "CPU usage readable: ${CpuTest}%"
} catch {
    Test-CheckFail "Cannot read CPU usage"
}

# Memory reading
try {
    $MemOS = Get-CimInstance Win32_OperatingSystem
    $MemPctTest = [math]::Round((($MemOS.TotalVisibleMemorySize - $MemOS.FreePhysicalMemory) / $MemOS.TotalVisibleMemorySize) * 100, 0)
    Test-CheckPass "Memory stats readable: ${MemPctTest}% used"
} catch {
    Test-CheckFail "Cannot read memory stats"
}

# Disk reading
try {
    $DiskTest = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $DiskPctTest = [math]::Round((($DiskTest.Size - $DiskTest.FreeSpace) / $DiskTest.Size) * 100, 0)
    Test-CheckPass "Disk stats readable: C: ${DiskPctTest}% used"
} catch {
    Test-CheckFail "Cannot read disk stats"
}

# Network reading
try {
    $NetTest = (Get-NetTCPConnection -State Established -ErrorAction Stop | Measure-Object).Count
    Test-CheckPass "Network stats readable: $NetTest connections"
} catch {
    Test-CheckWarn "Cannot read network stats"
}

#-------------------------------------------------------------------------------
# Section 8: Port Availability
#-------------------------------------------------------------------------------
Write-Section "Network"

$Port = if ($DASHBOARD_PORT) { $DASHBOARD_PORT } else { 8787 }
$PortInUse = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Listen' }
if ($PortInUse) {
    Test-CheckWarn "Port $Port is already in use (dashboard may be running)"
} else {
    Test-CheckPass "Port $Port is available"
}

#===============================================================================
# Summary
#===============================================================================
Write-Host ""
Write-Host ("-" * 50)
Write-Host "Summary" -ForegroundColor White
Write-Host ("-" * 50)
Write-Host "  Passed:   $Pass" -ForegroundColor Green
Write-Host "  Failed:   $Fail" -ForegroundColor Red
Write-Host "  Warnings: $Warn" -ForegroundColor Yellow
Write-Host ""

if ($Fail -eq 0) {
    Write-Host "OK - All required checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Quick start:"
    Write-Host "  Terminal dashboard:  .\dashboard\dashboard.ps1"
    Write-Host "  Radio Free Albany:   .\dashboard\launch.ps1"
    Write-Host "  Health check:        .\scripts\health-check.ps1"
    Write-Host ""
    exit 0
} else {
    Write-Host "FAIL - Some checks failed. Please review the output above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:"
    Write-Host "  Install Python:  winget install Python.Python.3"
    Write-Host "  Execution policy: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    Write-Host ""
    exit 1
}

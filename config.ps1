#===============================================================================
# config.ps1 - Centralized Configuration for System Monitor (Windows)
#===============================================================================
# This file contains all configurable settings for the system monitor suite.
# Import this file from other scripts: . "$PSScriptRoot\..\config.ps1"
#===============================================================================

#-------------------------------------------------------------------------------
# Paths
#-------------------------------------------------------------------------------
$script:MONITOR_HOME = if ($env:MONITOR_HOME) { $env:MONITOR_HOME } else { "$env:USERPROFILE\system-monitor" }
$script:LOG_DIR = "$MONITOR_HOME\logs"
$script:DASHBOARD_DIR = "$MONITOR_HOME\dashboard"
$script:NEWS_CACHE_DIR = "$DASHBOARD_DIR\news-cache"
$script:ALERT_LOG = "$LOG_DIR\alerts.log"

#-------------------------------------------------------------------------------
# Alert Thresholds
#-------------------------------------------------------------------------------
# CPU load thresholds (percentage)
$script:CPU_WARN = if ($env:CPU_WARN) { $env:CPU_WARN } else { 70 }     # Warning at 70% CPU
$script:CPU_CRIT = if ($env:CPU_CRIT) { $env:CPU_CRIT } else { 90 }     # Critical at 90% CPU

# Memory usage thresholds (percentage)
$script:MEM_WARN = if ($env:MEM_WARN) { $env:MEM_WARN } else { 70 }     # Warning at 70% usage
$script:MEM_CRIT = if ($env:MEM_CRIT) { $env:MEM_CRIT } else { 90 }     # Critical at 90% usage

# Page file (swap) usage threshold (percentage)
$script:SWAP_WARN = if ($env:SWAP_WARN) { $env:SWAP_WARN } else { 50 }  # Warning at 50% page file usage

# Disk usage thresholds (percentage)
$script:DISK_WARN = if ($env:DISK_WARN) { $env:DISK_WARN } else { 80 }  # Warning at 80% full
$script:DISK_CRIT = if ($env:DISK_CRIT) { $env:DISK_CRIT } else { 90 }  # Critical at 90% full

# GPU temperature thresholds (Celsius)
$script:GPU_TEMP_WARN = if ($env:GPU_TEMP_WARN) { $env:GPU_TEMP_WARN } else { 70 }  # Warning at 70C
$script:GPU_TEMP_CRIT = if ($env:GPU_TEMP_CRIT) { $env:GPU_TEMP_CRIT } else { 85 }  # Critical at 85C

# Uptime thresholds (days)
$script:UPTIME_WARN = if ($env:UPTIME_WARN) { $env:UPTIME_WARN } else { 14 }  # Warning after 14 days
$script:UPTIME_CRIT = if ($env:UPTIME_CRIT) { $env:UPTIME_CRIT } else { 30 }  # Critical after 30 days

# Event log error threshold (count per 24h)
$script:EVENT_ERROR_THRESHOLD = if ($env:EVENT_ERROR_THRESHOLD) { $env:EVENT_ERROR_THRESHOLD } else { 100 }

#-------------------------------------------------------------------------------
# Timing
#-------------------------------------------------------------------------------
$script:CHECK_INTERVAL = if ($env:CHECK_INTERVAL) { $env:CHECK_INTERVAL } else { 30 }        # Seconds between monitor checks
$script:NEWS_REFRESH_INTERVAL = if ($env:NEWS_REFRESH_INTERVAL) { $env:NEWS_REFRESH_INTERVAL } else { 2 }  # Minutes between news refreshes
$script:DASHBOARD_PORT = if ($env:DASHBOARD_PORT) { $env:DASHBOARD_PORT } else { 8787 }      # HTTP server port
$script:NEWS_CACHE_TTL = if ($env:NEWS_CACHE_TTL) { $env:NEWS_CACHE_TTL } else { 3600 }      # News cache TTL in seconds (1 hour)
$script:LOG_RETENTION_DAYS = if ($env:LOG_RETENTION_DAYS) { $env:LOG_RETENTION_DAYS } else { 30 }  # Days to keep old logs

#-------------------------------------------------------------------------------
# Services to Monitor (Windows Services)
#-------------------------------------------------------------------------------
# Comma-separated list of Windows services to check
$script:MONITORED_SERVICES = if ($env:MONITORED_SERVICES) {
    $env:MONITORED_SERVICES -split ','
} else {
    @('Spooler', 'W32Time', 'Winmgmt', 'WinRM', 'MSSQLSERVER', 'Docker')
}

#-------------------------------------------------------------------------------
# News Categories (for news-fetcher.ps1)
#-------------------------------------------------------------------------------
# Enable/disable categories (1=enabled, 0=disabled)
$script:NEWS_TECH_ENABLED = if ($env:NEWS_TECH_ENABLED) { $env:NEWS_TECH_ENABLED } else { 1 }
$script:NEWS_LOCAL_ENABLED = if ($env:NEWS_LOCAL_ENABLED) { $env:NEWS_LOCAL_ENABLED } else { 1 }
$script:NEWS_STATE_ENABLED = if ($env:NEWS_STATE_ENABLED) { $env:NEWS_STATE_ENABLED } else { 1 }
$script:NEWS_SPORTS_ENABLED = if ($env:NEWS_SPORTS_ENABLED) { $env:NEWS_SPORTS_ENABLED } else { 1 }
$script:NEWS_POLITICS_ENABLED = if ($env:NEWS_POLITICS_ENABLED) { $env:NEWS_POLITICS_ENABLED } else { 1 }
$script:NEWS_NATURE_ENABLED = if ($env:NEWS_NATURE_ENABLED) { $env:NEWS_NATURE_ENABLED } else { 1 }
$script:NEWS_FISHING_ENABLED = if ($env:NEWS_FISHING_ENABLED) { $env:NEWS_FISHING_ENABLED } else { 1 }
$script:NEWS_CONSERVATION_ENABLED = if ($env:NEWS_CONSERVATION_ENABLED) { $env:NEWS_CONSERVATION_ENABLED } else { 1 }

# Local news search term (customize for your area)
$script:LOCAL_NEWS_SEARCH = if ($env:LOCAL_NEWS_SEARCH) { $env:LOCAL_NEWS_SEARCH } else { "Albany+Georgia" }

#-------------------------------------------------------------------------------
# Feature Flags
#-------------------------------------------------------------------------------
$script:ENABLE_GPU_MONITORING = if ($env:ENABLE_GPU_MONITORING) { $env:ENABLE_GPU_MONITORING } else { 1 }  # Requires nvidia-smi
$script:ENABLE_NEWS_FETCHING = if ($env:ENABLE_NEWS_FETCHING) { $env:ENABLE_NEWS_FETCHING } else { 1 }
$script:ENABLE_BROWSER_OPEN = if ($env:ENABLE_BROWSER_OPEN) { $env:ENABLE_BROWSER_OPEN } else { 1 }       # Auto-open dashboard

#-------------------------------------------------------------------------------
# PlayoutONE Connection Settings (for DJ server)
#-------------------------------------------------------------------------------
$script:P1_SQL_SERVER   = if ($env:P1_SQL_SERVER)   { $env:P1_SQL_SERVER }   else { ".\P1SQLEXPRESS" }
$script:P1_SQL_DATABASE = if ($env:P1_SQL_DATABASE) { $env:P1_SQL_DATABASE } else { "playoutone_standard" }
$script:P1_SQL_USER     = if ($env:P1_SQL_USER)     { $env:P1_SQL_USER }     else { "playoutone_apps" }
$script:P1_SQL_PASSWORD = if ($env:P1_SQL_PASSWORD) { $env:P1_SQL_PASSWORD } else { "PlayoutONE." }
$script:P1_API_HOST     = if ($env:P1_API_HOST)     { $env:P1_API_HOST }     else { "127.0.0.1" }
$script:P1_API_PORT     = if ($env:P1_API_PORT)     { $env:P1_API_PORT }     else { 1073 }

# Export PlayoutONE settings as env vars for dj-server.py
$env:P1_SQL_SERVER   = $P1_SQL_SERVER
$env:P1_SQL_DATABASE = $P1_SQL_DATABASE
$env:P1_SQL_USER     = $P1_SQL_USER
$env:P1_SQL_PASSWORD = $P1_SQL_PASSWORD
$env:P1_API_HOST     = $P1_API_HOST
$env:P1_API_PORT     = $P1_API_PORT

#-------------------------------------------------------------------------------
# DJ Personality LLM (Ollama on jarvis superserver; canned lines if unreachable)
#-------------------------------------------------------------------------------
$script:DJ_LLM_URL     = if ($env:DJ_LLM_URL)     { $env:DJ_LLM_URL }     else { "http://100.80.111.84:11434" }
$script:DJ_LLM_MODEL   = if ($env:DJ_LLM_MODEL)   { $env:DJ_LLM_MODEL }   else { "phi3:mini" }
$script:DJ_LLM_ENABLED = if ($env:DJ_LLM_ENABLED) { $env:DJ_LLM_ENABLED } else { "1" }

$env:DJ_LLM_URL     = $DJ_LLM_URL
$env:DJ_LLM_MODEL   = $DJ_LLM_MODEL
$env:DJ_LLM_ENABLED = $DJ_LLM_ENABLED

#-------------------------------------------------------------------------------
# Load user overrides
#-------------------------------------------------------------------------------
# Users can create a user-config.ps1 in the same directory to override defaults
$UserConfig = "$env:USERPROFILE\.config\system-monitor\config.ps1"
if (Test-Path $UserConfig) {
    . $UserConfig
}

#-------------------------------------------------------------------------------
# Python Path (auto-detect real Python, bypassing Windows Store stub)
#-------------------------------------------------------------------------------
$script:PYTHON_EXE = $null
# Build list of candidate python.exe paths (most common Windows install locations)
$LocalAppData = [Environment]::GetFolderPath('LocalApplicationData')
$PythonCandidates = @()
# User-install: AppData\Local\Programs\Python\Python3XX\python.exe
$PyUserDir = Join-Path $LocalAppData "Programs\Python"
if (Test-Path $PyUserDir) {
    $PythonCandidates += Get-ChildItem -Path $PyUserDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Python3\d+$' } |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "python.exe" }
}
# System-wide installs
foreach ($ver in @('312','311','310','39','313','314')) {
    $PythonCandidates += "C:\Python$ver\python.exe"
    $PythonCandidates += "C:\Program Files\Python$ver\python.exe"
}
# Test each candidate
foreach ($candidate in $PythonCandidates) {
    if (Test-Path $candidate) {
        $script:PYTHON_EXE = $candidate
        break
    }
}
# Fallback: test if 'python' on PATH is real (not the Windows Store stub)
if (-not $PYTHON_EXE) {
    try {
        $testOut = & python -c "import sys; print(sys.executable)" 2>$null
        if ($testOut -and (Test-Path $testOut)) {
            $script:PYTHON_EXE = $testOut.Trim()
        }
    } catch {}
}

#-------------------------------------------------------------------------------
# Ensure directories exist
#-------------------------------------------------------------------------------
@($LOG_DIR, $NEWS_CACHE_DIR) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

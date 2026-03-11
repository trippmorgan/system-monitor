#===============================================================================
# cleanup.ps1 - System Cleanup and Maintenance Script (Windows)
#===============================================================================
# PURPOSE:
#   Frees disk space by removing old logs, browser caches, temp files,
#   and other accumulated data. Safe to run manually or via Task Scheduler.
#
# USAGE:
#   .\system-monitor\scripts\cleanup.ps1
#
# SCHEDULING:
#   Use Task Scheduler to run weekly on Sunday at 3:00 AM
#
# WHAT IT CLEANS:
#   - Old monitoring logs (30+ days)
#   - Browser caches (Chrome, Edge, Firefox)
#   - Windows temp files older than 7 days
#   - Thumbnail cache
#   - Windows Update cleanup (if elevated)
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
    $LOG_RETENTION_DAYS = 30
}

$Date = Get-Date -Format 'yyyy-MM-dd'
$CleanupLog = Join-Path $LOG_DIR "cleanup-$Date.log"
$RetentionDays = if ($LOG_RETENTION_DAYS) { $LOG_RETENTION_DAYS } else { 30 }

if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] $Message"
    $line | Add-Content -Path $CleanupLog
    Write-Host $line
}

#-------------------------------------------------------------------------------
# Cleanup Operations
#-------------------------------------------------------------------------------
Write-Log "Starting system cleanup..."

# Remove old monitoring logs
Write-Log "Cleaning old monitoring logs (older than $RetentionDays days)..."
$CutoffDate = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem -Path $LOG_DIR -Filter "daily-report-*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $CutoffDate } |
    ForEach-Object { Remove-Item $_.FullName -Force; Write-Log "  Removed: $($_.Name)" }
Get-ChildItem -Path $LOG_DIR -Filter "cleanup-*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $CutoffDate } |
    ForEach-Object { Remove-Item $_.FullName -Force; Write-Log "  Removed: $($_.Name)" }

# Chrome cache
Write-Log "Cleaning browser caches..."
$ChromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
if (Test-Path $ChromeCache) {
    Remove-Item "$ChromeCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  Chrome cache cleared"
}

# Edge cache
$EdgeCache = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
if (Test-Path $EdgeCache) {
    Remove-Item "$EdgeCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  Edge cache cleared"
}

# Firefox cache
$FirefoxProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $FirefoxProfiles) {
    Get-ChildItem -Path $FirefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $ffCache = Join-Path $_.FullName "cache2"
        if (Test-Path $ffCache) {
            Remove-Item "$ffCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log "  Firefox cache cleared"
}

# Thumbnail cache
Write-Log "Cleaning thumbnail cache..."
$ThumbCache = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path $ThumbCache) {
    Get-ChildItem -Path $ThumbCache -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    Write-Log "  Thumbnail cache cleared"
}

# User temp files older than 7 days
Write-Log "Cleaning old temp files..."
$TempDirs = @($env:TEMP, "$env:LOCALAPPDATA\Temp")
foreach ($TempDir in $TempDirs) {
    if (Test-Path $TempDir) {
        $TempCutoff = (Get-Date).AddDays(-7)
        $Removed = 0
        Get-ChildItem -Path $TempDir -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $TempCutoff } |
            ForEach-Object {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                $Removed++
            }
        Write-Log "  Removed $Removed old temp files from $TempDir"
    }
}

# Windows Update cleanup (requires elevation)
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) {
    Write-Log "Cleaning Windows Update cache..."
    try {
        # Clear SoftwareDistribution download cache
        $WUCache = "$env:SystemRoot\SoftwareDistribution\Download"
        if (Test-Path $WUCache) {
            Remove-Item "$WUCache\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  Windows Update download cache cleared"
        }
    } catch {
        Write-Log "  Could not clean Windows Update cache"
    }
} else {
    Write-Log "Skipping Windows Update cleanup (not running as Administrator)"
}

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
$Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$FreeGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
Write-Log "Cleanup complete. Available disk space on C: $FreeGB GB"
Write-Log "Cleanup finished."

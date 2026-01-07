#!/bin/bash
#===============================================================================
# cleanup.sh - System Cleanup and Maintenance Script
#===============================================================================
# PURPOSE:
#   Frees disk space by removing old logs, browser caches, temp files,
#   and other accumulated cruft. Safe to run manually or via cron.
#
# USAGE:
#   ~/system-monitor/scripts/cleanup.sh
#
# CRON:
#   Runs weekly on Sunday at 3:00 AM via crontab
#   0 3 * * 0 /home/tripp/system-monitor/scripts/cleanup.sh
#
# WHAT IT CLEANS:
#   - Old monitoring logs (30+ days)
#   - Browser caches (Chrome, Chromium, Firefox)
#   - Thumbnail cache
#   - APT package cache (requires sudo)
#   - Journal logs (limits to 500MB, requires sudo)
#   - Old snap revisions (lists only, manual removal)
#   - Temp files older than 7 days
#
# OUTPUT:
#   Log file: ~/system-monitor/logs/cleanup-YYYY-MM-DD.log
#===============================================================================

#-------------------------------------------------------------------------------
# Load Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Warning: config.sh not found, using defaults" >&2
    LOG_DIR="$HOME/system-monitor/logs"
    LOG_RETENTION_DAYS=30
fi

DATE=$(date +%Y-%m-%d)
CLEANUP_LOG="$LOG_DIR/cleanup-$DATE.log"

# log() - Log message to file and stdout
log() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$CLEANUP_LOG"
}

#-------------------------------------------------------------------------------
# Cleanup Operations
#-------------------------------------------------------------------------------
log "Starting system cleanup..."

# Remove old monitoring logs (keep last $LOG_RETENTION_DAYS days)
log "Cleaning old monitoring logs (older than $LOG_RETENTION_DAYS days)..."
find "$LOG_DIR" -name "daily-report-*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
find "$LOG_DIR" -name "cleanup-*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

# Remove browser cache directories (can reclaim significant space)
log "Cleaning browser caches..."
rm -rf ~/.cache/google-chrome/Default/Cache/* 2>/dev/null
rm -rf ~/.cache/chromium/Default/Cache/* 2>/dev/null
rm -rf ~/.cache/mozilla/firefox/*/cache2/* 2>/dev/null

# Remove thumbnail cache (regenerates automatically when needed)
log "Cleaning thumbnail cache..."
rm -rf ~/.cache/thumbnails/* 2>/dev/null

# System-level cleanup (requires sudo - skips gracefully if unavailable)
if sudo -n true 2>/dev/null; then
    log "Cleaning apt cache..."
    sudo apt-get clean 2>/dev/null

    log "Cleaning old journal logs..."
    sudo journalctl --vacuum-size=500M 2>/dev/null
fi

# Report old snap revisions (manual removal recommended)
log "Checking for old snap revisions..."
SNAP_OLD=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}')
if [ -n "$SNAP_OLD" ]; then
    log "Old snap revisions found (run manually with sudo to remove):"
    echo "$SNAP_OLD" >> "$CLEANUP_LOG"
fi

# Remove user's temp files older than 7 days
log "Cleaning old temp files..."
find /tmp -user $USER -mtime +7 -delete 2>/dev/null

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
BEFORE_SPACE=$(df -h / | awk 'NR==2 {print $4}')
log "Cleanup complete. Available disk space: $BEFORE_SPACE"

log "Cleanup finished."

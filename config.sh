#!/bin/bash
#===============================================================================
# config.sh - Centralized Configuration for System Monitor
#===============================================================================
# This file contains all configurable settings for the system monitor suite.
# Source this file from other scripts: source "$(dirname "$0")/../config.sh"
#===============================================================================

#-------------------------------------------------------------------------------
# Paths
#-------------------------------------------------------------------------------
export MONITOR_HOME="${MONITOR_HOME:-$HOME/system-monitor}"
export LOG_DIR="$MONITOR_HOME/logs"
export DASHBOARD_DIR="$MONITOR_HOME/dashboard"
export NEWS_CACHE_DIR="$DASHBOARD_DIR/news-cache"
export ALERT_LOG="$LOG_DIR/alerts.log"

#-------------------------------------------------------------------------------
# Alert Thresholds
#-------------------------------------------------------------------------------
# CPU load thresholds (based on load average)
export CPU_WARN="${CPU_WARN:-6}"           # Warning when load exceeds this
export CPU_CRIT="${CPU_CRIT:-8}"           # Critical when load exceeds this

# Memory usage thresholds (percentage)
export MEM_WARN="${MEM_WARN:-70}"          # Warning at 70% usage
export MEM_CRIT="${MEM_CRIT:-90}"          # Critical at 90% usage

# Swap usage threshold (percentage)
export SWAP_WARN="${SWAP_WARN:-50}"        # Warning at 50% swap usage

# Disk usage thresholds (percentage)
export DISK_WARN="${DISK_WARN:-80}"        # Warning at 80% full
export DISK_CRIT="${DISK_CRIT:-90}"        # Critical at 90% full

# GPU temperature thresholds (Celsius)
export GPU_TEMP_WARN="${GPU_TEMP_WARN:-70}"    # Warning at 70C
export GPU_TEMP_CRIT="${GPU_TEMP_CRIT:-85}"    # Critical at 85C

# Uptime thresholds (days)
export UPTIME_WARN="${UPTIME_WARN:-14}"    # Warning after 14 days
export UPTIME_CRIT="${UPTIME_CRIT:-30}"    # Critical after 30 days

# Journal error threshold (count per 24h)
export JOURNAL_ERROR_THRESHOLD="${JOURNAL_ERROR_THRESHOLD:-100}"

#-------------------------------------------------------------------------------
# Timing
#-------------------------------------------------------------------------------
export CHECK_INTERVAL="${CHECK_INTERVAL:-30}"       # Seconds between monitor checks
export NEWS_REFRESH_INTERVAL="${NEWS_REFRESH_INTERVAL:-5}"  # Minutes between news refreshes
export DASHBOARD_PORT="${DASHBOARD_PORT:-8787}"     # HTTP server port
export NEWS_CACHE_TTL="${NEWS_CACHE_TTL:-3600}"     # News cache TTL in seconds (1 hour)
export LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"  # Days to keep old logs

#-------------------------------------------------------------------------------
# Services to Monitor
#-------------------------------------------------------------------------------
# Space-separated list of systemd services to check
export MONITORED_SERVICES="${MONITORED_SERVICES:-docker postgresql@14-main ollama ssh}"

#-------------------------------------------------------------------------------
# News Categories (for news-fetcher.sh)
#-------------------------------------------------------------------------------
# Enable/disable categories (1=enabled, 0=disabled)
export NEWS_TECH_ENABLED="${NEWS_TECH_ENABLED:-1}"
export NEWS_LOCAL_ENABLED="${NEWS_LOCAL_ENABLED:-1}"
export NEWS_STATE_ENABLED="${NEWS_STATE_ENABLED:-1}"
export NEWS_SPORTS_ENABLED="${NEWS_SPORTS_ENABLED:-1}"
export NEWS_POLITICS_ENABLED="${NEWS_POLITICS_ENABLED:-1}"
export NEWS_NATURE_ENABLED="${NEWS_NATURE_ENABLED:-1}"
export NEWS_FISHING_ENABLED="${NEWS_FISHING_ENABLED:-1}"
export NEWS_CONSERVATION_ENABLED="${NEWS_CONSERVATION_ENABLED:-1}"

# Local news search term (customize for your area)
export LOCAL_NEWS_SEARCH="${LOCAL_NEWS_SEARCH:-Albany+Georgia}"

#-------------------------------------------------------------------------------
# Feature Flags
#-------------------------------------------------------------------------------
export ENABLE_GPU_MONITORING="${ENABLE_GPU_MONITORING:-1}"    # Requires nvidia-smi
export ENABLE_NEWS_FETCHING="${ENABLE_NEWS_FETCHING:-1}"
export ENABLE_BROWSER_OPEN="${ENABLE_BROWSER_OPEN:-1}"        # Auto-open dashboard

#-------------------------------------------------------------------------------
# Helper Function: Load user overrides
#-------------------------------------------------------------------------------
# Users can create ~/.config/system-monitor/config to override defaults
USER_CONFIG="$HOME/.config/system-monitor/config"
if [ -f "$USER_CONFIG" ]; then
    source "$USER_CONFIG"
fi

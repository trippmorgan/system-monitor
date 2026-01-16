#!/bin/bash
#===============================================================================
# system-stats.sh - System Statistics JSON Generator
#===============================================================================
# PURPOSE:
#   Collects current system metrics and outputs them as JSON for the
#   Radio Free Albany web dashboard. Called by the background refresh loop.
#
# USAGE:
#   ~/system-monitor/dashboard/system-stats.sh
#
# OUTPUT:
#   ~/system-monitor/dashboard/news-cache/stats.json
#
# METRICS COLLECTED:
#   - CPU load average and core count
#   - Memory usage (used, total, percent)
#   - Disk usage (percent, available)
#   - GPU stats (temp, utilization, VRAM) - NVIDIA only
#   - System uptime (text and days)
#   - Network connections (established TCP/UDP)
#   - Service status (docker, postgresql, ollama, ssh)
#   - Recent alerts count and messages
#===============================================================================

#-------------------------------------------------------------------------------
# Load Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    MONITOR_HOME="$HOME/system-monitor"
    NEWS_CACHE_DIR="$HOME/system-monitor/dashboard/news-cache"
    LOG_DIR="$HOME/system-monitor/logs"
    ENABLE_GPU_MONITORING=1
fi

STATS_FILE="${NEWS_CACHE_DIR:-$MONITOR_HOME/dashboard/news-cache}/stats.json"
ALERT_LOG="${ALERT_LOG:-$LOG_DIR/alerts.log}"

#-------------------------------------------------------------------------------
# Collect System Metrics
#-------------------------------------------------------------------------------

# CPU load (1-minute average) and core count
LOAD=$(cat /proc/loadavg | awk '{print $1}')
CORES=$(nproc)

# Memory usage in MB
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))

# Disk usage for root partition
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')

# GPU stats via nvidia-smi (gracefully handles missing GPU)
GPU_TEMP="N/A"
GPU_UTIL="N/A"
GPU_MEM="N/A"
if [ "${ENABLE_GPU_MONITORING:-1}" -eq 1 ] && command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$GPU_INFO" ]; then
        GPU_TEMP=$(echo "$GPU_INFO" | cut -d',' -f1 | tr -d ' ')
        GPU_UTIL=$(echo "$GPU_INFO" | cut -d',' -f2 | tr -d ' ')
        GPU_MEM_USED=$(echo "$GPU_INFO" | cut -d',' -f3 | tr -d ' ')
        GPU_MEM_TOT=$(echo "$GPU_INFO" | cut -d',' -f4 | tr -d ' ')
        GPU_MEM="$GPU_MEM_USED/$GPU_MEM_TOT"
    fi
fi

# System uptime (human-readable and raw days)
UPTIME=$(uptime -p | sed 's/up //')
UPTIME_DAYS=$(awk '{print int($1/86400)}' /proc/uptime)

# Network connections (established TCP/UDP)
NET_CONN=$(ss -tun | grep -c ESTAB 2>/dev/null || echo "0")

# Service status checks via systemctl
DOCKER=$(systemctl is-active docker 2>/dev/null || echo "unknown")
POSTGRES=$(systemctl is-active postgresql@14-main 2>/dev/null || echo "unknown")
OLLAMA=$(systemctl is-active ollama 2>/dev/null || echo "unknown")
SSH=$(systemctl is-active ssh 2>/dev/null || echo "unknown")

# Alert count and recent alerts (pipe-delimited for dashboard)
ALERT_COUNT=$(wc -l < "$ALERT_LOG" 2>/dev/null || echo "0")
RECENT_ALERTS=$(tail -3 "$ALERT_LOG" 2>/dev/null | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')

#-------------------------------------------------------------------------------
# Output JSON
#-------------------------------------------------------------------------------
cat > "$STATS_FILE" << EOF
{
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "cpu": {
    "load": "$LOAD",
    "cores": "$CORES"
  },
  "memory": {
    "used": "$MEM_USED",
    "total": "$MEM_TOTAL",
    "percent": "$MEM_PCT"
  },
  "disk": {
    "percent": "$DISK_PCT",
    "available": "$DISK_AVAIL"
  },
  "gpu": {
    "temp": "$GPU_TEMP",
    "util": "$GPU_UTIL",
    "mem": "$GPU_MEM"
  },
  "uptime": {
    "text": "$UPTIME",
    "days": "$UPTIME_DAYS"
  },
  "network": {
    "connections": "$NET_CONN"
  },
  "services": {
    "docker": "$DOCKER",
    "postgresql": "$POSTGRES",
    "ollama": "$OLLAMA",
    "ssh": "$SSH"
  },
  "alerts": {
    "count": "$ALERT_COUNT",
    "recent": "$RECENT_ALERTS"
  }
}
EOF

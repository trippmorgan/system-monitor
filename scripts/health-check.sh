#!/bin/bash
#===============================================================================
# health-check.sh - System Health Check Script
#===============================================================================
# PURPOSE:
#   Generates a comprehensive daily health report for system monitoring.
#   Checks CPU, memory, disk, GPU, services, and logs - alerting on issues.
#
# USAGE:
#   ~/system-monitor/scripts/health-check.sh
#
# OUTPUT:
#   - Daily report: ~/system-monitor/logs/daily-report-YYYY-MM-DD.log
#   - Alerts:       ~/system-monitor/logs/alerts.log (appended)
#
# CRON:
#   Runs daily at 8:00 AM via crontab
#   0 8 * * * /home/tripp/system-monitor/scripts/health-check.sh
#
# THRESHOLDS:
#   - CPU:    Alert when load exceeds core count
#   - Memory: Alert at 90%+ usage
#   - Swap:   Alert at 50%+ usage
#   - Disk:   Alert at 85%+ usage
#   - GPU:    Alert at 80C+ temperature
#   - Uptime: Recommend reboot after 30 days
#   - Errors: Alert at 100+ journal errors in 24h
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
    # Fallback defaults
    LOG_DIR="$HOME/system-monitor/logs"
    MEM_CRIT=90
    SWAP_WARN=50
    DISK_WARN=80
    GPU_TEMP_CRIT=80
    UPTIME_CRIT=30
    JOURNAL_ERROR_THRESHOLD=100
fi

ALERT_LOG="${ALERT_LOG:-$LOG_DIR/alerts.log}"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)
REPORT="$LOG_DIR/daily-report-$DATE.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------

# alert() - Log critical issues to alerts.log and stdout
# Usage: alert "message"
alert() {
    echo "[$DATE $TIME] ALERT: $1" >> "$ALERT_LOG"
    echo "[ALERT] $1"
}

# info() - Log informational messages to report and stdout
# Usage: info "message"
info() {
    echo "$1" >> "$REPORT"
    echo "$1"
}

#-------------------------------------------------------------------------------
# Report Header
#-------------------------------------------------------------------------------
echo "=============================================" >> "$REPORT"
echo "System Health Report - $DATE $TIME" >> "$REPORT"
echo "=============================================" >> "$REPORT"
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# CPU Load Check
# Alert if load average exceeds number of CPU cores (system overloaded)
#-------------------------------------------------------------------------------
info "--- CPU Load ---"
LOAD=$(cat /proc/loadavg | awk '{print $1}')    # 1-minute load average
CORES=$(nproc)
info "Load Average: $LOAD (Cores: $CORES)"
if (( $(echo "$LOAD > $CORES" | bc -l) )); then
    alert "High CPU load: $LOAD exceeds $CORES cores"
fi
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# Memory Usage Check
# Alert if RAM > 90% or Swap > 50% (potential memory pressure)
#-------------------------------------------------------------------------------
info "--- Memory Usage ---"
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
info "Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)"
if [ $MEM_PERCENT -gt $MEM_CRIT ]; then
    alert "High memory usage: ${MEM_PERCENT}% (threshold: ${MEM_CRIT}%)"
fi

SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
if [ $SWAP_TOTAL -gt 0 ]; then
    SWAP_PERCENT=$((SWAP_USED * 100 / SWAP_TOTAL))
    info "Swap: ${SWAP_USED}MB / ${SWAP_TOTAL}MB (${SWAP_PERCENT}%)"
    if [ $SWAP_PERCENT -gt $SWAP_WARN ]; then
        alert "High swap usage: ${SWAP_PERCENT}% (threshold: ${SWAP_WARN}%)"
    fi
fi
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# Disk Usage Check
# Alert if root partition > 85% full (low disk space warning)
#-------------------------------------------------------------------------------
info "--- Disk Usage ---"
DISK_PERCENT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
info "Root Partition: ${DISK_PERCENT}% used (${DISK_AVAIL} available)"
if [ $DISK_PERCENT -gt $DISK_WARN ]; then
    alert "Low disk space: ${DISK_PERCENT}% used (threshold: ${DISK_WARN}%)"
fi
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# GPU Status Check (NVIDIA only)
# Alert if GPU temperature > 80C (thermal throttling risk)
#-------------------------------------------------------------------------------
info "--- GPU Status ---"
if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$GPU_INFO" ]; then
        GPU_NAME=$(echo "$GPU_INFO" | cut -d',' -f1)
        GPU_TEMP=$(echo "$GPU_INFO" | cut -d',' -f2 | tr -d ' ')
        GPU_UTIL=$(echo "$GPU_INFO" | cut -d',' -f3 | tr -d ' ')
        GPU_MEM_USED=$(echo "$GPU_INFO" | cut -d',' -f4 | tr -d ' ')
        GPU_MEM_TOTAL=$(echo "$GPU_INFO" | cut -d',' -f5 | tr -d ' ')
        info "GPU: $GPU_NAME"
        info "Temperature: ${GPU_TEMP}C | Utilization: ${GPU_UTIL}% | VRAM: ${GPU_MEM_USED}/${GPU_MEM_TOTAL} MB"
        if [ "$GPU_TEMP" -gt $GPU_TEMP_CRIT ]; then
            alert "High GPU temperature: ${GPU_TEMP}C (threshold: ${GPU_TEMP_CRIT}C)"
        fi
    fi
else
    info "No NVIDIA GPU detected"
fi
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# System Uptime Check
# Recommend reboot after 30 days (memory fragmentation, kernel updates)
#-------------------------------------------------------------------------------
info "--- System Uptime ---"
UPTIME=$(uptime -p)
UPTIME_DAYS=$(awk '{print int($1/86400)}' /proc/uptime)
info "Uptime: $UPTIME"
if [ $UPTIME_DAYS -gt $UPTIME_CRIT ]; then
    alert "System uptime exceeds $UPTIME_CRIT days ($UPTIME_DAYS days). Consider rebooting."
fi
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# Failed Services Check
# Alert if any systemd services have failed (indicates system issues)
#-------------------------------------------------------------------------------
info "--- Failed Services ---"
FAILED=$(systemctl --failed --no-legend --no-pager | wc -l)
if [ $FAILED -gt 0 ]; then
    info "Failed services: $FAILED"
    systemctl --failed --no-legend --no-pager >> "$REPORT"
    alert "$FAILED failed service(s) detected"
else
    info "All services running normally"
fi
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# Top Memory Consumers
# Lists top 5 processes by memory usage for resource tracking
#-------------------------------------------------------------------------------
info "--- Top Memory Consumers ---"
ps aux --sort=-%mem | awk 'NR<=6 {printf "%-15s %5s%% %5sMB  %s\n", $1, $4, int($6/1024), $11}' >> "$REPORT"
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# Top CPU Consumers
# Lists top 5 processes by CPU usage for resource tracking
#-------------------------------------------------------------------------------
info "--- Top CPU Consumers ---"
ps aux --sort=-%cpu | awk 'NR<=6 {printf "%-15s %5s%%  %s\n", $1, $3, $11}' >> "$REPORT"
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# Network Connections
# Count of established TCP/UDP connections
#-------------------------------------------------------------------------------
info "--- Active Connections ---"
CONN_COUNT=$(ss -tun | grep -c ESTAB)
info "Established connections: $CONN_COUNT"
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# Journal Error Check
# Alert if > 100 error entries in last 24 hours (indicates problems)
#-------------------------------------------------------------------------------
info "--- Recent Errors (last 24h) ---"
ERROR_COUNT=$(journalctl --since "24 hours ago" -p err --no-pager 2>/dev/null | wc -l)
info "Error log entries: $ERROR_COUNT"
if [ $ERROR_COUNT -gt $JOURNAL_ERROR_THRESHOLD ]; then
    alert "High number of system errors in last 24h: $ERROR_COUNT (threshold: $JOURNAL_ERROR_THRESHOLD)"
fi
echo "" >> "$REPORT"

echo "=============================================" >> "$REPORT"
echo "Report saved to: $REPORT"

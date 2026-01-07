#!/bin/bash
#===============================================================================
# system-monitor-assistant.sh - Continuous Background Monitor
#===============================================================================
# PURPOSE:
#   Monitors system metrics continuously and alerts only on significant changes.
#   Runs as a background daemon, checking metrics every 30 seconds.
#
# USAGE:
#   Foreground: ~/system-monitor/scripts/system-monitor-assistant.sh
#   Background: nohup ~/system-monitor/scripts/system-monitor-assistant.sh &
#
# FEATURES:
#   - Change-based alerting (only alerts when values change - reduces noise)
#   - Two-tier thresholds: WARNING and CRITICAL for each metric
#   - Service monitoring (Docker, PostgreSQL, Ollama)
#   - Auto-refreshes dashboard data when changes detected
#
# CONFIGURATION:
#   Thresholds are loaded from ~/system-monitor/config.sh
#   Override with ~/.config/system-monitor/config
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
    DASHBOARD_DIR="$HOME/system-monitor/dashboard"
    CPU_WARN=6; CPU_CRIT=8
    MEM_WARN=70; MEM_CRIT=90
    DISK_WARN=80; DISK_CRIT=90
    GPU_TEMP_WARN=70; GPU_TEMP_CRIT=85
    CHECK_INTERVAL=30
fi

ALERT_LOG="${ALERT_LOG:-$LOG_DIR/alerts.log}"
STATE_FILE="$LOG_DIR/.monitor-state.json"

mkdir -p "$LOG_DIR"

#-------------------------------------------------------------------------------
# Check for jq (faster/safer JSON parsing)
#-------------------------------------------------------------------------------
HAS_JQ=0
if command -v jq &> /dev/null; then
    HAS_JQ=1
fi

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------

# log_alert() - Log alert to file and stdout
log_alert() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ALERT: $msg" >> "$ALERT_LOG"
    echo "[ALERT] $msg"
}

# log_info() - Log informational message to stdout only
log_info() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# log_error() - Log error message to stderr and optionally to file
log_error() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $msg" >&2
}

#-------------------------------------------------------------------------------
# JSON Parsing Helper
#-------------------------------------------------------------------------------

# json_get() - Extract value from JSON string
# Uses jq if available, falls back to grep
# Args: $1 = JSON string, $2 = key name
json_get() {
    local json="$1"
    local key="$2"

    if [ "$HAS_JQ" -eq 1 ]; then
        echo "$json" | jq -r ".$key // empty" 2>/dev/null
    else
        # Fallback to grep (less robust but works)
        echo "$json" | grep -oP "\"$key\"\s*:\s*\"\K[^\"]+" 2>/dev/null | head -1
    fi
}

#-------------------------------------------------------------------------------
# Data Collection Functions
#-------------------------------------------------------------------------------

# get_current_stats() - Collect all system metrics and return as JSON
# Returns: JSON object with load, mem, disk, gpu_temp, and service statuses
get_current_stats() {
    local load mem_pct disk_pct gpu_temp
    local docker_status postgres_status ollama_status

    # CPU load - handle errors gracefully
    load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    if [ -z "$load" ]; then
        log_error "Failed to read CPU load"
        load="0"
    fi

    # Memory - handle errors gracefully
    mem_pct=$(free 2>/dev/null | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    if [ -z "$mem_pct" ]; then
        log_error "Failed to read memory stats"
        mem_pct="0"
    fi

    # Disk - handle errors gracefully
    disk_pct=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
    if [ -z "$disk_pct" ]; then
        log_error "Failed to read disk stats"
        disk_pct="0"
    fi

    # GPU - optional, don't log error if nvidia-smi missing
    if [ "${ENABLE_GPU_MONITORING:-1}" -eq 1 ] && command -v nvidia-smi &>/dev/null; then
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
        [ -z "$gpu_temp" ] && gpu_temp="0"
    else
        gpu_temp="0"
    fi

    # Service status checks
    docker_status=$(systemctl is-active docker 2>/dev/null || echo "unknown")
    postgres_status=$(systemctl is-active postgresql@14-main 2>/dev/null || echo "unknown")
    ollama_status=$(systemctl is-active ollama 2>/dev/null || echo "unknown")

    echo "{\"load\":\"$load\",\"mem\":\"$mem_pct\",\"disk\":\"$disk_pct\",\"gpu_temp\":\"$gpu_temp\",\"docker\":\"$docker_status\",\"postgres\":\"$postgres_status\",\"ollama\":\"$ollama_status\"}"
}

#-------------------------------------------------------------------------------
# Alert Logic
#-------------------------------------------------------------------------------

# compare_and_alert() - Check metrics against thresholds and alert if exceeded
# Args: $1 = JSON string of current stats
compare_and_alert() {
    local current="$1"

    # Extract values using json_get helper (uses jq if available)
    local load=$(json_get "$current" "load")
    local mem=$(json_get "$current" "mem")
    local disk=$(json_get "$current" "disk")
    local gpu_temp=$(json_get "$current" "gpu_temp")
    local docker=$(json_get "$current" "docker")
    local postgres=$(json_get "$current" "postgres")
    local ollama=$(json_get "$current" "ollama")

    # Check CPU load - uses bc for floating point comparison
    if (( $(echo "$load > $CPU_CRIT" | bc -l) )); then
        log_alert "CRITICAL: CPU load at $load (threshold: $CPU_CRIT)"
    elif (( $(echo "$load > $CPU_WARN" | bc -l) )); then
        log_alert "WARNING: CPU load at $load (threshold: $CPU_WARN)"
    fi

    # Check Memory - integer comparison
    if [ "$mem" -gt "$MEM_CRIT" ]; then
        log_alert "CRITICAL: Memory at ${mem}% (threshold: ${MEM_CRIT}%)"
    elif [ "$mem" -gt "$MEM_WARN" ]; then
        log_alert "WARNING: Memory at ${mem}% (threshold: ${MEM_WARN}%)"
    fi

    # Check Disk usage
    if [ "$disk" -gt "$DISK_CRIT" ]; then
        log_alert "CRITICAL: Disk at ${disk}% (threshold: ${DISK_CRIT}%)"
    elif [ "$disk" -gt "$DISK_WARN" ]; then
        log_alert "WARNING: Disk at ${disk}% (threshold: ${DISK_WARN}%)"
    fi

    # Check GPU temperature
    if [ "$gpu_temp" -gt "$GPU_TEMP_CRIT" ]; then
        log_alert "CRITICAL: GPU temperature at ${gpu_temp}°C (threshold: ${GPU_TEMP_CRIT}°C)"
    elif [ "$gpu_temp" -gt "$GPU_TEMP_WARN" ]; then
        log_alert "WARNING: GPU temperature at ${gpu_temp}°C (threshold: ${GPU_TEMP_WARN}°C)"
    fi

    # Check critical services - alert if any are not active
    if [ "$docker" != "active" ]; then
        log_alert "Service DOWN: Docker is $docker"
    fi
    if [ "$postgres" != "active" ]; then
        log_alert "Service DOWN: PostgreSQL is $postgres"
    fi
    if [ "$ollama" != "active" ]; then
        log_alert "Service DOWN: Ollama is $ollama"
    fi
}

#-------------------------------------------------------------------------------
# Dashboard Integration
#-------------------------------------------------------------------------------

# refresh_dashboard() - Update dashboard JSON data when stats change
refresh_dashboard() {
    log_info "Refreshing dashboard data..."
    "$DASHBOARD_DIR/system-stats.sh" 2>/dev/null
}

#===============================================================================
# Main Monitoring Loop
#===============================================================================
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║      System Monitor Assistant Started      ║"
echo "╚════════════════════════════════════════════╝"
echo ""
log_info "Monitoring system... (Ctrl+C to stop)"
log_info "Thresholds: CPU=$CPU_WARN/$CPU_CRIT | MEM=$MEM_WARN/$MEM_CRIT% | DISK=$DISK_WARN/$DISK_CRIT% | GPU=$GPU_TEMP_WARN/$GPU_TEMP_CRIT°C"
echo ""

# State tracking for change detection
LAST_STATS=""
# CHECK_INTERVAL loaded from config.sh (default: 30 seconds)

# Infinite monitoring loop - Ctrl+C to stop
while true; do
    CURRENT_STATS=$(get_current_stats)

    # Check if stats changed significantly
    if [ "$CURRENT_STATS" != "$LAST_STATS" ]; then
        compare_and_alert "$CURRENT_STATS"
        refresh_dashboard
        LAST_STATS="$CURRENT_STATS"
    fi

    # Show status using json_get helper for consistent parsing
    load=$(json_get "$CURRENT_STATS" "load")
    mem=$(json_get "$CURRENT_STATS" "mem")
    log_info "Status: CPU=$load | MEM=${mem}% | Sleeping ${CHECK_INTERVAL}s..."

    sleep $CHECK_INTERVAL
done

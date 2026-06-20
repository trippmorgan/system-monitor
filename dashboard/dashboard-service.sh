#!/bin/bash
#===============================================================================
# dashboard-service.sh - Systemd Wrapper for Radio Free Albany
#===============================================================================
# Runs the dashboard in foreground mode for systemd.
#
# USAGE: ExecStart in systemd unit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    DASHBOARD_DIR="$HOME/system-monitor/dashboard"
    DASHBOARD_PORT=8787
    DASHBOARD_BIND_HOST=0.0.0.0
    CHECK_INTERVAL=30
    NEWS_REFRESH_INTERVAL=5
fi

DASHBOARD_DIR="${DASHBOARD_DIR:-$HOME/system-monitor/dashboard}"
PORT="${DASHBOARD_PORT:-8787}"
BIND_HOST="${DASHBOARD_BIND_HOST:-0.0.0.0}"

# Trap termination to clean up child processes
cleanup() {
    echo "Stopping Radio Free Albany..."
    kill $(jobs -p) 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

# 1. Initial Data Fetch
echo "Fetching initial data..."
"$DASHBOARD_DIR/system-stats.sh"
"$DASHBOARD_DIR/news-fetcher.sh"

# 2. Start Background Refresh Loop
echo "Starting background refresh loop..."
(
    while true; do
        sleep $CHECK_INTERVAL
        "$DASHBOARD_DIR/system-stats.sh" >/dev/null 2>&1
        
        # News refresh logic
        MINS=$((10#$(date +%M)))
        if [ $((MINS % NEWS_REFRESH_INTERVAL)) -eq 0 ]; then
             "$DASHBOARD_DIR/news-fetcher.sh" >/dev/null 2>&1
        fi
    done
) &

# 3. Start Python Server (Foreground)
echo "Starting web server on $BIND_HOST:$PORT..."
cd "$DASHBOARD_DIR"
python3 -m http.server "$PORT" --bind "$BIND_HOST"

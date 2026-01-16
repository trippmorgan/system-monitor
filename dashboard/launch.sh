#!/bin/bash
#===============================================================================
# launch.sh - Command Center Dashboard Launcher
#===============================================================================
# PURPOSE:
#   Starts the complete Command Center ecosystem including:
#   - Initial data fetch (system stats + news)
#   - Background refresh loop (stats every 30s, news every 5min)
#   - Python HTTP server for the web dashboard
#   - Opens dashboard in default browser
#
# USAGE:
#   ~/system-monitor/dashboard/launch.sh
#   or use alias: command-center
#
# TO STOP:
#   ~/system-monitor/dashboard/stop.sh
#
# PORTS:
#   Dashboard served on http://localhost:8787
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
    DASHBOARD_DIR="$HOME/system-monitor/dashboard"
    DASHBOARD_PORT=8787
    CHECK_INTERVAL=30
    NEWS_REFRESH_INTERVAL=5
    ENABLE_BROWSER_OPEN=1
fi

DASHBOARD_DIR="${DASHBOARD_DIR:-$HOME/system-monitor/dashboard}"
PID_FILE="$DASHBOARD_DIR/.refresh.pid"       # Stores refresh loop PID
SERVER_PID_FILE="$DASHBOARD_DIR/.server.pid" # Stores HTTP server PID
PORT="${DASHBOARD_PORT:-8787}"

# Terminal colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════╗"
echo "║       Radio Free Albany - Launcher         ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${NC}"

#-------------------------------------------------------------------------------
# Cleanup - Kill any existing processes from previous runs
#-------------------------------------------------------------------------------
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    kill "$OLD_PID" 2>/dev/null
    rm "$PID_FILE"
fi

if [ -f "$SERVER_PID_FILE" ]; then
    OLD_PID=$(cat "$SERVER_PID_FILE")
    kill "$OLD_PID" 2>/dev/null
    rm "$SERVER_PID_FILE"
fi

# Kill any existing server on our port
fuser -k $PORT/tcp 2>/dev/null

#-------------------------------------------------------------------------------
# Step 1: Initial Data Fetch
#-------------------------------------------------------------------------------
echo -e "${GREEN}[1/4]${NC} Fetching initial data..."
chmod +x "$DASHBOARD_DIR/news-fetcher.sh" "$DASHBOARD_DIR/system-stats.sh" 2>/dev/null
"$DASHBOARD_DIR/system-stats.sh"
"$DASHBOARD_DIR/news-fetcher.sh" 2>/dev/null

#-------------------------------------------------------------------------------
# Step 2: Start Background Refresh Loop
# - System stats refresh every CHECK_INTERVAL seconds (default: 30)
# - News refresh every NEWS_REFRESH_INTERVAL minutes (default: 5)
#-------------------------------------------------------------------------------
echo -e "${GREEN}[2/4]${NC} Starting background refresh (every ${CHECK_INTERVAL}s)..."
(
    while true; do
        sleep $CHECK_INTERVAL
        "$DASHBOARD_DIR/system-stats.sh" 2>/dev/null
        # Refresh news every NEWS_REFRESH_INTERVAL minutes
        # Use 10# prefix to force base-10 interpretation (avoids octal error with 08, 09)
        MINS=$((10#$(date +%M)))
        if [ $((MINS % NEWS_REFRESH_INTERVAL)) -eq 0 ]; then
            "$DASHBOARD_DIR/news-fetcher.sh" 2>/dev/null
        fi
    done
) &
echo $! > "$PID_FILE"

#-------------------------------------------------------------------------------
# Step 3: Start HTTP Server
# Python's built-in server, bound to localhost only for security
#-------------------------------------------------------------------------------
echo -e "${GREEN}[3/4]${NC} Starting web server on port $PORT..."
cd "$DASHBOARD_DIR"
python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1 &
echo $! > "$SERVER_PID_FILE"
sleep 1

#-------------------------------------------------------------------------------
# Step 4: Open Dashboard in Browser (if enabled)
# Tries xdg-open, then Firefox, then Chrome
#-------------------------------------------------------------------------------
DASHBOARD_URL="http://localhost:$PORT/index.html"

if [ "${ENABLE_BROWSER_OPEN:-1}" -eq 1 ]; then
    echo -e "${GREEN}[4/4]${NC} Opening dashboard in browser..."
    if command -v xdg-open &> /dev/null; then
        xdg-open "$DASHBOARD_URL" 2>/dev/null &
    elif command -v firefox &> /dev/null; then
        firefox "$DASHBOARD_URL" 2>/dev/null &
    elif command -v google-chrome &> /dev/null; then
        google-chrome "$DASHBOARD_URL" 2>/dev/null &
    else
        echo -e "${YELLOW}Please open manually: $DASHBOARD_URL${NC}"
    fi
else
    echo -e "${GREEN}[4/4]${NC} Browser auto-open disabled"
fi

echo ""
echo -e "${GREEN}Dashboard launched!${NC}"
echo ""
echo -e "Dashboard URL: ${CYAN}$DASHBOARD_URL${NC}"
echo ""
echo "Background processes running:"
echo "  - Data refresh: PID $(cat $PID_FILE)"
echo "  - Web server:   PID $(cat $SERVER_PID_FILE) on port $PORT"
echo ""
echo "To stop everything: ~/system-monitor/dashboard/stop.sh"
echo "To chat with Claude: run 'claude' in terminal"
echo ""

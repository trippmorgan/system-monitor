#!/bin/bash
#===============================================================================
# stop.sh - Stop Radio Free Albany Background Processes
#===============================================================================
# PURPOSE:
#   Cleanly stops all Radio Free Albany background processes started by launch.sh.
#   Kills both the data refresh loop and the HTTP server.
#
# USAGE:
#   ~/Documents/radio-free-albany/dashboard/stop.sh
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi
DASHBOARD_DIR="${DASHBOARD_DIR:-$SCRIPT_DIR}"
PID_FILE="$DASHBOARD_DIR/.refresh.pid"
SERVER_PID_FILE="$DASHBOARD_DIR/.server.pid"

echo "Stopping Radio Free Albany..."

# Kill the background data refresh loop
if [ -f "$PID_FILE" ]; then
    kill $(cat "$PID_FILE") 2>/dev/null && echo "  Stopped data refresh"
    rm "$PID_FILE"
fi

# Kill the HTTP server
if [ -f "$SERVER_PID_FILE" ]; then
    kill $(cat "$SERVER_PID_FILE") 2>/dev/null && echo "  Stopped web server"
    rm "$SERVER_PID_FILE"
fi

echo "Done."

#!/bin/bash
#===============================================================================
# network-sentry.sh - Active Network Watchdog
#===============================================================================
# Pings critical devices and logs status changes.
# Can be run via cron (every 5 mins) or continuously.

# Configuration
LOG_FILE="$HOME/system-monitor/logs/alerts.log"
STATE_FILE="$HOME/system-monitor/logs/network_state.json"

# Targets (Name|IP)
TARGETS=(
    "Router|192.168.0.10"
    "NAS|192.168.0.194"
)

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# Ensure state file exists
if [ ! -f "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
fi

for target in "${TARGETS[@]}"; do
    NAME="${target%%|*}"
    IP="${target##*|}"
    
    # Ping check (1 packet, 2s timeout)
    if ping -c 1 -W 2 "$IP" > /dev/null 2>&1; then
        CURRENT_STATUS="UP"
    else
        # Retry once to be sure
        sleep 2
        if ping -c 1 -W 2 "$IP" > /dev/null 2>&1; then
            CURRENT_STATUS="UP"
        else
            CURRENT_STATUS="DOWN"
        fi
    fi

    # Read previous status
    PREV_STATUS=$(jq -r --arg ip "$IP" '.[$ip] // "UNKNOWN"' "$STATE_FILE")

    # If status changed
    if [ "$CURRENT_STATUS" != "$PREV_STATUS" ]; then
        echo "$(timestamp) [NETWORK] Alert: $NAME ($IP) is now $CURRENT_STATUS" >> "$LOG_FILE"
        
        # Update state file
        TEMP=$(mktemp)
        jq --arg ip "$IP" --arg status "$CURRENT_STATUS" '.[$ip] = $status' "$STATE_FILE" > "$TEMP" && mv "$TEMP" "$STATE_FILE"
    fi
done

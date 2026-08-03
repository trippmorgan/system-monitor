#!/bin/bash
#===============================================================================
# email-watcher.sh - Simple IMAP Inbox Checker
#===============================================================================
# Credentials are read from environment variables:
#   SYSTEM_MONITOR_IMAP_USER
#   SYSTEM_MONITOR_IMAP_PASS
# Optional:
#   SYSTEM_MONITOR_IMAP_URL (default: imaps://imap.gmail.com:993)

set -euo pipefail

IMAP_HOST="${SYSTEM_MONITOR_IMAP_URL:-imaps://imap.gmail.com:993}"
USER="${SYSTEM_MONITOR_IMAP_USER:-}"
PASS="${SYSTEM_MONITOR_IMAP_PASS:-}"

if [ -z "$USER" ] || [ -z "$PASS" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [EMAIL] Missing IMAP env credentials; skipping" >> "$HOME/system-monitor/logs/alerts.log"
    exit 0
fi

LOG_FILE="$HOME/system-monitor/logs/alerts.log"
STATE_FILE="$HOME/system-monitor/logs/email_state.json"

mkdir -p "$(dirname "$LOG_FILE")"
[ ! -f "$STATE_FILE" ] && echo "{}" > "$STATE_FILE"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

RESPONSE=$(curl -s -u "$USER:$PASS" "$IMAP_HOST/INBOX?SEARCH UNSEEN")
IDS=$(echo "$RESPONSE" | grep "^* SEARCH" | cut -d' ' -f3- || true)

[ -z "$IDS" ] && exit 0

for ID in $IDS; do
    [[ ! "$ID" =~ ^[0-9]+$ ]] && continue

    SEEN=$(jq -r --arg id "$ID" '.[$id] // "no"' "$STATE_FILE")
    if [ "$SEEN" = "no" ]; then
        HEADER=$(curl -s -u "$USER:$PASS" "$IMAP_HOST/INBOX;UID=$ID" -X "FETCH $ID (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM)])")
        SUBJECT=$(echo "$HEADER" | grep -i "^Subject:" | sed 's/^Subject: //I' | tr -d '\r' || true)
        FROM=$(echo "$HEADER" | grep -i "^From:" | sed 's/^From: //I' | tr -d '\r' || true)

        echo "$(timestamp) [EMAIL] New: $SUBJECT (from $FROM)" >> "$LOG_FILE"

        TEMP_JSON=$(mktemp)
        jq --arg id "$ID" --arg sub "$SUBJECT" '.[$id] = $sub' "$STATE_FILE" > "$TEMP_JSON" && mv "$TEMP_JSON" "$STATE_FILE"
    fi
done

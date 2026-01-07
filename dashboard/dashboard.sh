#!/bin/bash
#===============================================================================
# dashboard.sh - Terminal-Based System Dashboard
#===============================================================================
# PURPOSE:
#   Displays a quick system status overview directly in the terminal.
#   Alternative to the web-based Command Center for quick checks.
#
# USAGE:
#   ~/system-monitor/dashboard/dashboard.sh
#   or use alias: dashboard
#
# DISPLAYS:
#   - System status (CPU, Memory, Disk, GPU, Uptime, Network)
#   - Key service status (Docker, PostgreSQL, Ollama, SSH, NoMachine)
#   - Recent alerts from alerts.log
#   - Top 5 processes by CPU usage
#   - Hacker News headlines (cached for 1 hour)
#   - Quick action commands
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
    ALERT_LOG="$HOME/system-monitor/logs/alerts.log"
fi

DASHBOARD_DIR="${DASHBOARD_DIR:-$HOME/system-monitor/dashboard}"
ALERT_LOG="${ALERT_LOG:-$LOG_DIR/alerts.log}"

# Terminal colors (ANSI escape codes)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'    # No Color - reset
BOLD='\033[1m'

#===============================================================================
# Dashboard Display
#===============================================================================
clear

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    SYSTEM DASHBOARD - $(date '+%A, %B %d, %Y')                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

#-------------------------------------------------------------------------------
# System Status Section
# Shows CPU, Memory, Disk, GPU, Uptime, and Network with color-coded status
#-------------------------------------------------------------------------------
echo -e "${BOLD}${BLUE}▶ SYSTEM STATUS${NC}"
echo "─────────────────────────────────────────────────────────────────────────────────"

# CPU
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
CORES=$(nproc)
LOAD1=$(echo $LOAD | awk '{print $1}')
if (( $(echo "$LOAD1 > $CORES" | bc -l 2>/dev/null || echo 0) )); then
    CPU_STATUS="${RED}HIGH${NC}"
else
    CPU_STATUS="${GREEN}OK${NC}"
fi
printf "  ${BOLD}CPU:${NC}      Load: %-15s Cores: %-4s Status: %b\n" "$LOAD" "$CORES" "$CPU_STATUS"

# Memory
MEM_INFO=$(free -m | awk '/Mem:/ {printf "%dMB / %dMB (%d%%)", $3, $2, $3*100/$2}')
MEM_PCT=$(free -m | awk '/Mem:/ {print int($3*100/$2)}')
if [ $MEM_PCT -gt 90 ]; then
    MEM_STATUS="${RED}HIGH${NC}"
elif [ $MEM_PCT -gt 70 ]; then
    MEM_STATUS="${YELLOW}WARN${NC}"
else
    MEM_STATUS="${GREEN}OK${NC}"
fi
printf "  ${BOLD}Memory:${NC}   %-35s Status: %b\n" "$MEM_INFO" "$MEM_STATUS"

# Disk
DISK_INFO=$(df -h / | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
if [ $DISK_PCT -gt 90 ]; then
    DISK_STATUS="${RED}LOW${NC}"
elif [ $DISK_PCT -gt 80 ]; then
    DISK_STATUS="${YELLOW}WARN${NC}"
else
    DISK_STATUS="${GREEN}OK${NC}"
fi
printf "  ${BOLD}Disk:${NC}     %-35s Status: %b\n" "$DISK_INFO" "$DISK_STATUS"

# GPU
if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$GPU_INFO" ]; then
        GPU_TEMP=$(echo "$GPU_INFO" | cut -d',' -f1 | tr -d ' ')
        GPU_UTIL=$(echo "$GPU_INFO" | cut -d',' -f2 | tr -d ' ')
        GPU_MEM=$(echo "$GPU_INFO" | cut -d',' -f3 | tr -d ' ')
        GPU_MEM_TOT=$(echo "$GPU_INFO" | cut -d',' -f4 | tr -d ' ')
        if [ "$GPU_TEMP" -gt 80 ]; then
            GPU_STATUS="${RED}HOT${NC}"
        else
            GPU_STATUS="${GREEN}OK${NC}"
        fi
        printf "  ${BOLD}GPU:${NC}      Temp: %s°C | Util: %s%% | VRAM: %s/%sMB    Status: %b\n" "$GPU_TEMP" "$GPU_UTIL" "$GPU_MEM" "$GPU_MEM_TOT" "$GPU_STATUS"
    fi
fi

# Uptime
UPTIME=$(uptime -p | sed 's/up //')
UPTIME_DAYS=$(awk '{print int($1/86400)}' /proc/uptime)
if [ $UPTIME_DAYS -gt 14 ]; then
    UPTIME_STATUS="${YELLOW}REBOOT SOON${NC}"
else
    UPTIME_STATUS="${GREEN}OK${NC}"
fi
printf "  ${BOLD}Uptime:${NC}   %-35s Status: %b\n" "$UPTIME" "$UPTIME_STATUS"

# Network
NET_CONN=$(ss -tun | grep -c ESTAB 2>/dev/null || echo "?")
NET_INFO="$NET_CONN active connections"
printf "  ${BOLD}Network:${NC}  %-35s\n" "$NET_INFO"

echo ""

#-------------------------------------------------------------------------------
# Services Section
# Checks status of key systemd services
#-------------------------------------------------------------------------------
echo -e "${BOLD}${BLUE}▶ KEY SERVICES${NC}"
echo "─────────────────────────────────────────────────────────────────────────────────"

# check_service() - Display service status with color indicator
check_service() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        printf "  %-20s %b\n" "$1" "${GREEN}● Running${NC}"
    else
        printf "  %-20s %b\n" "$1" "${RED}○ Stopped${NC}"
    fi
}

check_service "docker"
check_service "postgresql@14-main"
check_service "ollama"
check_service "ssh"
check_service "nxserver"

echo ""

#-------------------------------------------------------------------------------
# Alerts Section
# Shows last 5 alerts from the alerts log
#-------------------------------------------------------------------------------
echo -e "${BOLD}${BLUE}▶ RECENT ALERTS${NC}"
echo "─────────────────────────────────────────────────────────────────────────────────"
if [ -f "$ALERT_LOG" ] && [ -s "$ALERT_LOG" ]; then
    tail -5 "$ALERT_LOG" | while read line; do
        echo -e "  ${YELLOW}⚠${NC} $line"
    done
else
    echo -e "  ${GREEN}✓ No recent alerts${NC}"
fi

echo ""

#-------------------------------------------------------------------------------
# Processes Section
# Shows top 5 CPU-consuming processes
#-------------------------------------------------------------------------------
echo -e "${BOLD}${BLUE}▶ TOP PROCESSES (by CPU)${NC}"
echo "─────────────────────────────────────────────────────────────────────────────────"
ps aux --sort=-%cpu | awk 'NR>1 && NR<=6 {printf "  %-12s %5.1f%% CPU  %5.1f%% MEM  %s\n", $1, $3, $4, $11}'

echo ""

#-------------------------------------------------------------------------------
# News Section
# Fetches Hacker News headlines (cached for 1 hour to reduce API calls)
#-------------------------------------------------------------------------------
echo -e "${BOLD}${MAGENTA}▶ NEWS HEADLINES${NC}"
echo "─────────────────────────────────────────────────────────────────────────────────"

# News cache configuration
NEWS_CACHE="$DASHBOARD_DIR/.news_cache"
NEWS_AGE="${NEWS_CACHE_TTL:-3600}"  # Cache TTL from config (default: 1 hour)

# fetch_news() - Fetch top 5 Hacker News stories via Firebase API
fetch_news() {
    # Using Hacker News top stories API (simple, no auth required)
    curl -s --max-time 5 "https://hacker-news.firebaseio.com/v0/topstories.json" 2>/dev/null | \
        head -c 100 | grep -oP '\d+' | head -5 | while read id; do
            curl -s --max-time 3 "https://hacker-news.firebaseio.com/v0/item/$id.json" 2>/dev/null | \
                grep -oP '"title":"[^"]*"|"url":"[^"]*"' | \
                tr '\n' '|' | sed 's/|$/\n/'
        done
}

# Check if cache exists and is fresh
if [ -f "$NEWS_CACHE" ] && [ $(($(date +%s) - $(stat -c %Y "$NEWS_CACHE" 2>/dev/null || echo 0))) -lt $NEWS_AGE ]; then
    cat "$NEWS_CACHE"
else
    NEWS=$(fetch_news 2>/dev/null)
    if [ -n "$NEWS" ]; then
        echo "$NEWS" > "$NEWS_CACHE"
        echo "$NEWS"
    elif [ -f "$NEWS_CACHE" ]; then
        cat "$NEWS_CACHE"
    else
        echo "  Unable to fetch news. Check internet connection."
    fi
fi | head -5 | while IFS='|' read title url; do
    TITLE=$(echo "$title" | sed 's/"title":"//;s/"$//')
    URL=$(echo "$url" | sed 's/"url":"//;s/"$//')
    if [ -n "$TITLE" ]; then
        # Make it clickable in terminal (OSC 8 hyperlink)
        if [ -n "$URL" ]; then
            echo -e "  ${CYAN}•${NC} \e]8;;$URL\e\\${TITLE}\e]8;;\e\\"
        else
            echo -e "  ${CYAN}•${NC} $TITLE"
        fi
    fi
done

echo ""
echo -e "${CYAN}─────────────────────────────────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Quick Actions:${NC}"
echo -e "    Run health check:  ~/system-monitor/scripts/health-check.sh"
echo -e "    Run cleanup:       ~/system-monitor/scripts/cleanup.sh"
echo -e "    View full report:  cat ~/system-monitor/logs/daily-report-$(date +%Y-%m-%d).log"
echo -e "    Edit goals:        nano ~/CLAUDE.md"
echo -e "${CYAN}─────────────────────────────────────────────────────────────────────────────────${NC}"
echo ""

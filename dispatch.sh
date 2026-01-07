#!/bin/bash
# dispatch.sh - Agent selection menu

MONITOR_HOME="${MONITOR_HOME:-$HOME/system-monitor}"

clear
echo "╔════════════════════════════════════════╗"
echo "║       SYSTEM MONITOR DISPATCH          ║"
echo "╠════════════════════════════════════════╣"
echo "║  1) System Tech   - health & services  ║"
echo "║  2) News Curator  - headlines & news   ║"
echo "║  3) Orchestrator  - help me decide     ║"
echo "║  0) Exit                               ║"
echo "╚════════════════════════════════════════╝"
echo ""
read -p "Select agent [1-3]: " choice

case $choice in
    1)
        echo "Launching System Tech agent..."
        cd "$MONITOR_HOME/agents/system-tech" && claude
        ;;
    2)
        echo "Launching News Curator agent..."
        cd "$MONITOR_HOME/agents/news-curator" && claude
        ;;
    3)
        echo "Launching Orchestrator..."
        cd "$MONITOR_HOME/agents/orchestrator" && claude
        ;;
    0)
        echo "Goodbye."
        exit 0
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

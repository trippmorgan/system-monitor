#!/bin/bash
#===============================================================================
# validate.sh - System Monitor Validation Script
#===============================================================================
# PURPOSE:
#   Validates the system-monitor installation by checking:
#   - Required dependencies are installed
#   - All scripts are executable
#   - Configuration is valid
#   - Directories exist and are writable
#   - Basic functionality works
#
# USAGE:
#   ~/system-monitor/scripts/validate.sh
#
# EXIT CODES:
#   0 - All checks passed
#   1 - One or more checks failed (review output)
#===============================================================================

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_HOME="$(dirname "$SCRIPT_DIR")"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Counters
PASS=0
FAIL=0
WARN=0

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++))
}

check_warn() {
    echo -e "  ${YELLOW}!${NC} $1"
    ((WARN++))
}

check_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

section() {
    echo ""
    echo -e "${BOLD}${CYAN}▶ $1${NC}"
    echo "─────────────────────────────────────────────"
}

#===============================================================================
# Validation Checks
#===============================================================================

echo ""
echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════╗"
echo "║     System Monitor - Validation Check      ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${NC}"

#-------------------------------------------------------------------------------
# Section 1: Required Dependencies
#-------------------------------------------------------------------------------
section "Required Dependencies"

# bash (obviously present if this is running)
check_pass "bash"

# bc - for floating point comparisons
if command -v bc &>/dev/null; then
    check_pass "bc (math operations)"
else
    check_fail "bc not installed (required for CPU load comparisons)"
fi

# awk - for text processing
if command -v awk &>/dev/null; then
    check_pass "awk (text processing)"
else
    check_fail "awk not installed (required)"
fi

# curl - for news fetching
if command -v curl &>/dev/null; then
    check_pass "curl (HTTP requests)"
else
    check_fail "curl not installed (required for news fetching)"
fi

# python3 - for HTTP server and JSON processing
if command -v python3 &>/dev/null; then
    check_pass "python3 ($(python3 --version 2>&1 | awk '{print $2}'))"
else
    check_fail "python3 not installed (required for dashboard server)"
fi

# systemctl - for service monitoring
if command -v systemctl &>/dev/null; then
    check_pass "systemctl (service monitoring)"
else
    check_warn "systemctl not found (service monitoring will be limited)"
fi

#-------------------------------------------------------------------------------
# Section 2: Optional Dependencies
#-------------------------------------------------------------------------------
section "Optional Dependencies"

# jq - faster JSON parsing
if command -v jq &>/dev/null; then
    check_pass "jq $(jq --version 2>&1) (faster JSON parsing)"
else
    check_info "jq not installed (will use grep fallback - install for better performance)"
fi

# nvidia-smi - GPU monitoring
if command -v nvidia-smi &>/dev/null; then
    GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    if [ -n "$GPU" ]; then
        check_pass "nvidia-smi (GPU: $GPU)"
    else
        check_warn "nvidia-smi found but no GPU detected"
    fi
else
    check_info "nvidia-smi not found (GPU monitoring disabled)"
fi

#-------------------------------------------------------------------------------
# Section 3: Configuration
#-------------------------------------------------------------------------------
section "Configuration"

CONFIG_FILE="$MONITOR_HOME/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    check_pass "config.sh exists"

    # Try sourcing it
    if source "$CONFIG_FILE" 2>/dev/null; then
        check_pass "config.sh sources without errors"

        # Check key variables
        [ -n "$LOG_DIR" ] && check_pass "LOG_DIR defined: $LOG_DIR" || check_fail "LOG_DIR not defined"
        [ -n "$DASHBOARD_DIR" ] && check_pass "DASHBOARD_DIR defined" || check_fail "DASHBOARD_DIR not defined"
        [ -n "$CPU_WARN" ] && check_pass "Thresholds defined (CPU_WARN=$CPU_WARN)" || check_fail "Thresholds not defined"
    else
        check_fail "config.sh has syntax errors"
    fi
else
    check_fail "config.sh not found at $CONFIG_FILE"
fi

# User override config
USER_CONFIG="$HOME/.config/system-monitor/config"
if [ -f "$USER_CONFIG" ]; then
    check_info "User override config found: $USER_CONFIG"
fi

#-------------------------------------------------------------------------------
# Section 4: Directory Structure
#-------------------------------------------------------------------------------
section "Directory Structure"

# Check main directories
for dir in scripts dashboard logs; do
    if [ -d "$MONITOR_HOME/$dir" ]; then
        check_pass "$dir/"
    else
        check_fail "$dir/ directory missing"
    fi
done

# Check logs directory is writable
if [ -w "$LOG_DIR" ]; then
    check_pass "logs/ is writable"
else
    check_fail "logs/ is not writable"
fi

# Check news-cache directory
if [ -d "$MONITOR_HOME/dashboard/news-cache" ]; then
    check_pass "dashboard/news-cache/"
else
    check_warn "dashboard/news-cache/ missing (will be created on first run)"
fi

#-------------------------------------------------------------------------------
# Section 5: Script Executability
#-------------------------------------------------------------------------------
section "Scripts"

SCRIPTS=(
    "scripts/health-check.sh"
    "scripts/cleanup.sh"
    "scripts/system-monitor-assistant.sh"
    "scripts/validate.sh"
    "dashboard/launch.sh"
    "dashboard/stop.sh"
    "dashboard/dashboard.sh"
    "dashboard/system-stats.sh"
    "dashboard/news-fetcher.sh"
)

for script in "${SCRIPTS[@]}"; do
    path="$MONITOR_HOME/$script"
    if [ -f "$path" ]; then
        if [ -x "$path" ]; then
            check_pass "$script"
        else
            check_warn "$script exists but not executable"
        fi
    else
        check_fail "$script not found"
    fi
done

#-------------------------------------------------------------------------------
# Section 6: Dashboard Files
#-------------------------------------------------------------------------------
section "Dashboard Files"

if [ -f "$MONITOR_HOME/dashboard/index.html" ]; then
    check_pass "index.html"
else
    check_fail "index.html not found"
fi

#-------------------------------------------------------------------------------
# Section 7: Basic Functionality Tests
#-------------------------------------------------------------------------------
section "Functionality Tests"

# Test CPU load reading
if LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}'); then
    check_pass "CPU load readable: $LOAD"
else
    check_fail "Cannot read CPU load from /proc/loadavg"
fi

# Test memory reading
if MEM=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%d%%", $3*100/$2}'); then
    check_pass "Memory stats readable: $MEM used"
else
    check_fail "Cannot read memory stats"
fi

# Test disk reading
if DISK=$(df / 2>/dev/null | awk 'NR==2 {print $5}'); then
    check_pass "Disk stats readable: $DISK used"
else
    check_fail "Cannot read disk stats"
fi

# Test network reading
if CONN=$(ss -tun 2>/dev/null | grep -c ESTAB); then
    check_pass "Network stats readable: $CONN connections"
else
    check_warn "Cannot read network stats (ss command failed)"
fi

#-------------------------------------------------------------------------------
# Section 8: Port Availability
#-------------------------------------------------------------------------------
section "Network"

PORT="${DASHBOARD_PORT:-8787}"
if command -v ss &>/dev/null; then
    if ss -tuln | grep -q ":$PORT "; then
        check_warn "Port $PORT is already in use (dashboard may be running)"
    else
        check_pass "Port $PORT is available"
    fi
fi

#===============================================================================
# Summary
#===============================================================================
echo ""
echo "─────────────────────────────────────────────"
echo -e "${BOLD}Summary${NC}"
echo "─────────────────────────────────────────────"
echo -e "  ${GREEN}Passed:${NC}   $PASS"
echo -e "  ${RED}Failed:${NC}   $FAIL"
echo -e "  ${YELLOW}Warnings:${NC} $WARN"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ All required checks passed!${NC}"
    echo ""
    echo "Quick start:"
    echo "  Terminal dashboard:  ~/system-monitor/dashboard/dashboard.sh"
    echo "  Radio Free Albany:   ~/system-monitor/dashboard/launch.sh"
    echo "  Health check:        ~/system-monitor/scripts/health-check.sh"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}✗ Some checks failed. Please review the output above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "  Install bc:          sudo apt install bc"
    echo "  Install jq:          sudo apt install jq"
    echo "  Make scripts executable: chmod +x ~/system-monitor/scripts/*.sh"
    echo ""
    exit 1
fi

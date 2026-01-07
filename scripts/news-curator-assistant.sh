#!/bin/bash
#===============================================================================
# news-curator-assistant.sh - Interactive News Browser
#===============================================================================
# PURPOSE:
#   Interactive terminal-based news desk for browsing curated news feeds.
#   Provides menu-driven access to 8 news categories with Claude integration.
#
# USAGE:
#   ~/system-monitor/scripts/news-curator-assistant.sh
#   or use alias: news-desk
#
# FEATURES:
#   - Menu-driven category browsing
#   - Color-coded bias labels on stories
#   - Integrates with Claude for news discussion
#   - Refreshes news from all sources on demand
#
# CATEGORIES:
#   Local (Albany GA), State (Georgia), Sports (CFB), Politics (major),
#   Tech (Hacker News), Nature, Fishing/Hunting, Conservation
#===============================================================================

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
NEWS_DIR="$HOME/system-monitor/dashboard/news-cache"
NEWS_JSON="$NEWS_DIR/news.json"
FETCHER="$HOME/system-monitor/dashboard/news-fetcher.sh"

#-------------------------------------------------------------------------------
# Terminal Colors (ANSI escape codes)
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'    # No Color - reset

clear
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   NEWS DESK - COMMAND CENTER                  ║"
echo "║              Your Personal News Curator Assistant             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

#-------------------------------------------------------------------------------
# Menu Functions
#-------------------------------------------------------------------------------

# show_menu() - Display the main menu options
show_menu() {
    echo -e "${BOLD}What would you like to do?${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) Refresh all news feeds"
    echo -e "  ${CYAN}2${NC}) Show headlines by category"
    echo -e "  ${CYAN}3${NC}) Show Local News (Albany, GA)"
    echo -e "  ${CYAN}4${NC}) Show Georgia State News"
    echo -e "  ${CYAN}5${NC}) Show College Football"
    echo -e "  ${CYAN}6${NC}) Show Nature & Outdoors"
    echo -e "  ${CYAN}7${NC}) Show Fly Fishing & Hunting"
    echo -e "  ${CYAN}8${NC}) Show Tech News"
    echo -e "  ${CYAN}9${NC}) Show all headlines"
    echo -e "  ${CYAN}0${NC}) Exit"
    echo ""
    echo -e "  ${YELLOW}c${NC}) Chat about the news (opens Claude)"
    echo ""
}

# refresh_news() - Fetch fresh news from all sources
refresh_news() {
    echo -e "${YELLOW}Fetching fresh news from all sources...${NC}"
    echo ""
    "$FETCHER"
    echo ""
    echo -e "${GREEN}News refreshed!${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# News Display Functions
#-------------------------------------------------------------------------------

# show_category() - Display news items for a specific category
# Args: $1 = category key (e.g., "local", "tech")
#       $2 = display title
show_category() {
    local category="$1"
    local title="$2"

    echo ""
    echo -e "${BOLD}${MAGENTA}═══ $title ═══${NC}"
    echo ""

    if [ ! -f "$NEWS_JSON" ]; then
        echo -e "${RED}No news data. Run refresh first.${NC}"
        return
    fi

    python3 << EOF
import json
try:
    with open('$NEWS_JSON') as f:
        news = json.load(f)

    items = [n for n in news if n.get('category') == '$category']

    if not items:
        print("  No news in this category.")
    else:
        for i, item in enumerate(items[:10], 1):
            title = item.get('title', 'No title')[:80]
            source = item.get('source', 'Unknown')
            bias = item.get('bias_label', '')
            url = item.get('url', '')

            # Bias color
            bias_color = '\033[0;35m'  # purple/center
            if item.get('bias', 0) < -20:
                bias_color = '\033[0;34m'  # blue/left
            elif item.get('bias', 0) > 20:
                bias_color = '\033[0;31m'  # red/right

            print(f"  {i}. \033[1m{title}\033[0m")
            print(f"     {source} {bias_color}[{bias}]\033[0m")
            if url:
                print(f"     \033[0;36m{url[:60]}...\033[0m" if len(url) > 60 else f"     \033[0;36m{url}\033[0m")
            print()
except Exception as e:
    print(f"Error: {e}")
EOF
}

# show_all_headlines() - Display all headlines grouped by category
show_all_headlines() {
    echo ""
    echo -e "${BOLD}${MAGENTA}═══ ALL HEADLINES ═══${NC}"
    echo ""

    python3 << EOF
import json
try:
    with open('$NEWS_JSON') as f:
        news = json.load(f)

    # Group by category
    categories = {}
    for item in news:
        cat = item.get('category', 'other')
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(item)

    cat_names = {
        'local': 'LOCAL (Albany, GA)',
        'state': 'GEORGIA STATE',
        'sports': 'COLLEGE FOOTBALL',
        'politics': 'POLITICS (Major)',
        'tech': 'TECH & WORLD',
        'nature': 'NATURE & OUTDOORS',
        'fishing': 'FLY FISHING & HUNTING',
        'conservation': 'CONSERVATION'
    }

    for cat in ['local', 'state', 'sports', 'nature', 'fishing', 'conservation', 'tech', 'politics']:
        if cat in categories and categories[cat]:
            print(f"\033[1;33m{cat_names.get(cat, cat.upper())}\033[0m")
            for item in categories[cat][:4]:
                title = item.get('title', '')[:70]
                source = item.get('source', '')
                print(f"  • {title}")
                print(f"    \033[0;90m{source}\033[0m")
            print()

except Exception as e:
    print(f"Error: {e}")
EOF
}

# show_summary() - Display count of stories per category
show_summary() {
    echo -e "${BOLD}News Summary:${NC}"
    if [ -f "$NEWS_JSON" ]; then
        python3 -c "
import json
with open('$NEWS_JSON') as f:
    d = json.load(f)
cats = {}
for item in d:
    c = item.get('category', 'other')
    cats[c] = cats.get(c, 0) + 1
print(f'  Total stories: {len(d)}')
for k, v in sorted(cats.items()):
    print(f'    {k}: {v}')
" 2>/dev/null
    else
        echo "  No news data yet."
    fi
    echo ""
}

# open_claude_chat() - Launch Claude CLI for news discussion
open_claude_chat() {
    echo ""
    echo -e "${CYAN}Starting Claude for news discussion...${NC}"
    echo ""
    echo "You can ask Claude about:"
    echo "  - Summarize today's news"
    echo "  - What's happening in Albany?"
    echo "  - Any big college football news?"
    echo "  - What's new in conservation?"
    echo ""
    echo -e "${YELLOW}Press Enter to open Claude, or 'q' to go back...${NC}"
    read -r response
    if [ "$response" != "q" ]; then
        claude
    fi
}

#===============================================================================
# Main Interactive Loop
#===============================================================================
show_summary

while true; do
    show_menu
    read -p "Choose option: " choice

    case $choice in
        1) refresh_news ;;
        2) show_summary ;;
        3) show_category "local" "LOCAL NEWS - Albany, GA" ;;
        4) show_category "state" "GEORGIA STATE NEWS" ;;
        5) show_category "sports" "COLLEGE FOOTBALL" ;;
        6) show_category "nature" "NATURE & OUTDOORS" ;;
        7) show_category "fishing" "FLY FISHING & HUNTING" ;;
        8) show_category "tech" "TECH & WORLD NEWS" ;;
        9) show_all_headlines ;;
        0) echo "Goodbye!"; exit 0 ;;
        c|C) open_claude_chat ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
    clear
    echo -e "${CYAN}${BOLD}NEWS DESK - COMMAND CENTER${NC}"
    echo ""
done

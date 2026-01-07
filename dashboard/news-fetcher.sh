#!/bin/bash
#===============================================================================
# news-fetcher.sh - News Aggregator for Command Center
#===============================================================================
# PURPOSE:
#   Fetches news from multiple sources and aggregates them into a single JSON
#   file for the Command Center dashboard. Includes bias scoring for sources.
#
# USAGE:
#   ~/system-monitor/dashboard/news-fetcher.sh
#
# OUTPUT:
#   ~/system-monitor/dashboard/news-cache/news.json
#   ~/system-monitor/dashboard/news-cache/meta.json (timestamp)
#
# SOURCES:
#   - Hacker News (Firebase API) - Tech news
#   - Major Networks: CBS, NBC, Fox News
#   - Drudge Report - News aggregator
#   - Alternative: Daily Wire, Breitbart, NPR
#   - Google News RSS - Regional/topical news
#
# CATEGORIES:
#   breaking     - Top stories from major networks
#   local        - Albany, Georgia news
#   state        - Georgia state news
#   sports       - College football (CFP, UGA)
#   politics     - Major political news
#   tech         - Hacker News top stories
#   nature       - Outdoor adventure, national parks
#   fishing      - Fly fishing, duck hunting
#   conservation - Water policy, wildlife conservation
#
# BIAS SCORING:
#   Scale: -20 (far left) to +20 (far right), 0 = center
#   Labels: Left, Center-Left, Center, Center-Right, Right
#
#   CBS News:     -10 (Center-Left)
#   NBC News:     -12 (Center-Left)
#   NPR:          -8  (Center-Left)
#   Fox News:     +15 (Right)
#   Drudge:       +10 (Center-Right)
#   Daily Wire:   +18 (Right)
#   Breitbart:    +20 (Right)
#   Newsmax:      +18 (Right)
#===============================================================================

#-------------------------------------------------------------------------------
# Load Configuration
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Fallback defaults
    NEWS_CACHE_DIR="$HOME/system-monitor/dashboard/news-cache"
    LOCAL_NEWS_SEARCH="Albany+Georgia"
    ENABLE_NEWS_FETCHING=1
fi

NEWS_DIR="${NEWS_CACHE_DIR:-$HOME/system-monitor/dashboard/news-cache}"
NEWS_JSON="$NEWS_DIR/news.json"
mkdir -p "$NEWS_DIR"

# Check if news fetching is enabled
if [ "${ENABLE_NEWS_FETCHING:-1}" -ne 1 ]; then
    echo "News fetching disabled in config. Exiting."
    exit 0
fi

# Temp file for collecting items before JSON conversion
TEMP_FILE=$(mktemp)

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------

# add_item() - Add a news item to the temp file
# Args: source, title, url, bias_score, bias_label, category
add_item() {
    local source="$1"
    local title="$2"
    local url="$3"
    local bias="$4"
    local bias_label="$5"
    local category="$6"

    title=$(echo "$title" | sed 's/"/\\"/g; s/\t/ /g' | tr -d '\n\r' | head -c 200)
    url=$(echo "$url" | tr -d '\n\r')

    if [ -n "$title" ] && [ ${#title} -gt 5 ]; then
        local timestamp=$(date +%s)
        echo "{\"source\":\"$source\",\"title\":\"$title\",\"url\":\"$url\",\"bias\":$bias,\"bias_label\":\"$bias_label\",\"category\":\"$category\",\"timestamp\":$timestamp}" >> "$TEMP_FILE"
    fi
}

#===============================================================================
# News Source Fetching
#===============================================================================
echo "Fetching news... $(date)"

# ============================================
# TECH & WORLD NEWS
# Source: Hacker News Firebase API (most reliable, no auth needed)
# ============================================
echo "  [TECH] Hacker News..."
HN_IDS=$(curl -s --max-time 10 "https://hacker-news.firebaseio.com/v0/topstories.json" 2>/dev/null | grep -oP '\d+' | head -12)
for id in $HN_IDS; do
    DATA=$(curl -s --max-time 5 "https://hacker-news.firebaseio.com/v0/item/$id.json" 2>/dev/null)
    TITLE=$(echo "$DATA" | grep -oP '"title"\s*:\s*"\K[^"]+' | head -1)
    URL=$(echo "$DATA" | grep -oP '"url"\s*:\s*"\K[^"]+' | head -1)
    [ -z "$URL" ] && URL="https://news.ycombinator.com/item?id=$id"
    add_item "Hacker News" "$TITLE" "$URL" 5 "Center" "tech"
done

# ============================================
# MAJOR NETWORKS - THE BIG THREE + MORE
# ============================================

# CBS News (Center-Left)
echo "  [BREAKING] CBS News..."
curl -s --max-time 10 -A "Mozilla/5.0" "https://www.cbsnews.com/latest/rss/main" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "CBS News" | head -5 | while read title; do
    add_item "CBS News" "$title" "https://www.cbsnews.com" -10 "Center-Left" "breaking"
done

# NBC News (Center-Left)
echo "  [BREAKING] NBC News..."
curl -s --max-time 10 -A "Mozilla/5.0" "https://feeds.nbcnews.com/nbcnews/public/news" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "NBC News" | head -5 | while read title; do
    add_item "NBC News" "$title" "https://www.nbcnews.com" -12 "Center-Left" "breaking"
done

# Fox News (Right)
echo "  [BREAKING] Fox News..."
curl -s --max-time 10 -A "Mozilla/5.0" "https://moxie.foxnews.com/google-publisher/latest.xml" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Fox News" | head -5 | while read title; do
    add_item "Fox News" "$title" "https://www.foxnews.com" 15 "Right" "breaking"
done

# ============================================
# DRUDGE REPORT (Aggregator, Center-Right)
# ============================================
echo "  [BREAKING] Drudge Report headlines..."
curl -s --max-time 10 -A "Mozilla/5.0" "https://www.drudgereport.com/" 2>/dev/null | \
    grep -oP 'href="[^"]+">([A-Z][A-Z\s]+)</a>' | \
    sed 's/href="[^"]*">//g; s/<\/a>//g' | head -8 | while read title; do
    # Only add if it looks like a headline (all caps, decent length)
    if [ ${#title} -gt 10 ]; then
        add_item "Drudge Report" "$title" "https://www.drudgereport.com" 10 "Center-Right" "breaking"
    fi
done

# ============================================
# ALTERNATIVE / RIGHT-LEANING SOURCES
# ============================================

# Daily Wire (Right)
echo "  [ALT] Daily Wire..."
curl -s --max-time 10 -A "Mozilla/5.0" "https://www.dailywire.com/feeds/rss.xml" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Daily Wire" | head -5 | while read title; do
    add_item "Daily Wire" "$title" "https://www.dailywire.com" 18 "Right" "politics"
done

# Breitbart (Right)
echo "  [ALT] Breitbart..."
curl -s --max-time 10 -A "Mozilla/5.0" "https://feeds.feedburner.com/breitbart" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Breitbart" | head -4 | while read title; do
    add_item "Breitbart" "$title" "https://www.breitbart.com" 20 "Right" "politics"
done

# ============================================
# LEFT-LEANING SOURCES (for balance)
# ============================================

# NPR (Center-Left)
echo "  [ALT] NPR News..."
curl -s --max-time 10 -A "Mozilla/5.0" "https://feeds.npr.org/1001/rss.xml" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "NPR" | head -5 | while read title; do
    add_item "NPR" "$title" "https://www.npr.org" -8 "Center-Left" "breaking"
done

# ============================================
# LOCAL NEWS (via Google News)
# Uses LOCAL_NEWS_SEARCH from config (default: Albany+Georgia)
# ============================================
echo "  [LOCAL] ${LOCAL_NEWS_SEARCH/+/ } News..."
curl -s --max-time 15 -A "Mozilla/5.0" "https://news.google.com/rss/search?q=${LOCAL_NEWS_SEARCH}&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -5 | while read title; do
    add_item "Google News" "$title" "https://news.google.com/search?q=${LOCAL_NEWS_SEARCH}" 0 "Center" "local"
done

# ============================================
# STATE NEWS - Georgia
# ============================================
echo "  [STATE] Georgia News..."
curl -s --max-time 15 -A "Mozilla/5.0" "https://news.google.com/rss/search?q=Georgia+state+news&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -5 | while read title; do
    add_item "Google News" "$title" "https://news.google.com/search?q=Georgia" -5 "Center" "state"
done

# ============================================
# SPORTS - College Football
# ============================================
echo "  [SPORTS] College Football..."
curl -s --max-time 15 -A "Mozilla/5.0" "https://news.google.com/rss/search?q=college+football+CFP+playoff&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -6 | while read title; do
    add_item "CFB News" "$title" "https://news.google.com/search?q=college+football" 5 "Center" "sports"
done

echo "  [SPORTS] Georgia Bulldogs..."
curl -s --max-time 15 -A "Mozilla/5.0" "https://news.google.com/rss/search?q=Georgia+Bulldogs+football&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -4 | while read title; do
    add_item "UGA News" "$title" "https://news.google.com/search?q=Georgia+Bulldogs" 5 "Center" "sports"
done

# ============================================
# POLITICS - Major Only (Wars, Elections)
# ============================================
echo "  [POLITICS] Major political news..."
curl -s --max-time 15 "https://news.google.com/rss/search?q=presidential+election+OR+war+OR+congress+major&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | \
    grep -iE "president|election|war|congress|senate|supreme|military|nuclear" | head -4 | while read title; do
    add_item "Politics" "$title" "https://news.google.com" 0 "Center" "politics"
done

# ============================================
# NATURE & OUTDOORS
# ============================================
echo "  [NATURE] Outdoor news..."
curl -s --max-time 15 "https://news.google.com/rss/search?q=outdoor+adventure+hiking+camping&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -5 | while read title; do
    add_item "Outdoor News" "$title" "https://news.google.com/search?q=outdoor" 0 "Center" "nature"
done

echo "  [NATURE] National Parks..."
curl -s --max-time 15 "https://news.google.com/rss/search?q=national+parks+wildlife&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -3 | while read title; do
    add_item "Parks News" "$title" "https://news.google.com" 0 "Center" "nature"
done

# ============================================
# FLY FISHING & HUNTING
# ============================================
echo "  [FISHING] Fly fishing news..."
curl -s --max-time 15 "https://news.google.com/rss/search?q=fly+fishing+trout&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -4 | while read title; do
    add_item "Fishing News" "$title" "https://news.google.com/search?q=fly+fishing" 10 "Center" "fishing"
done

echo "  [HUNTING] Duck hunting..."
curl -s --max-time 15 "https://news.google.com/rss/search?q=duck+hunting+waterfowl&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -4 | while read title; do
    add_item "Hunting News" "$title" "https://news.google.com/search?q=duck+hunting" 15 "Center-Right" "fishing"
done

# ============================================
# WATER & CONSERVATION
# ============================================
echo "  [CONSERVATION] Water policy..."
curl -s --max-time 15 "https://news.google.com/rss/search?q=water+policy+conservation+rivers&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -4 | while read title; do
    add_item "Conservation" "$title" "https://news.google.com/search?q=water+conservation" -10 "Center" "conservation"
done

echo "  [CONSERVATION] Wildlife..."
curl -s --max-time 15 "https://news.google.com/rss/search?q=wildlife+conservation+habitat&hl=en-US&gl=US&ceid=US:en" 2>/dev/null | \
    grep -oP '<title>\K[^<]+' | grep -v "Google News" | head -3 | while read title; do
    add_item "Wildlife" "$title" "https://news.google.com" -5 "Center" "conservation"
done

#===============================================================================
# JSON Finalization
# Convert NDJSON temp file to proper JSON array using Python
#===============================================================================
echo ""
echo "Building news feed..."

# Convert NDJSON (one JSON object per line) to a proper JSON array
python3 << 'PYEOF'
import json
import sys

items = []
try:
    with open("$TEMP_FILE".replace("$TEMP_FILE", sys.argv[1] if len(sys.argv) > 1 else "/tmp/news_temp"), 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    item = json.loads(line)
                    items.append(item)
                except:
                    pass

    with open("$NEWS_JSON".replace("$NEWS_JSON", sys.argv[2] if len(sys.argv) > 2 else "news.json"), 'w') as f:
        json.dump(items, f)

    print(f"Saved {len(items)} news items")

    # Count by category
    cats = {}
    for item in items:
        c = item.get('category', 'other')
        cats[c] = cats.get(c, 0) + 1

    print("\nCategories:")
    for k, v in sorted(cats.items()):
        print(f"  {k}: {v}")
    print(f"  TOTAL: {len(items)}")

except Exception as e:
    print(f"Error: {e}")
    # Fallback - just write empty array
    with open("$NEWS_JSON".replace("$NEWS_JSON", sys.argv[2] if len(sys.argv) > 2 else "news.json"), 'w') as f:
        json.dump([], f)
PYEOF

# Run python with actual paths
python3 -c "
import json
items = []
with open('$TEMP_FILE', 'r') as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                item = json.loads(line)
                items.append(item)
            except:
                pass
with open('$NEWS_JSON', 'w') as f:
    json.dump(items, f, indent=None)
print(f'Saved {len(items)} news items')
cats = {}
for item in items:
    c = item.get('category', 'other')
    cats[c] = cats.get(c, 0) + 1
print('Categories:')
for k, v in sorted(cats.items()):
    print(f'  {k}: {v}')
print(f'  TOTAL: {len(items)}')
"

# Cleanup temp file
rm -f "$TEMP_FILE"

# Write metadata (for cache freshness checking)
echo "{\"updated\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}" > "$NEWS_DIR/meta.json"

echo ""
echo "News fetch complete: $(date)"

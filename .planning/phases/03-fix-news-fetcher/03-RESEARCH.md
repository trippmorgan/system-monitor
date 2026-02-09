# Phase 3: Fix News Fetcher - Research

**Researched:** 2026-02-09
**Domain:** RSS feed parsing, Python XML, local news aggregation
**Confidence:** HIGH

## Summary

The current `news-fetcher.sh` already uses Python 3 with `xml.etree.ElementTree` (not grep-based parsing as the roadmap assumed). It is a short, well-structured 83-line script with an embedded Python block that fetches 6 RSS feeds and writes JSON. The script mostly works -- WTXL, GA Wildlife, and BBC feeds produce valid items. However, two of the three local sources are broken: Albany Herald returns a Cloudflare 403 on the current URL, and WALB's category-filtered URL returns 0 items (empty channel). Additionally, the JSON file is written directly (not atomically), and there is no Hacker News feed despite CLAUDE.md listing it as a category.

The good news: Albany Herald has a working WordPress RSS feed at `https://albanyherald.com/feed/` (note: different domain -- no `www`), and WALB's general feed at `https://www.walb.com/arc/outboundfeeds/rss/?outputType=xml` returns 20 items. Google News RSS for "Albany GA" returns 100 items as a reliable fallback. All feeds parse correctly with Python's `xml.etree.ElementTree`, including CDATA-wrapped titles (WALB uses CDATA; Albany Herald uses CDATA for creator names).

**Primary recommendation:** Fix the three broken feed URLs (Albany Herald, WALB local, add Google News fallback), add atomic writes via `.tmp` + `mv`, add Hacker News feed, and clean up CDATA/HTML entities in titles with `html.unescape()` + regex tag stripping.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Python 3 `xml.etree.ElementTree` | stdlib (Python 3.14.2) | RSS/XML parsing | Already in use, handles CDATA, no deps |
| Python 3 `html` | stdlib | Entity unescaping (`&amp;` -> `&`) | Handles all HTML entities including named ones |
| Python 3 `json` | stdlib | JSON output | Already in use |
| Python 3 `urllib.request` | stdlib | HTTP fetching | Already in use, no deps |
| Python 3 `re` | stdlib | Strip HTML tags from CDATA content | Lightweight, no deps |
| Python 3 `ssl` | stdlib | SSL context for old feeds | Already in use |
| Python 3 `tempfile` | stdlib | Atomic write via NamedTemporaryFile | Safer than manual `.tmp` naming |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `xml.etree.ElementTree` | `feedparser` library | Handles more edge cases but requires pip install -- violates "no external dependencies" rule |
| `urllib.request` | `requests` library | Nicer API but requires pip install |
| `tempfile` + `os.rename` | Manual `.tmp` + `mv` | tempfile is slightly safer (unique names) but either approach works |

**Installation:** No installation needed -- all stdlib.

## Architecture Patterns

### Current Project Structure (news-fetcher)
```
dashboard/
├── news-fetcher.sh        # Shell wrapper calling embedded Python
├── news-cache/
│   └── news.json          # Output consumed by index.html
├── index.html             # Dashboard that reads news.json
├── launch.sh              # Starts refresh loop (news every 5 min)
└── system-stats.sh        # Separate stats pipeline
```

### Pattern: Embedded Python in Shell Script
**What:** The current news-fetcher.sh embeds Python code inside a bash `python3 -c "..."` block. This is the established pattern in this project.
**When to use:** Keep this pattern. It works, the user prefers pragmatic solutions, and switching to a standalone `.py` file would change the launch/refresh infrastructure.
**Constraints:**
- Python code uses `$OUTPUT_FILE` from the shell environment (string substitution before Python runs)
- All Python must be in a single `-c` argument (no imports from local modules)
- Quoting requires care: the Python string is inside double quotes in bash

### Pattern: Feed Config as Data
**What:** Feed URLs, categories, and source names defined as a list of dicts at the top of the Python block.
**Why:** Easy to add/remove/modify feeds without touching parsing logic.
**Current code already does this correctly.**

### Pattern: Atomic File Writes
**What:** Write to a temporary file, then `os.rename()` to the final path. This ensures the dashboard never reads a half-written JSON file.
**Implementation:**
```python
import tempfile, os, json

# Write to temp file in same directory (same filesystem = atomic rename)
tmp_fd, tmp_path = tempfile.mkstemp(dir=cache_dir, suffix='.json')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        json.dump(all_news, f, indent=2)
    os.rename(tmp_path, output_file)
except:
    os.unlink(tmp_path)
    raise
```

### Anti-Patterns to Avoid
- **Writing JSON directly to final path:** Dashboard JS may `fetch()` a half-written file and get a JSON parse error. Always use atomic write.
- **Catching all exceptions silently:** The current `except Exception as e: print(...)` pattern is fine for individual feeds (one bad feed should not kill the whole run), but the final JSON write should NOT be silently swallowed.
- **Hardcoding the wrong Albany Herald URL:** The `www.albanyherald.com/search/?f=rss` URL is Cloudflare-blocked. Must use `albanyherald.com/feed/`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTML entity decoding | Manual `replace('&amp;','&')` chains | `html.unescape()` | Handles all 2,231 named HTML entities plus numeric refs |
| XML parsing | grep/sed/awk on XML | `xml.etree.ElementTree` | Already in use; handles namespaces, CDATA, encoding |
| HTML tag stripping | Complex regex | `re.sub(r'<[^>]+>', '', text)` then `html.unescape()` | Simple, handles CDATA content that contains HTML |
| Atomic file writes | Shell `echo > file` | Python `tempfile.mkstemp` + `os.rename` | Guaranteed atomic on same filesystem |
| RSS date parsing | Manual string parsing | Can ignore -- dashboard uses `time.time()` for timestamp | Current approach is fine; pubDate is optional enrichment |

**Key insight:** The project rule is "no external dependencies." All solutions must use Python stdlib only.

## Common Pitfalls

### Pitfall 1: Albany Herald Cloudflare Block
**What goes wrong:** The URL `https://www.albanyherald.com/search/?f=rss&t=article&c=news/local&l=50&s=start_time&sd=desc` returns HTTP 403 with a Cloudflare JavaScript challenge. No amount of User-Agent spoofing fixes this.
**Why it happens:** Albany Herald moved to a WordPress site at `albanyherald.com` (no www) with a standard WordPress RSS feed, and their old Lee Enterprises CMS search endpoint is now Cloudflare-protected.
**How to avoid:** Use `https://albanyherald.com/feed/` instead. Verified working: returns 10 items with real article URLs.
**Warning signs:** HTTP 403, response body contains "Just a moment..." or Cloudflare challenge HTML.

### Pitfall 2: WALB Category-Filtered RSS Returns Empty
**What goes wrong:** The URL `https://www.walb.com/arc/outboundfeeds/rss/category/news/local/?outputType=xml` returns HTTP 200 with valid RSS XML, but the `<channel>` contains zero `<item>` elements.
**Why it happens:** WALB's Arc Publishing CMS does not populate the category-filtered feed endpoint. The general feed works fine.
**How to avoid:** Use `https://www.walb.com/arc/outboundfeeds/rss/?outputType=xml` (general feed, 20 items). WALB content is already Albany/South Georgia focused.
**Warning signs:** Feed parses successfully but produces 0 items -- easy to miss because there is no error.

### Pitfall 3: CDATA-Wrapped Titles
**What goes wrong:** WALB wraps `<title>` in `<![CDATA[...]]>`. Albany Herald wraps `<dc:creator>` in CDATA.
**Why it happens:** Standard practice in RSS feeds to avoid XML escaping issues.
**How to avoid:** Python's `xml.etree.ElementTree` handles CDATA transparently -- `element.text` returns the unwrapped content. No special handling needed.
**Verified:** Tested with actual WALB feed. `item.find('title').text` returns clean text even from CDATA-wrapped elements.

### Pitfall 4: HTML Tags Inside Titles
**What goes wrong:** Some CDATA-wrapped titles may contain HTML tags (e.g., `<b>`, `<a>`). These would appear as raw HTML in the dashboard.
**Why it happens:** CDATA allows any content including HTML markup.
**How to avoid:** Strip HTML tags with `re.sub(r'<[^>]+>', '', text)` then `html.unescape()` on all title text.
**Warning signs:** Titles containing `<` characters in the JSON output.

### Pitfall 5: Google News RSS Link Redirects
**What goes wrong:** Google News RSS `<link>` values are not direct article URLs. They are `https://news.google.com/rss/articles/CBMI...` redirect URLs.
**Why it happens:** Google News wraps all article links through their redirect service for tracking.
**How to avoid:** These links work fine when clicked in a browser -- Google's JavaScript redirects to the actual article. For a dashboard where links open in a browser tab, this is acceptable. No need to resolve the redirect server-side.
**Warning signs:** Links starting with `https://news.google.com/rss/articles/` -- these work in browsers.

### Pitfall 6: Atom Feed Link Extraction
**What goes wrong:** The current code does `item.find('link').text` which returns `None` for Atom feeds because Atom `<link>` uses an `href` attribute, not text content.
**Why it happens:** RSS uses `<link>URL</link>` but Atom uses `<link href="URL" rel="alternate"/>`.
**How to avoid:** Check both: `link.text or link.get('href', '')`.
**Verified:** Tested with Python ET. Atom `link.text` is `None`; `link.get('href')` returns the URL.
**Current impact:** LOW -- none of the current feeds use Atom format. But the code already searches for Atom entries, so it should handle Atom links correctly.

### Pitfall 7: Non-Atomic JSON Writes
**What goes wrong:** The dashboard fetches `news.json` every 30 seconds. If `news-fetcher.sh` is mid-write, the dashboard gets truncated/invalid JSON and the `catch(e)` silently shows "News Offline."
**Why it happens:** `json.dump()` directly to the output file is not atomic.
**How to avoid:** Write to temp file, then `os.rename()`. Both files must be on the same filesystem for `rename()` to be atomic.

### Pitfall 8: Missing Hacker News Feed
**What goes wrong:** CLAUDE.md lists "tech - Hacker News top stories" as a news category, and the dashboard's `categories` object includes `tech` implicitly (items without a matching category fall through). But the current `news-fetcher.sh` has no Hacker News feed.
**Impact:** The `tech` category is empty. The `hnrss.org/frontpage` RSS feed works and returns 20 items.
**How to avoid:** Add `{'url': 'https://hnrss.org/frontpage', 'category': 'tech', 'source': 'Hacker News'}` to the feeds list.

## Code Examples

Verified patterns from testing against live feeds:

### Feed Configuration (Updated URLs)
```python
# Source: Live-verified 2026-02-09
feeds = [
    # LOCAL ALBANY
    {'url': 'https://albanyherald.com/feed/', 'category': 'local', 'source': 'Albany Herald', 'bias_label': 'CENTER'},
    {'url': 'https://www.walb.com/arc/outboundfeeds/rss/?outputType=xml', 'category': 'local', 'source': 'WALB News 10', 'bias_label': 'CENTER'},
    {'url': 'https://www.wtxl.com/news/local-news.rss', 'category': 'local', 'source': 'WTXL ABC 27', 'bias_label': 'CENTER'},
    # FALLBACK: Google News for Albany GA (backup if direct feeds fail)
    {'url': 'https://news.google.com/rss/search?q=%22Albany+GA%22&hl=en-US&gl=US&ceid=US:en', 'category': 'local', 'source': 'Google News (Albany)', 'bias_label': 'MIXED'},

    # TECH
    {'url': 'https://hnrss.org/frontpage', 'category': 'tech', 'source': 'Hacker News', 'bias_label': 'NEUTRAL'},

    # OUTDOORS / NATURE
    {'url': 'https://georgiawildlife.blog/feed/', 'category': 'nature', 'source': 'GA Wildlife', 'bias_label': 'NEUTRAL'},

    # SPORTS
    {'url': 'https://www.wtxl.com/sports.rss', 'category': 'sports', 'source': 'WTXL Sports', 'bias_label': 'CENTER'},

    # BREAKING / WORLD
    {'url': 'http://feeds.bbci.co.uk/news/world/rss.xml', 'category': 'breaking', 'source': 'BBC World', 'bias_label': 'CENTER-LEFT'},
]
```

### Safe Title Extraction (CDATA + HTML + Entities)
```python
# Source: Tested against WALB, Albany Herald, WTXL live feeds 2026-02-09
import re, html

def clean_title(element):
    """Extract and clean title text from RSS/Atom element."""
    if element is None or element.text is None:
        return 'Untitled'
    text = element.text
    # Strip any HTML tags that leaked through CDATA
    text = re.sub(r'<[^>]+>', '', text)
    # Decode HTML entities (&amp; -> &, etc.)
    text = html.unescape(text)
    # Collapse whitespace
    text = ' '.join(text.split())
    return text.strip() or 'Untitled'
```

### Safe Link Extraction (RSS + Atom)
```python
# Source: Tested with Atom feeds where link.text is None
def get_link(item, ns=None):
    """Extract link from RSS item or Atom entry."""
    link = item.find('link')
    if link is not None:
        # RSS: <link>URL</link>  |  Atom: <link href="URL"/>
        url = link.text or link.get('href', '')
        if url:
            return url.strip()
    # Atom namespace fallback
    if ns:
        for link in item.findall(f'{ns}link'):
            href = link.get('href', '')
            if href and link.get('rel', 'alternate') == 'alternate':
                return href.strip()
    return ''
```

### Atomic JSON Write
```python
# Source: Python stdlib docs for tempfile + os.rename
import tempfile, os, json

def write_json_atomic(data, output_path):
    """Write JSON data atomically using temp file + rename."""
    output_dir = os.path.dirname(output_path)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=output_dir, suffix='.json')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            json.dump(data, f, indent=2)
        os.rename(tmp_path, output_path)
    except:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
```

### Filtering Albany Herald Categories for Local News
```python
# Source: Tested against albanyherald.com/feed/ 2026-02-09
# Albany Herald feed includes all categories (Sports, News, etc.)
# Filter to only 'News' category items for the 'local' category
# Categories are available in <category> elements
def is_local_news(item):
    """Check if Albany Herald item is local news (not sports, etc.)."""
    cats = [c.text for c in item.findall('category') if c.text]
    # If no categories, include it (benefit of doubt)
    if not cats:
        return True
    # Include items categorized as 'News' or 'Local'
    local_keywords = {'news', 'local', 'breaking', 'community'}
    return any(cat.lower() in local_keywords for cat in cats)
```

## Dashboard Consumption Analysis

### How index.html Reads news.json
```javascript
// Source: dashboard/index.html lines 436-456
// Fetches: news-cache/news.json (relative path, cache-busted)
const newsRes = await fetch('news-cache/news.json?' + Date.now());
let allNews = await newsRes.json();

// Sorts by timestamp descending
allNews.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));

// Groups into 4 categories
const categories = { local: [], breaking: [], sports: [], nature: [] };
allNews.forEach(item => {
    const cat = item.category || 'tech';
    if (categories[cat]) categories[cat].push(item);
});
```

### Required JSON Fields Per Item
| Field | Type | Used In | Required |
|-------|------|---------|----------|
| `title` | string | `renderArcadeList` -- displayed as link text | YES |
| `url` | string | `renderArcadeList` -- `<a href="${item.url}">` | YES |
| `source` | string | `renderArcadeList` -- shown in `.news-meta` | YES |
| `category` | string | Category grouping: `local`, `breaking`, `sports`, `nature` | YES |
| `timestamp` | number | Sort order (descending) | YES |
| `bias` | number | Displayed as `SCORE: ${Math.abs(item.bias)}` | YES (can be 0) |
| `bias_label` | string | Not currently displayed in dashboard | YES (for NEWS-02 requirement) |

### Category Mapping
| Category | Dashboard Element | Panel Title |
|----------|-------------------|-------------|
| `local` | `#news-local` | "LEVEL 1: LOCAL" |
| `breaking` | `#news-breaking` | "BOSS BATTLE: BREAKING" |
| `sports` | `#news-sports` | "BONUS STAGE: SPORTS" |
| `nature` | `#news-nature` | "LEVEL 2: OUTDOORS" |
| `tech` | NOT RENDERED -- no `#news-tech` element exists | N/A |

**Important:** The dashboard has no panel for `tech` category items. Items with `category: 'tech'` are collected by the code but never rendered because `categories` object only has 4 keys and `tech` is not one of them. Adding Hacker News will require either adding a `tech` panel to the HTML or mapping it to an existing category. This is a Phase 4 concern or could be noted as a follow-up.

### XSS Consideration
The dashboard uses `innerHTML` with template literals to render news items (line 467):
```javascript
el.innerHTML = items.slice(0, 5).map(item => `
    <a href="${item.url || '#'}" target="_blank" class="news-link">
        <i class="nes-icon coin is-small"></i> ${item.title}
    </a>
`).join('');
```
This means malicious content in `title` or `url` fields could inject HTML. The news-fetcher should sanitize titles (strip HTML tags) and validate URLs (must start with `http://` or `https://`).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| grep/sed RSS parsing (roadmap assumption) | Python xml.etree.ElementTree | Already current | No migration needed |
| `www.albanyherald.com/search/?f=rss` | `albanyherald.com/feed/` (WordPress) | Albany Herald migrated to WordPress | Old URL Cloudflare-blocked |
| WALB category-filtered RSS | WALB general RSS feed | Category endpoint broken (returns 0 items) | Use general feed instead |

**Key correction:** The roadmap says "Replace grep-based RSS parsing with Python XML." The current code already uses Python XML. The real issues are:
1. Two of three local feed URLs are broken
2. No atomic writes
3. No Hacker News feed
4. Missing Google News fallback

## RSS Feed Verification Results

| Feed | URL | Status | Items | Article URLs |
|------|-----|--------|-------|-------------|
| Albany Herald | `albanyherald.com/feed/` | 200 OK | 10 | Real article links (verified) |
| Albany Herald (old) | `www.albanyherald.com/search/?f=rss...` | 403 Cloudflare | 0 | BROKEN |
| WALB (general) | `walb.com/arc/outboundfeeds/rss/?outputType=xml` | 200 OK | 20 | Real article links (verified) |
| WALB (local category) | `walb.com/.../category/news/local/...` | 200 OK | 0 | EMPTY |
| WTXL Local | `wtxl.com/news/local-news.rss` | 200 OK | 10+ | Real article links (verified) |
| WTXL Sports | `wtxl.com/sports.rss` | 200 OK | Yes | Real article links |
| GA Wildlife | `georgiawildlife.blog/feed/` | 200 OK | Yes | Real article links |
| BBC World | `feeds.bbci.co.uk/news/world/rss.xml` | 302->200 | Yes | Real article links |
| Hacker News | `hnrss.org/frontpage` | 200 OK | 20 | Real article links (verified) |
| Google News (Albany) | `news.google.com/rss/search?q=...` | 200 OK | 100 | Redirect links (work in browser) |

## Open Questions

1. **Tech category panel missing from dashboard**
   - What we know: The dashboard HTML has no `#news-tech` element. Adding Hacker News to the feed will produce items that are never displayed.
   - What's unclear: Should we add a tech panel to the HTML, or map HN items to `breaking`?
   - Recommendation: Add HN feed with `category: 'tech'` anyway (requirement NEWS-07 says "Hacker News... categories continue working"). The dashboard HTML update can be a separate task in this plan or deferred to Phase 4. The data should be correct regardless.

2. **Albany Herald feed includes non-local categories**
   - What we know: The `albanyherald.com/feed/` returns a mix of Sports, News, etc. The feed has `<category>` elements per item.
   - What's unclear: Should we filter to only "News" category, or include everything as "local"?
   - Recommendation: Filter Albany Herald items to those with "News" or "Local" in their categories. Sports items from Herald would duplicate WTXL Sports.

3. **Google News fallback strategy**
   - What we know: Google News RSS for "Albany GA" returns 100 items from mixed sources including WALB, Herald, obituaries.
   - What's unclear: Should Google News be always-on or only used when direct feeds fail?
   - Recommendation: Include Google News as a separate feed with `max_items=3` to supplement direct feeds. Filter out obituaries by title keyword matching if needed.

4. **Bias labels**
   - What we know: Current code sets all items to `bias: 0, bias_label: 'NEUTRAL'`. Requirement NEWS-02 says local items must include bias labels.
   - What's unclear: What bias values to assign?
   - Recommendation: Set bias labels per source in the feed config (shown in code examples above). Keep `bias: 0` (numeric) for all local sources since they are centrist local news. Use string labels like 'CENTER', 'CENTER-LEFT' etc.

## Sources

### Primary (HIGH confidence)
- Albany Herald RSS feed at `https://albanyherald.com/feed/` -- verified live 2026-02-09, returns 10 items with real article URLs
- WALB News RSS feed at `https://www.walb.com/arc/outboundfeeds/rss/?outputType=xml` -- verified live 2026-02-09, returns 20 items
- WTXL RSS feed at `https://www.wtxl.com/news/local-news.rss` -- verified live 2026-02-09, returns 10+ items with CDATA content
- Python 3.14.2 stdlib `xml.etree.ElementTree` -- tested CDATA handling against live feeds
- Google News RSS at `https://news.google.com/rss/search?q=%22Albany+GA%22&hl=en-US&gl=US&ceid=US:en` -- verified live, 100 items
- Hacker News RSS at `https://hnrss.org/frontpage` -- verified live, 20 items
- Current `dashboard/news-fetcher.sh` -- read and analyzed in full
- Current `dashboard/index.html` -- read and analyzed news consumption patterns

### Secondary (MEDIUM confidence)
- Google News redirect links work in browsers (tested with curl -L, returns 200 at redirect target)
- Albany Herald categories can be used to filter local vs sports items (tested with live feed)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all stdlib, already in use, verified against live feeds
- Architecture: HIGH - maintaining existing embedded-Python pattern, adding atomic writes
- Pitfalls: HIGH - all feed URLs verified with live curl/Python tests
- Dashboard consumption: HIGH - read and analyzed actual index.html code

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (RSS feed URLs may change; re-verify if feeds stop working)

# Feature Landscape

**Domain:** Local news dashboard with chat integration (personal workstation)
**Researched:** 2026-02-08
**Mode:** Features dimension for milestone work

## Table Stakes

Features users expect. Missing = product feels incomplete.

### Local News Fetching (RSS Pipeline)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Direct RSS fetch from Albany Herald | Currently using Google News proxy search which returns generic results, not actual local journalism | Low | Albany Herald (Lee Enterprises) likely publishes RSS at `/rss` or `/search/?f=rss`. Confidence: MEDIUM -- URL needs runtime verification. Fallback to Google News search if RSS unavailable. |
| Direct RSS fetch from WALB News 10 | WALB is the primary NBC affiliate serving Albany, GA -- core local source | Low | Gray Television stations typically publish RSS feeds. Common pattern: `walb.com/news/rss`. Confidence: MEDIUM -- URL structure from training data, needs verification. |
| Direct RSS fetch from WTXL ABC 27 | WTXL covers the Albany/Tallahassee market -- regional coverage gap filler | Low | Scripps station. Pattern: `wtxl.com/news/rss` or similar. Confidence: LOW -- less certain about Scripps feed availability. May need Google News fallback. |
| RSS parse failure fallback to Google News | Any direct RSS feed can go down, change URL, or block scrapers | Low | Already have Google News search for `Albany+Georgia` in `news-fetcher.sh`. Keep as fallback, not primary. |
| Cache freshness indicator | User needs to know if news is current or stale (fetch failed silently) | Low | `meta.json` already has `updated` timestamp. Dashboard should display "Last updated X minutes ago" and flag stale data (>10 min). |
| News item deduplication | Multiple sources report same story -- feed becomes repetitive | Medium | Compare normalized titles (lowercase, strip punctuation) across sources. Keep first occurrence. Without this, the same AP wire story appears 3 times from 3 local sources. |
| Proper RSS XML parsing | Current grep-based parsing (`grep -oP '<title>\K[^<]+'`) breaks on CDATA, encoded entities, multi-line titles | Medium | Use Python `xml.etree.ElementTree` or `feedparser` library. The existing pattern of calling Python for JSON finalization means Python is already available. `feedparser` is the standard, but adds a pip dependency. `xml.etree` is stdlib -- use that. |
| Article URL extraction from RSS | Currently many items link to generic homepage (e.g., `https://www.cbsnews.com`) instead of article URL | Low | RSS `<link>` elements contain article URLs. Current grep only extracts `<title>`. Must also extract `<link>` per item. Critical for user experience -- clicking a headline should go to that article. |
| Error logging for failed fetches | News fetcher fails silently. User has no idea which sources are down. | Low | Log failed curl responses (HTTP status, timeout) to a fetch-status file. Dashboard can optionally show source health. |

### Chat Integration (BotSpace to FaceBot)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Poll FaceBot `/api/feed` for messages | BotSpace panel exists but shows hardcoded placeholder messages. Must show real data from FaceBot. | Low | FaceBot API is simple REST. `GET /api/feed` returns JSON array of posts with username, content, created_at. Dashboard already has `loadChat()` function -- just needs correct endpoint URL (localhost:4000). |
| Post messages via `/api/post` | Chat input field and SEND button exist but `postChat()` has `// TODO: Send to backend API` | Low | `POST /api/post` with `{username, content}`. Dashboard sends as "tripp" username. Straightforward fetch call. |
| Connection error state display | FaceBot may not be running when dashboard loads. User needs feedback, not silent failure. | Low | Show "FACEBOT OFFLINE" in red in the BotSpace panel when fetch fails. Retry every 30 seconds. Currently fails silently in catch block. |
| Chat auto-scroll on new messages | Chat panel must scroll to bottom when new messages arrive | Low | Already partially implemented (`feed.scrollTop = feed.scrollHeight`). Needs to work on poll updates, not just optimistic inserts. |
| Chat polling interval | Messages should appear within seconds of being posted by agents | Low | Poll `/api/feed` every 5 seconds. The `setInterval(loadChat, 5000)` line exists but is commented out. Uncomment and point at correct endpoint. |
| Input sanitization (XSS prevention) | Chat input is interpolated directly into innerHTML. If FaceBot returns unsanitized content, XSS is possible. | Low | Use `textContent` instead of `innerHTML` for message content. Or escape HTML entities before insertion. Already flagged in CONCERNS.md. |

### Dashboard Data Pipeline

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Atomic JSON writes | Dashboard reads news.json mid-write = corrupt/empty JSON = "No targets found" | Low | Write to temp file, then `mv` (atomic on same filesystem). Already identified in CONCERNS.md as a known bug. |
| Stats JSON validation | Dashboard JavaScript does basic null checks but crashes on malformed JSON | Low | Add try/catch around JSON.parse. Show "Data unavailable" instead of blank panel. Partially done already. |
| News category routing for new sources | Adding Albany Herald/WALB/WTXL items must route to `local` category | Low | Use existing `add_item` function with `category="local"`. Pattern already established. |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Bias labeling on local sources | Users see left/right lean of local news sources alongside national ones. Unique for a personal dashboard. | Low | Assign bias scores to Albany Herald (local newspaper, typically center), WALB (NBC affiliate, center-left), WTXL (ABC affiliate, center-left). Use existing -20 to +20 scale. |
| System alert routing to BotSpace | System alerts (CPU critical, disk full) appear as chat messages from "SECURITY_BOT" in BotSpace, not just in logs/alerts.log | Medium | When system-monitor detects threshold breach, POST to FaceBot `/api/post` as `security` agent. Bridges the monitoring and chat systems. Makes alerts visible without checking log files. |
| Agent-authored system messages | Agents (System Tech, News Curator) post status updates to BotSpace -- "News fetch complete: 47 items" or "GPU temp elevated: 72C" | Medium | Modify `news-fetcher.sh` and `system-stats.sh` to POST summaries to FaceBot after each run. Gives chat panel a living feed of system activity. |
| News source health dashboard | Show which RSS sources are up/down with last successful fetch time | Medium | Track fetch success/failure per source in a `source-health.json` file. Display as a small status grid. Helps diagnose why categories are empty. |
| Ticker populated from breaking news | Top scrolling ticker currently shows static placeholder text. Should rotate through actual breaking headlines. | Low | Pull first 5 items from `breaking` category and inject into ticker. Already have the ticker HTML structure. |
| Chat message types (visual differentiation) | Alert messages styled differently from normal chat. System messages distinct from user messages. | Low | FaceBot posts have a `type` field (default 'Note'). Use 'Alert' type for system alerts. Dashboard already has `.chat-msg.alert` CSS class. |
| Category-specific news panels for all 8 categories | Dashboard currently only renders 4 categories (local, breaking, sports, nature) but fetcher collects 9 | Medium | Add panels or tabs for state, politics, tech, fishing, conservation. Current 3-column layout limits visible panels. Consider collapsible accordion or tabbed interface within columns. |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Real-time WebSocket chat | Overengineered for a personal dashboard with 1 user. Adds server complexity (need WebSocket server alongside HTTP). | Poll FaceBot REST API every 5 seconds. Latency is imperceptible for personal use. |
| User authentication for dashboard | Personal workstation, localhost-only. Auth adds friction with zero security benefit. | Keep `--bind 127.0.0.1`. If remote access ever needed, use SSH tunnel. |
| Full-text article content scraping | Scraping full articles from news sites violates ToS, requires complex HTML parsing per site, and creates massive storage. | Fetch headlines + links only via RSS. User clicks through to source for full article. |
| News sentiment analysis / AI categorization | Adds Python ML dependencies (NLTK, transformers), slows fetch pipeline, provides marginal value for headline-level content. | Keep manual bias scoring per source. Simple, transparent, and fast. |
| Multi-user chat identities | FaceBot supports multiple agents, but the dashboard is single-user. Building user switching, avatar selection, etc. adds complexity with no user. | Hardcode dashboard posts as "tripp" username. Agents post as their own usernames via backend. |
| Mobile-responsive design overhaul | This is a workstation dashboard, not a mobile app. NES.css pixel aesthetic doesn't translate well to small screens. | Keep desktop-first layout. If mobile viewing needed, use existing responsive grid breakpoint (already has `@media max-width: 900px`). |
| RSS feed management UI (add/remove sources) | Over-engineering for a personal project. Config changes are infrequent. | Edit `news-fetcher.sh` directly or add source URLs to `config.sh`. Shell script is the UI. |
| Chat message persistence/history in dashboard | FaceBot already persists in SQLite. Dashboard doesn't need its own storage. | Always fetch from FaceBot. If FaceBot is down, show "offline" state. Don't cache chat locally. |
| Notification sounds/desktop alerts | Browser notification APIs are unreliable, require permissions, and are annoying for a dashboard that's always open. | Visual indicators only. Red border on critical alerts. Blinking text for breaking news (already have blink animation). |

## Feature Dependencies

```
RSS XML Parsing (proper) --> Local Source Fetching (Herald, WALB, WTXL)
                         --> Article URL Extraction
                         --> News Deduplication

FaceBot Server Running --> Chat Polling (GET /api/feed)
                       --> Chat Posting (POST /api/post)
                       --> System Alert Routing to Chat
                       --> Agent-Authored Messages

Atomic JSON Writes --> Reliable Dashboard Rendering
                   --> Cache Freshness Indicator

Article URL Extraction --> Clickable Headlines (UX)

Chat Polling --> Chat Auto-Scroll
             --> Connection Error State

Local Source Fetching --> Bias Labeling on Local Sources
                     --> News Category Routing

News Category Routing --> Category-Specific Panels (all 8)
                      --> Ticker Population from Breaking News
```

## MVP Recommendation

Prioritize (in order):

1. **FaceBot chat connection** -- Lowest effort, highest visible impact. The UI panel already exists, just needs JavaScript wired to localhost:4000. Uncomment the polling interval, fix the POST handler, add error state display. This is mostly uncommenting code and changing a URL.

2. **Local RSS source addition** -- Add Albany Herald, WALB, WTXL to `news-fetcher.sh` using direct RSS URLs. Even if some feeds are unavailable, the fallback Google News search already works. Use `xml.etree.ElementTree` in the Python finalization step for proper parsing, or at minimum extract both `<title>` and `<link>` from RSS.

3. **Atomic JSON writes** -- Quick fix (write to `.tmp`, then `mv`) that eliminates the known "empty dashboard" bug. 5-minute fix with outsized reliability improvement.

4. **Article URL extraction** -- Fix the pattern where items link to generic homepages. Extract actual article URLs from RSS `<link>` elements. Essential for a news dashboard to be useful.

5. **Ticker population** -- Replace static placeholder text with actual breaking headlines. Low effort, high visual payoff for the arcade theme.

Defer:

- **System alert routing to BotSpace**: Requires FaceBot to be stable first. Do after chat integration is proven working.
- **Agent-authored system messages**: Nice-to-have. Do after core pipeline is solid.
- **All 8 category panels**: Layout change that requires design decisions. Current 4-panel layout works. Expand later.
- **News source health dashboard**: Diagnostic tool. Build only if source reliability becomes a problem.
- **News deduplication**: Wait until local sources are live and confirm duplicate stories are actually a problem.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Chat integration features | HIGH | FaceBot API is visible in source code. Endpoints are clear. Dashboard has placeholder code ready. |
| Local RSS feed URLs | LOW | Could not verify Albany Herald, WALB, or WTXL RSS feed URLs. Training data suggests common patterns but URLs must be tested at runtime. Recommend `curl -I` verification before hardcoding. |
| RSS parsing approach | HIGH | Python `xml.etree.ElementTree` is stdlib and well-documented. Current grep approach is known fragile. |
| Dashboard features | HIGH | Based on direct code analysis of `index.html`. All capabilities and gaps are visible. |
| Feature dependencies | HIGH | Derived from code analysis. FaceBot dependency is explicit. JSON pipeline dependency is structural. |

## Sources

- Direct code analysis: `/home/tripp/Documents/radio-free-albany/dashboard/index.html`
- Direct code analysis: `/home/tripp/Documents/radio-free-albany/dashboard/news-fetcher.sh`
- Direct code analysis: `/home/tripp/Documents/facebot/src/server.ts`
- Existing analysis: `/home/tripp/Documents/radio-free-albany/.planning/codebase/CONCERNS.md`
- Existing analysis: `/home/tripp/Documents/radio-free-albany/.planning/codebase/ARCHITECTURE.md`
- Existing analysis: `/home/tripp/Documents/radio-free-albany/.planning/codebase/INTEGRATIONS.md`
- Project definition: `/home/tripp/Documents/radio-free-albany/.planning/PROJECT.md`

---

*Feature landscape analysis: 2026-02-08*

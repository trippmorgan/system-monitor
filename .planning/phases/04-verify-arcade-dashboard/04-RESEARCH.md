# Phase 4: Verify Arcade Dashboard - Research

**Researched:** 2026-02-09
**Domain:** Dashboard verification, process management, path resolution, NES.css theme
**Confidence:** HIGH

## Summary

Phase 4 is a verification/fix phase, not a feature-building phase. The goal is to confirm that the full Radio Free Albany arcade dashboard loads at localhost:8787 with all panels rendering correctly. Research uncovered one critical issue and several minor concerns.

**The critical issue:** `config.sh` hardcodes `MONITOR_HOME` to `$HOME/system-monitor`, which is a SEPARATE directory from the project at `~/Documents/radio-free-albany`. When `launch.sh` sources `config.sh`, it sets `DASHBOARD_DIR` to `~/system-monitor/dashboard` -- the OLD non-arcade dashboard. Similarly, `stop.sh` has `DASHBOARD_DIR` hardcoded to `$HOME/system-monitor/dashboard`. This means launch.sh currently serves the wrong index.html and runs the wrong scripts. Additionally, `system-stats.sh` sources the same `config.sh` and writes `stats.json` to the old location. The new news-fetcher.sh (Phase 3 rewrite) uses `SCRIPT_DIR` so it writes to whichever copy is invoked, but launch.sh invokes the old copy.

**Primary recommendation:** Fix `config.sh` to set `MONITOR_HOME` to the actual project location (`$HOME/Documents/radio-free-albany`), fix `stop.sh` to use dynamic path resolution instead of a hardcoded path, then verify end-to-end.

## launch.sh Analysis

### What It Does (4 steps)
1. **Initial data fetch** -- runs `system-stats.sh` and `news-fetcher.sh` synchronously
2. **Background refresh loop** -- subshell that runs `system-stats.sh` every 30s, `news-fetcher.sh` every N minutes (based on minute modulo)
3. **HTTP server** -- `python3 -m http.server $PORT --bind 127.0.0.1` from `$DASHBOARD_DIR`
4. **Browser open** -- tries `xdg-open`, then Firefox, then Chrome

### Path Resolution Logic
```
SCRIPT_DIR = dirname of launch.sh (dynamic, correct)
CONFIG_FILE = $SCRIPT_DIR/../config.sh (found at project root)
source config.sh -> MONITOR_HOME = $HOME/system-monitor (WRONG)
                 -> DASHBOARD_DIR = $MONITOR_HOME/dashboard (WRONG)
```

Line 40 fallback: `DASHBOARD_DIR="${DASHBOARD_DIR:-$HOME/system-monitor/dashboard}"` -- also wrong.

### Process Management
- PID files: `.refresh.pid` and `.server.pid` stored in `$DASHBOARD_DIR`
- Cleans up old PIDs on start
- Kills any existing process on port via `fuser -k $PORT/tcp`
- Refresh loop PID saved via `echo $! > "$PID_FILE"`

### Timing
- Stats refresh: every `CHECK_INTERVAL` seconds (default 30, from config.sh)
- News refresh: every `NEWS_REFRESH_INTERVAL` minutes (default 2 from config.sh, checked via minute modulo)
- Dashboard port: 8787 (from config.sh `DASHBOARD_PORT`)

## stop.sh Analysis

### What It Does
1. Reads `.refresh.pid` from `$DASHBOARD_DIR`, kills that PID
2. Reads `.server.pid` from `$DASHBOARD_DIR`, kills that PID
3. Removes both PID files

### Critical Bug
**Line 13:** `DASHBOARD_DIR="$HOME/system-monitor/dashboard"` is HARDCODED.
- Does NOT use `SCRIPT_DIR` or source `config.sh`
- This happens to work right now because launch.sh also resolves to `~/system-monitor/dashboard` (same wrong path)
- After fixing config.sh, stop.sh will also need to be fixed or it will look for PID files in the wrong place

## HTTP Server Details

- **Server:** `python3 -m http.server 8787 --bind 127.0.0.1`
- **Serving from:** `$DASHBOARD_DIR` (currently resolves to old location)
- **Bound to:** localhost only (127.0.0.1) -- not accessible from network
- **Background:** runs with `&`, PID captured
- **URL:** `http://localhost:8787/index.html`

The server serves static files from the directory it's started in. `index.html` uses relative paths to fetch `news-cache/stats.json` and `news-cache/news.json`, which works as long as the server root is the dashboard directory containing the `news-cache/` subfolder.

## Panel Inventory (index.html)

The arcade dashboard has these panels:

### Top-Level Elements
| Element | ID/Class | Purpose |
|---------|----------|---------|
| Scrolling ticker | `#top-ticker` | Animated text marquee across top |
| Header | `.arcade-header` | "RADIO FREE ALBANY" title with glitch animation |
| Boombox player | `.boombox-player` | Fixed-bottom radio player |

### Left Column
| Panel | Container | Data Element | Data Source |
|-------|-----------|--------------|-------------|
| System Vitals | `nes-container is-dark` | `#cpu-bar`, `#cpu-val`, `#mem-bar`, `#mem-val`, `#disk-bar`, `#disk-val` | `news-cache/stats.json` |
| Local News | `nes-container is-dark` | `#news-local` | `news-cache/news.json` (category: `local`) |

### Center Column
| Panel | Container | Data Element | Data Source |
|-------|-----------|--------------|-------------|
| Breaking News | `nes-container is-rounded` | `#news-breaking` | `news-cache/news.json` (category: `breaking`) |
| BotSpace BBS | `nes-container is-dark` | `#botspace-feed`, `#chat-input` | FaceBot API at `localhost:4000` |

### Right Column
| Panel | Container | Data Element | Data Source |
|-------|-----------|--------------|-------------|
| Outdoors | `nes-container is-dark` | `#news-nature` | `news-cache/news.json` (category: `nature`) |
| Sports | `nes-container is-dark` | `#news-sports` | `news-cache/news.json` (category: `sports`) |

### Boombox Player (fixed bottom bar)
| Element | ID | Purpose |
|---------|----|---------|
| Play button | -- | Calls `toggleRadio()` |
| Stop button | -- | Calls `stopRadio()` |
| Status display | `#radio-status` | Shows "READY PLAYER ONE" or "NOW PLAYING" |
| Audio element | `#radio-stream` | Streams from `https://stream.aiir.com/0ompkrc5jxntv` |

### Category Mapping (JS line 442)
The JavaScript categorizer expects these exact category strings:
```javascript
const categories = { local: [], breaking: [], sports: [], nature: [] };
```
News items with categories not in this list (e.g., `tech`, `politics`, `state`, `fishing`, `conservation`) are silently dropped. The news-fetcher.sh produces: `local`, `tech`, `nature`, `sports`, `breaking` -- of these, `tech` items are fetched but never displayed.

## NES.css CDN Status

| Resource | URL | Status | Confidence |
|----------|-----|--------|------------|
| NES.css 2.3.0 | `https://unpkg.com/nes.css@2.3.0/css/nes.min.css` | LOADS SUCCESSFULLY | HIGH |
| Press Start 2P | `https://fonts.googleapis.com/css?family=Press+Start+2P` | LOADS SUCCESSFULLY | HIGH |

Both CDN resources are live and serving valid content. NES.css provides pixel-art styled buttons, progress bars, containers, and icons. Press Start 2P is the 8-bit pixel font used throughout.

## system-stats.sh Analysis

### Path Resolution
Same issue as launch.sh: sources `config.sh`, which sets `NEWS_CACHE_DIR` to `$HOME/system-monitor/dashboard/news-cache`. Writes `stats.json` to that directory.

Fallback (no config): `NEWS_CACHE_DIR="$HOME/system-monitor/dashboard/news-cache"` -- also wrong.

### Output Format (stats.json)
```json
{
  "timestamp": "2026-02-09 16:24:00",
  "cpu": { "load": "1.23", "cores": "12" },
  "memory": { "used": "8192", "total": "32768", "percent": "25" },
  "disk": { "percent": "45", "available": "120G" },
  "gpu": { "temp": "55", "util": "10", "mem": "2048/8192" },
  "uptime": { "text": "5 days, 3 hours", "days": "5" },
  "network": { "connections": "42" },
  "services": { "docker": "active", "postgresql": "active", "ollama": "active", "ssh": "active" },
  "alerts": { "count": "7", "recent": "alert1|alert2|alert3" }
}
```

### What index.html Reads from stats.json
- `stats.cpu.load` -- displayed as percentage in CPU bar (note: load average is NOT a percentage -- this is a display quirk)
- `stats.memory.percent` -- memory bar
- `stats.disk.percent` -- disk bar
- `stats.uptime.days` -- displayed as "HIGH SCORE"
- `stats.services.docker` -- determines CREDIT display

### Missing stats.json in New Location
The `news-cache/` directory in `~/Documents/radio-free-albany/dashboard/` has `news.json` (from Phase 3) but NO `stats.json`. This is because `system-stats.sh` writes to the old location via config.sh.

## news-fetcher.sh Path Resolution

The Phase 3 rewritten news-fetcher.sh uses `SCRIPT_DIR` (NOT config.sh) for its output path:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/news-cache"
OUTPUT_FILE="$CACHE_DIR/news.json"
```

This means: when called directly as `~/Documents/radio-free-albany/dashboard/news-fetcher.sh`, it writes to the correct new location. But when launch.sh calls `$DASHBOARD_DIR/news-fetcher.sh`, and `DASHBOARD_DIR` points to `~/system-monitor/dashboard/`, it runs the OLD news-fetcher.sh (with grep-based parsing, not the Phase 3 rewrite).

## Radio Stream

The audio stream URL `https://stream.aiir.com/0ompkrc5jxntv` returns a 302 redirect to a time-limited signed URL, which is standard streaming behavior. The `<audio>` element handles this automatically in browsers. Stream is verified accessible.

## Terminal Dashboard Alternative

`dashboard/dashboard.sh` exists (10,775 bytes) as a terminal-based alternative. This is out of scope for Phase 4 -- note its existence but do not modify.

## Two Locations Problem -- Full Summary

| Item | `~/system-monitor/` (OLD) | `~/Documents/radio-free-albany/` (NEW - project) |
|------|---------------------------|---------------------------------------------------|
| index.html | Old Drudge-style (35KB) | Arcade NES.css edition (this file) |
| news-fetcher.sh | Old grep-based parser | Phase 3 Python XML rewrite |
| news.json | 90 items, 9 categories | 38 items, 5 categories |
| stats.json | EXISTS (generated by refresh loop) | MISSING |
| launch.sh | Identical copy | Identical copy |
| stop.sh | Identical copy | Identical copy |
| system-stats.sh | Identical copy | Identical copy |
| config.sh | Identical copy | Identical copy |
| .server.pid | EXISTS (active server) | Does not exist |
| .refresh.pid | EXISTS (active loop) | Does not exist |

**Root cause:** `config.sh` line 12: `export MONITOR_HOME="${MONITOR_HOME:-$HOME/system-monitor}"`

## Issues Found

### CRITICAL: config.sh MONITOR_HOME Points to Wrong Directory
- **Severity:** CRITICAL -- dashboard will serve wrong files
- **What:** `MONITOR_HOME` defaults to `$HOME/system-monitor`, not `$HOME/Documents/radio-free-albany`
- **Impact:** launch.sh serves old index.html, runs old news-fetcher, writes stats to old location
- **Fix:** Change default to `$HOME/Documents/radio-free-albany`
- **Confidence:** HIGH -- verified by tracing path resolution and confirming both directories exist

### CRITICAL: stop.sh Hardcoded Path
- **Severity:** CRITICAL -- stop.sh won't find PID files after config.sh fix
- **What:** Line 13 hardcodes `DASHBOARD_DIR="$HOME/system-monitor/dashboard"`
- **Impact:** After fixing config.sh, stop.sh will look for PID files in old location
- **Fix:** Use `SCRIPT_DIR` pattern (like launch.sh) and source config.sh
- **Confidence:** HIGH -- verified by reading stop.sh

### MINOR: stats.json Missing in New Location
- **Severity:** Auto-resolves after config.sh fix
- **What:** No stats.json in `~/Documents/radio-free-albany/dashboard/news-cache/`
- **Impact:** System Vitals panel shows "--%" until first refresh
- **Fix:** Fixed by fixing config.sh (system-stats.sh will then write to correct location)

### MINOR: Tech News Fetched But Never Displayed
- **Severity:** Low -- cosmetic waste, not a bug
- **What:** news-fetcher.sh fetches 5 Hacker News items (category: `tech`), but index.html's category map only includes `local`, `breaking`, `sports`, `nature`
- **Impact:** Tech news items are fetched and stored but silently dropped during rendering
- **Note:** This is pre-existing behavior, not a Phase 4 issue. Could add a tech panel later.

### MINOR: CPU Load Displayed as Percentage
- **Severity:** Cosmetic
- **What:** `stats.cpu.load` is a load average (e.g., "1.23") but displayed as a percentage on a 0-100 progress bar
- **Impact:** A load of 1.23 shows as 1% on the bar. Not very useful but not broken.
- **Note:** Pre-existing behavior, not a Phase 4 issue.

## What "Verification" Means for This Phase

This is NOT a code-writing phase in the traditional sense. It is a testing/fixing phase:

1. **Fix the path issue** -- update config.sh and stop.sh so the correct dashboard files are served
2. **Run launch.sh** -- confirm HTTP server starts, refresh loop runs, no errors
3. **Open browser** -- confirm all panels render with NES.css arcade theme
4. **Check each panel** -- system stats load, news populates, BotSpace connects (or shows offline gracefully), radio player buttons work
5. **Run stop.sh** -- confirm clean shutdown
6. **Verify FaceBot integration** -- if FaceBot is running at :4000, BotSpace panel should show messages; if not, should show "FACEBOT OFFLINE"

The scope of code changes is limited to:
- `config.sh` line 12 (MONITOR_HOME path)
- `stop.sh` lines 13-15 (path resolution)
- Possibly fixing stale PID files from old location

## Potential Issues for Verification

| Check | What to Test | Pass Criteria |
|-------|-------------|---------------|
| NES.css loads | Pixel fonts and retro borders visible | Not Times New Roman or unstyled HTML |
| CRT scanline effect | Subtle scanline overlay on page | CSS `::before` pseudo-element renders |
| System Vitals | CPU/Memory/Disk bars populated | Values show percentages, bars move |
| Local News | Items from Albany Herald/WALB/WTXL | Category "local" items render in left column |
| Breaking News | BBC World items | Category "breaking" items in center |
| Sports | WTXL Sports items | Category "sports" items in right column |
| Outdoors | GA Wildlife items | Category "nature" items in right column |
| BotSpace | Chat messages or offline notice | Either messages from FaceBot or "FACEBOT OFFLINE" |
| Radio Player | Play/Stop buttons | Audio element present, buttons call JS functions |
| Ticker | Scrolling text animation | Green text scrolls across top |
| Refresh Loop | Stats update every 30s | stats.json timestamp changes |
| stop.sh | Processes die cleanly | Port 8787 freed, no orphan processes |

## Sources

### Primary (HIGH confidence)
- Direct file reading of all dashboard scripts (launch.sh, stop.sh, index.html, system-stats.sh, news-fetcher.sh, config.sh)
- Path resolution verified by simulating launch.sh sourcing config.sh
- Both `~/system-monitor/` and `~/Documents/radio-free-albany/` directory contents compared
- NES.css CDN verified via WebFetch (unpkg.com/nes.css@2.3.0)
- Press Start 2P font verified via WebFetch (fonts.googleapis.com)
- Radio stream URL verified via WebFetch (302 redirect = normal for streaming)

### Secondary (MEDIUM confidence)
- FaceBot CORS configuration verified from facebot source code (`cors()` wide open)

## Metadata

**Confidence breakdown:**
- Path resolution issue: HIGH -- verified by simulating config.sh sourcing and comparing directory contents
- Panel inventory: HIGH -- read directly from index.html source
- CDN status: HIGH -- verified with live WebFetch requests
- Fix scope: HIGH -- changes are minimal and well-understood
- Radio stream: MEDIUM -- 302 redirect is normal but stream availability depends on external service

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (stable -- no fast-moving dependencies)

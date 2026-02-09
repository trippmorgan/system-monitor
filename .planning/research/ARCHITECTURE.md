# Architecture Patterns

**Domain:** Local news dashboard + agent chat integration (repair/connect milestone)
**Researched:** 2026-02-08

## Recommended Architecture

Two independent servers with a shared-nothing design, connected only through the browser client. The dashboard does not proxy or relay to FaceBot -- the browser JavaScript talks to both servers directly.

```
                          BROWSER (localhost)
                         /                   \
            HTTP GET :8787                HTTP GET/POST :4000
                   /                             \
    +--------------------------+     +-------------------------+
    | Radio Free Albany        |     | FaceBot                 |
    | (Python http.server)     |     | (Express + SQLite)      |
    |                          |     |                         |
    | Serves:                  |     | Serves:                 |
    |   index.html             |     |   GET /api/feed         |
    |   news-cache/news.json   |     |   POST /api/post        |
    |   news-cache/stats.json  |     |   GET /api/agent/:user  |
    +--------------------------+     +-------------------------+
               ^                                ^
               |                                |
    +--------------------+           +--------------------+
    | Collection Layer   |           | Agent Scripts      |
    | (bash cron loop)   |           | (curl POST to      |
    |                    |           |  localhost:4000)    |
    | system-stats.sh    |           |                    |
    | news-fetcher.sh    |           | health-check.sh    |
    +--------------------+           | system-monitor.sh  |
                                     +--------------------+
```

### Why This Shape

The existing dashboard is a static file server (Python `http.server`). It cannot proxy API requests. FaceBot is a separate Express server with its own database. Rather than merge them (which would violate the "no npm/frameworks in radio-free-albany" constraint), keep them as two independent servers that the browser talks to via separate `fetch()` calls. This is the simplest architecture that respects the existing constraints.

CORS is already enabled on FaceBot (`app.use(cors())`), so cross-origin requests from `:8787` to `:4000` work without any changes.

## Component Boundaries

| Component | Responsibility | Location | Communicates With |
|-----------|---------------|----------|-------------------|
| **Dashboard Server** | Serve static HTML/JS/CSS and JSON data files | `~/Documents/radio-free-albany/dashboard/` | Browser (serves files) |
| **Collection Scripts** | Gather system metrics and news, write JSON | `dashboard/system-stats.sh`, `dashboard/news-fetcher.sh` | Filesystem (writes `news-cache/*.json`) |
| **Refresh Loop** | Schedule collection scripts on intervals | `dashboard/launch.sh` (background process) | Collection Scripts (invokes) |
| **FaceBot Server** | Persist and serve agent chat messages | `~/Documents/facebot/` | Browser (API), Agent Scripts (API) |
| **Browser Client** | Render dashboard, poll both servers | `dashboard/index.html` (vanilla JS) | Dashboard Server (:8787), FaceBot (:4000) |
| **Agent Scripts** | Post system events to FaceBot | Various in `scripts/` | FaceBot API (HTTP POST) |
| **Orchestration** | Start/stop all processes | `launch.sh`, `stop.sh` | Dashboard Server, Refresh Loop |

### Boundary Rules

1. **Dashboard server never talks to FaceBot.** The Python `http.server` has no routing capability. It only serves files.
2. **FaceBot never talks to Dashboard server.** FaceBot has no knowledge of the dashboard. It exposes a REST API and that is it.
3. **The browser is the integration point.** JavaScript in `index.html` fetches from both servers independently.
4. **Collection scripts write to files, not APIs.** `news-fetcher.sh` and `system-stats.sh` write JSON to `news-cache/`. They do not talk to FaceBot.
5. **Agent scripts write to FaceBot, not files.** When system events should appear in BotSpace, scripts POST to `localhost:4000/api/post`.

## Data Flow

### Flow 1: News Pipeline (news-fetcher.sh -> news.json -> Dashboard JS)

```
news-fetcher.sh                     news-cache/news.json              index.html JS
     |                                      |                              |
     | 1. curl RSS feeds (30+ sources)      |                              |
     | 2. Parse titles via grep -oP         |                              |
     | 3. Build NDJSON temp file            |                              |
     | 4. python3 converts to JSON array    |                              |
     |------- write ----------------------->|                              |
     |                                      |                              |
     |                                      | 5. fetch('news-cache/        |
     |                                      |    news.json?' + Date.now()) |
     |                                      |<-----------------------------|
     |                                      |                              |
     |                                      | 6. Sort by timestamp         |
     |                                      | 7. Categorize: local,        |
     |                                      |    breaking, sports, nature  |
     |                                      | 8. Render into DOM panels    |
     |                                      |                              |
```

**Timing:** news-fetcher.sh runs every 2 minutes (configurable via `NEWS_REFRESH_INTERVAL`). Dashboard JS polls `news.json` every 30 seconds. There is no push notification -- the dashboard always reads the most recent file.

**Failure mode:** If news-fetcher.sh fails, `news.json` retains previous data. Dashboard shows stale-but-valid news. No error is visible to the user unless all categories are empty.

**Key repair needed:** News-fetcher.sh currently pulls from generic national sources. Needs Albany Herald, WALB, WTXL RSS feeds added for the `local` category.

### Flow 2: System Stats Pipeline (system-stats.sh -> stats.json -> Dashboard JS)

```
system-stats.sh                     news-cache/stats.json             index.html JS
     |                                      |                              |
     | 1. Read /proc/loadavg               |                              |
     | 2. Run free -m, df, nvidia-smi      |                              |
     | 3. Check systemctl services          |                              |
     | 4. Build JSON via heredoc            |                              |
     |------- write ----------------------->|                              |
     |                                      |                              |
     |                                      | 5. fetch('news-cache/        |
     |                                      |    stats.json?' + Date.now())|
     |                                      |<-----------------------------|
     |                                      |                              |
     |                                      | 6. Update HP bars (CPU,      |
     |                                      |    memory, disk)             |
     |                                      | 7. Update header scores      |
     |                                      |                              |
```

**Timing:** system-stats.sh runs every 30 seconds (configurable via `CHECK_INTERVAL`). Dashboard JS polls on the same 30-second interval.

**No repair needed.** This pipeline is working.

### Flow 3: BotSpace Chat (FaceBot API -> Dashboard JS Polling)

```
Agent Script              FaceBot (Express :4000)              index.html JS
     |                           |                                   |
     | 1. curl -X POST           |                                   |
     |    /api/post              |                                   |
     |    {username, content}    |                                   |
     |-------------------------->|                                   |
     |                           | 2. Lookup agent by username       |
     |                           | 3. INSERT into posts table        |
     |                           | 4. Return {success, id}           |
     |                           |                                   |
     |                           |   5. fetch('http://localhost:     |
     |                           |      4000/api/feed')              |
     |                           |<----------------------------------|
     |                           |                                   |
     |                           | 6. Return 50 most recent posts   |
     |                           |---------------------------------->|
     |                           |                                   |
     |                           |   7. Render posts in BotSpace     |
     |                           |      chat panel                   |
     |                           |   8. Wire SEND button to          |
     |                           |      POST /api/post               |
     |                           |                                   |
```

**Current state:** Dashboard has the BotSpace UI panel built (HTML/CSS done). The JavaScript currently:
- Tries to fetch `news-cache/feedback.json` (line 481) -- **wrong endpoint, needs to hit FaceBot**
- Has `postChat()` function with `// TODO: Send to backend API` (line 509) -- **not wired**
- Chat refresh interval is commented out (line 518) -- **needs uncommenting**

**Repair needed:**
1. Change `loadChat()` to fetch from `http://localhost:4000/api/feed` instead of `news-cache/feedback.json`
2. Wire `postChat()` to POST to `http://localhost:4000/api/post` with `{username: "tripp", content: inputValue}`
3. Uncomment `setInterval(loadChat, 5000)` on line 518
4. Map FaceBot response fields (`username`, `name`, `icon`, `content`, `type`) to BotSpace chat HTML

**Polling interval:** 5 seconds (already defined in commented-out code). This is appropriate for a local chat feed.

### Flow 4: Agent Event Publishing (System Scripts -> FaceBot)

```
health-check.sh / system-monitor-assistant.sh
     |
     | On threshold alert:
     | curl -s -X POST http://localhost:4000/api/post \
     |   -H "Content-Type: application/json" \
     |   -d '{"username":"security","content":"ALERT: CPU load critical (8.5)"}'
     |
     v
FaceBot (SQLite INSERT)
     |
     v
Dashboard polls /api/feed -> user sees alert in BotSpace panel
```

**Current state:** No agent scripts currently POST to FaceBot. This is a **new integration** to wire up after FaceBot itself is working.

**Build order dependency:** FaceBot must be running and accepting POST requests before agent scripts can publish to it.

## Patterns to Follow

### Pattern 1: File-Based Data Exchange (Existing, Keep)

**What:** Collection scripts write JSON files. Dashboard reads them via HTTP. No shared database between the two.

**When:** All system stats and news data flows.

**Why keep it:** Simple, zero-dependency, works with Python `http.server`, easy to debug (just `cat news-cache/news.json`). The collection layer and presentation layer are fully decoupled -- you can run `news-fetcher.sh` manually and see results immediately.

**Example (existing):**
```bash
# system-stats.sh writes
cat > "$STATS_FILE" << EOF
{"timestamp": "...", "cpu": {"load": "2.5"}, ...}
EOF

# dashboard JS reads
const statsRes = await fetch('news-cache/stats.json?' + Date.now());
```

### Pattern 2: Direct API Polling for Chat (New, Add)

**What:** Dashboard JavaScript polls FaceBot REST API directly via `fetch()`. No intermediate file.

**When:** BotSpace chat panel data.

**Why this works:** FaceBot already has CORS enabled. The browser can talk to both `:8787` (static files) and `:4000` (API) simultaneously. No proxy needed.

**Example (to implement):**
```javascript
async function loadChat() {
    try {
        const res = await fetch('http://localhost:4000/api/feed?' + Date.now());
        const posts = await res.json();
        const feed = document.getElementById('botspace-feed');
        feed.innerHTML = posts.slice(-10).map(post => `
            <div class="chat-msg ${post.type === 'alert' ? 'alert' : ''}">
                <span class="chat-user">${post.icon || ''} ${post.name}:</span> ${post.content}
            </div>
        `).join('');
        feed.scrollTop = feed.scrollHeight;
    } catch(e) {
        console.log("FaceBot offline");
    }
}
```

### Pattern 3: Fire-and-Forget Agent Posts (New, Add)

**What:** System scripts POST to FaceBot when events happen. They do not wait for or depend on FaceBot being available.

**When:** Alert thresholds crossed, health checks complete, services change state.

**Why fire-and-forget:** If FaceBot is down, the alert still gets logged to `alerts.log`. BotSpace is a nice-to-have view, not a critical alerting path. The curl should have a short timeout and ignore failures.

**Example (to implement in health-check.sh):**
```bash
# Post to FaceBot if available (fire-and-forget)
curl -s --max-time 3 -X POST http://localhost:4000/api/post \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"firstofficer\",\"content\":\"Daily health check complete. CPU: ${LOAD}, Memory: ${MEM_PCT}%, Disk: ${DISK_PCT}%\"}" \
  2>/dev/null || true
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Merging the Servers

**What:** Replacing Python `http.server` with Express, or adding API routes to the dashboard server.

**Why bad:** Violates the "no npm/frameworks in radio-free-albany" constraint. Would require Node.js as a dependency for the dashboard. Would couple FaceBot's lifecycle to the dashboard. If one breaks, both break.

**Instead:** Keep them as two separate processes. The browser handles integration.

### Anti-Pattern 2: FaceBot Writing to news-cache/ Files

**What:** Having FaceBot write `feedback.json` to the dashboard's `news-cache/` directory so the dashboard can read it as a static file.

**Why bad:** Creates a filesystem coupling between two separate projects. FaceBot would need write access to the dashboard directory. Introduces race conditions. Defeats the purpose of having a REST API.

**Instead:** Dashboard JavaScript fetches from FaceBot API directly. FaceBot stores data in its own SQLite database.

### Anti-Pattern 3: Dashboard Server Proxying to FaceBot

**What:** Adding a reverse proxy layer so the dashboard serves `/api/*` routes that forward to FaceBot.

**Why bad:** Python `http.server` has no proxy capability. Would require nginx or similar, adding infrastructure complexity to a personal workstation project. Over-engineering.

**Instead:** Direct browser-to-FaceBot fetch with CORS. Already works.

### Anti-Pattern 4: Making FaceBot a Hard Dependency

**What:** Dashboard fails or shows errors if FaceBot is not running.

**Why bad:** Dashboard should work independently. News and system stats are the primary value. Chat is supplementary.

**Instead:** Graceful degradation. If FaceBot is unreachable, BotSpace panel shows the default welcome message ("Welcome to BotSpace"). No errors. No broken UI.

## Build Order (Critical for Roadmap)

The repair work has hard dependencies that dictate phase ordering:

```
Phase 1: Fix FaceBot Server
   |
   | FaceBot must compile and run before anything can connect to it
   |
   v
Phase 2: Fix News Fetcher
   |
   | Can run in parallel with Phase 1, but listed second because
   | it's a simpler fix (adding RSS URLs to an existing script)
   |
   v
Phase 3: Wire BotSpace to FaceBot
   |
   | DEPENDS ON Phase 1 (FaceBot must be running on :4000)
   | Dashboard JS changes to fetch from FaceBot API
   |
   v
Phase 4: Wire Agent Scripts to FaceBot
   |
   | DEPENDS ON Phase 1 (FaceBot must accept POST requests)
   | DEPENDS ON Phase 3 (so you can verify posts appear in BotSpace)
   | Add curl POST calls to health-check.sh, system-monitor-assistant.sh
   |
   v
Phase 5: Verify End-to-End
   |
   | DEPENDS ON all prior phases
   | launch.sh starts dashboard, FaceBot started separately
   | Verify: news loads, stats update, BotSpace shows agent messages
```

**Why FaceBot first:** The `sqlite3` vs `better-sqlite3` dependency mismatch means FaceBot will not start at all right now. Nothing can connect to a server that does not run. This is the blocking issue.

**Why news fetcher can be parallel:** It is purely a file-based pipeline change (add local RSS URLs). It does not touch FaceBot or BotSpace. Could be done simultaneously with Phase 1 if resources allow.

**Why BotSpace wiring requires FaceBot:** The dashboard JavaScript needs a running FaceBot to test against. You cannot verify `fetch('http://localhost:4000/api/feed')` works unless FaceBot is actually serving responses.

## Process Lifecycle

### Current Lifecycle (Dashboard Only)

```
launch.sh
  |-- Initial fetch: system-stats.sh + news-fetcher.sh
  |-- Start: background refresh loop (PID saved to .refresh.pid)
  |-- Start: python3 -m http.server 8787 (PID saved to .server.pid)
  |-- Open: browser to localhost:8787

stop.sh
  |-- Kill: refresh loop (from .refresh.pid)
  |-- Kill: HTTP server (from .server.pid)
```

### Required Lifecycle (Dashboard + FaceBot)

FaceBot is a **separate project** with its own lifecycle. It should NOT be managed by `launch.sh`. Options:

**Option A (Recommended): Manual FaceBot Start**
```bash
# Terminal 1: Start FaceBot
cd ~/Documents/facebot && npm start

# Terminal 2: Start Dashboard
~/Documents/radio-free-albany/dashboard/launch.sh
```

**Why recommended:** Keeps projects independent. FaceBot can run without the dashboard. Dashboard can run without FaceBot (graceful degradation). No cross-project process management complexity.

**Option B (Future Enhancement): launch.sh Checks FaceBot**
```bash
# launch.sh could check if FaceBot is already running
if curl -s --max-time 2 http://localhost:4000/api/feed >/dev/null 2>&1; then
    echo "FaceBot detected on :4000"
else
    echo "Warning: FaceBot not running. BotSpace will be offline."
fi
```

This is a nice-to-have health check, not a launcher. launch.sh should not start processes in another project's directory.

## Scalability Considerations

| Concern | Current (1 user) | At Scale (not applicable) | Notes |
|---------|-------------------|---------------------------|-------|
| News fetch time | 2-3 min sequential | N/A | Could parallelize with `&` and `wait` |
| FaceBot SQLite | Fine for 1000s of posts | N/A | Personal project, will not hit limits |
| Dashboard serving | Python http.server, 1 user | N/A | Localhost only, never needs scaling |
| Polling frequency | 30s stats, 5s chat | N/A | Acceptable for personal dashboard |

This is a personal workstation tool. Scalability is not a concern. The architecture is designed for simplicity and debuggability, not throughput.

## Port Allocation

| Port | Service | Binding | Purpose |
|------|---------|---------|---------|
| 8787 | Python http.server | 127.0.0.1 | Dashboard static files |
| 4000 | Express (FaceBot) | 0.0.0.0 (default) | Chat API |

**Note:** FaceBot binds to all interfaces by default (Express default). For security on a personal workstation, consider binding to localhost: `app.listen(port, '127.0.0.1', ...)`. Not critical for personal use but good hygiene.

## Sources

- `/home/tripp/Documents/radio-free-albany/dashboard/index.html` -- Dashboard source, lines 478-518 (BotSpace JavaScript, currently incomplete)
- `/home/tripp/Documents/radio-free-albany/dashboard/news-fetcher.sh` -- News collection pipeline
- `/home/tripp/Documents/radio-free-albany/dashboard/launch.sh` -- Process orchestration
- `/home/tripp/Documents/radio-free-albany/dashboard/system-stats.sh` -- System metrics collection
- `/home/tripp/Documents/radio-free-albany/config.sh` -- Centralized configuration
- `/home/tripp/Documents/facebot/src/server.ts` -- FaceBot server source (Express + better-sqlite3)
- `/home/tripp/Documents/facebot/package.json` -- FaceBot dependencies (sqlite3 listed, better-sqlite3 used in code)
- `/home/tripp/Documents/facebot/PLAN.md` -- FaceBot integration plan
- `/home/tripp/Documents/radio-free-albany/.planning/PROJECT.md` -- Project requirements and scope
- `/home/tripp/Documents/radio-free-albany/.planning/codebase/ARCHITECTURE.md` -- Existing architecture analysis
- `/home/tripp/Documents/facebot/.planning/codebase/ARCHITECTURE.md` -- FaceBot architecture analysis

**Confidence:** HIGH -- all findings based on direct source code analysis of both projects. No external sources needed; this is an architecture assessment of existing code.

---

*Architecture research: 2026-02-08*

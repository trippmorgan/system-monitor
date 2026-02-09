# Technology Stack

**Project:** Radio Free Albany - Arcade Edition Upgrade
**Researched:** 2026-02-08
**Focus:** RSS feed parsing, sqlite3 async migration, vanilla JS chat polling

## Recommended Stack

### 1. RSS Feed Parsing (news-fetcher.sh)

**Recommendation: Replace grep-based RSS parsing with Python `xml.etree.ElementTree`**

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Python 3 `xml.etree.ElementTree` | stdlib | RSS/XML parsing | Already available (no install), handles XML namespaces, entity encoding, CDATA sections that grep cannot |
| `curl` | system | HTTP fetching | Keep existing curl for fetching; Python only for parsing |

**Why NOT `feedparser` (pip package):**
The project constraint is "no pip dependencies" for radio-free-albany (Bash + vanilla JS + Python stdlib only). `feedparser` is the gold standard for RSS parsing in Python, but it requires `pip install feedparser`. The project already uses Python 3 as a stdlib tool (for JSON conversion in news-fetcher.sh lines 322-345). Using `xml.etree.ElementTree` from stdlib maintains zero-dependency posture while being dramatically more reliable than grep regex.

**Why NOT keep `grep -oP '<title>\K[^<]+'`:**
The current approach (grep with Perl regex) fails on:
- CDATA-wrapped titles: `<title><![CDATA[Story about <thing>]]></title>`
- HTML entities: `<title>Gov&#39;s Plan &amp; Budget</title>`
- Multi-line title elements (some RSS feeds split across lines)
- Namespace prefixes: `<media:title>` vs `<title>`
The CONCERNS.md already flags this as a "Performance Bottleneck" and "Fragile Area."

**Pattern: curl fetches, Python parses**

```bash
# Fetch RSS, pipe to Python for parsing
parse_rss() {
    local url="$1"
    local category="$2"
    local source="$3"
    local bias="$4"
    local bias_label="$5"
    local max_items="${6:-5}"

    curl -s --max-time 15 -A "Mozilla/5.0" "$url" 2>/dev/null | \
    python3 -c "
import sys
import xml.etree.ElementTree as ET
import json

try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    # Handle both RSS 2.0 and Atom feeds
    ns = {'atom': 'http://www.w3.org/2005/Atom'}
    items = root.findall('.//item') or root.findall('.//atom:entry', ns)
    count = 0
    for item in items:
        if count >= $max_items:
            break
        title_el = item.find('title') or item.find('atom:title', ns)
        link_el = item.find('link') or item.find('atom:link', ns)
        if title_el is not None and title_el.text:
            title = title_el.text.strip()[:200]
            link = ''
            if link_el is not None:
                link = link_el.text or link_el.get('href', '')
            if len(title) > 5:
                import time
                obj = {
                    'source': '$source',
                    'title': title,
                    'url': link or '',
                    'bias': $bias,
                    'bias_label': '$bias_label',
                    'category': '$category',
                    'timestamp': int(time.time())
                }
                print(json.dumps(obj))
                count += 1
except Exception as e:
    print(f'RSS parse error: {e}', file=sys.stderr)
" >> "$TEMP_FILE"
}
```

**Confidence: HIGH** - `xml.etree.ElementTree` is Python stdlib, well-documented, and the standard approach for XML parsing in Python without external dependencies. The project already uses inline Python for JSON processing.

### Albany, GA Local News RSS Sources

| Source | RSS URL | Category | Bias | Notes |
|--------|---------|----------|------|-------|
| Albany Herald | `https://www.albanyherald.com/search/?f=rss&t=article&l=50` | local | 5 (Center) | Paywall on articles but RSS titles are free |
| WALB News 10 | `https://www.walb.com/search/?f=rss&t=article&l=25` | local | 0 (Center) | Gray Television NBC affiliate |
| WTXL ABC 27 | `https://www.wtxl.com/news.rss` | local | 0 (Center) | Scripps station, covers Albany-Tallahassee market |

**Confidence: LOW** - These RSS URLs are based on common patterns for Gray Television and Scripps station websites. The exact paths need runtime verification. Many local news station RSS feeds have been deprecated or moved behind content management system changes. **Must verify these URLs with curl before committing to implementation.**

**Fallback strategy:** If direct RSS feeds are unavailable, keep Google News RSS search (`news.google.com/rss/search?q=Albany+Georgia`) as the fallback -- this is what currently works. Add local station names to the search query for better targeting: `q=Albany+Georgia+site:walb.com+OR+site:albanyherald.com`.

---

### 2. SQLite3 Async Migration (FaceBot server.ts)

**Recommendation: Use `sqlite3` npm package with `util.promisify` wrappers**

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `sqlite3` | ^5.1.7 | SQLite database access | Already in package.json, async/callback-based, well-maintained |
| `util.promisify` | Node.js stdlib | Wrap callbacks as Promises | Clean async/await syntax without adding another dependency |

**Current Problem:**
FaceBot's `server.ts` imports `better-sqlite3` (synchronous API) but `package.json` lists `sqlite3` (async/callback API). The code uses `better-sqlite3` patterns:
- `db.exec(sql)` -- synchronous
- `db.prepare(sql).run(...)` -- synchronous
- `db.prepare(sql).all()` -- synchronous
- `db.prepare(sql).get(...)` -- synchronous

**Why `sqlite3` (async) instead of `better-sqlite3` (sync):**
Per PROJECT.md: "better-sqlite3 has native compilation issues." The `better-sqlite3` package requires `node-gyp` compilation of a native addon and frequently fails on newer Node.js versions or non-standard build environments. The `sqlite3` package also requires native compilation but has broader prebuilt binary support via `@mapbox/node-pre-gyp`. Since `sqlite3` is already in `package.json`, use it.

**Why NOT switch to `better-sqlite3` anyway:**
While `better-sqlite3` has a simpler API (synchronous), the decision to move away from it was already made due to build failures. Reversing that decision would just reintroduce the build problem.

**Why NOT use `sql.js` (pure JS SQLite):**
`sql.js` compiles SQLite to WebAssembly -- no native dependencies. But it loads the entire database into memory and must be manually serialized to disk. For a personal server this would work, but it is an unusual pattern that would confuse future maintenance. The `sqlite3` package is the standard Node.js SQLite binding.

**Migration Pattern: Promisified Wrapper**

```typescript
// db.ts - Database wrapper with promisified sqlite3
import sqlite3 from 'sqlite3';
import { promisify } from 'util';

const db = new sqlite3.Database('facebot.db');

// Promisify the core methods
export const dbRun = promisify(db.run.bind(db));
export const dbGet = promisify(db.get.bind(db));
export const dbAll = promisify(db.all.bind(db));

// For exec (schema creation), wrap manually since it doesn't follow
// the standard (err, result) callback pattern consistently
export function dbExec(sql: string): Promise<void> {
    return new Promise((resolve, reject) => {
        db.exec(sql, (err) => {
            if (err) reject(err);
            else resolve();
        });
    });
}

export default db;
```

**Usage in server.ts after migration:**

```typescript
// BEFORE (better-sqlite3 sync):
const posts = db.prepare(`SELECT ...`).all();
res.json(posts);

// AFTER (sqlite3 async with promisify):
const posts = await dbAll(`SELECT p.*, a.username, a.name, a.icon
    FROM posts p JOIN agents a ON p.agent_id = a.id
    ORDER BY p.created_at DESC LIMIT 50`);
res.json(posts);
```

**Key API differences (better-sqlite3 vs sqlite3):**

| Operation | better-sqlite3 (sync) | sqlite3 (async promisified) |
|-----------|----------------------|----------------------------|
| Execute DDL | `db.exec(sql)` | `await dbExec(sql)` |
| Insert/Update | `db.prepare(sql).run(p1, p2)` | `await dbRun(sql, p1, p2)` |
| Select one | `db.prepare(sql).get(p1)` | `await dbGet(sql, p1)` |
| Select many | `db.prepare(sql).all()` | `await dbAll(sql)` |
| Parameterized | `.run(val1, val2)` | `dbRun(sql, val1, val2)` or `dbRun(sql, [val1, val2])` |

**Additional fix needed:** The code imports `uuid` (`import { v4 as uuidv4 } from 'uuid'`) but `uuid` is not in `package.json`. Either add `uuid` as a dependency or replace with `crypto.randomUUID()` (available in Node.js 19+) or a simple timestamp-based ID.

**Confidence: HIGH** - The `sqlite3` npm package callback-to-promise pattern via `util.promisify` is a standard, well-documented Node.js pattern. The API surface is stable and has not changed significantly.

---

### 3. Vanilla JS Chat Polling (Dashboard)

**Recommendation: `setInterval` + `fetch` with backoff, NOT WebSockets**

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `fetch` API | Browser built-in | HTTP requests to FaceBot | Already used in dashboard for stats/news; consistent pattern |
| `setInterval` | Browser built-in | Polling loop | Simple, matches existing 30s stats loop pattern |

**Why polling (not WebSockets):**
1. FaceBot is a personal single-user server on localhost. Chat volume is near-zero (agents posting status updates).
2. The dashboard already uses polling for stats (30s) and news (30s). Adding WebSockets for one panel creates inconsistent patterns.
3. WebSockets require server-side upgrade handling, heartbeat logic, reconnection logic. Over-engineering for a BBS-style feed.
4. The BotSpace panel refreshes "last 10 messages" -- polling every 3-5 seconds is perfectly adequate for agent status updates.

**Why NOT Server-Sent Events (SSE):**
SSE is a better fit than WebSockets for one-directional feeds, but FaceBot also needs to accept POST from the chat input. Mixing SSE (read) + fetch (write) adds complexity. Pure polling keeps one communication pattern. For a personal dashboard, the difference between 3s polling and instant SSE push is imperceptible.

**Pattern: Polling with simple state management**

```javascript
// Chat polling - fetch last N messages from FaceBot
const FACEBOT_URL = 'http://localhost:4000';
let lastMessageTimestamp = 0;

async function loadChat() {
    try {
        const res = await fetch(`${FACEBOT_URL}/api/feed?_=${Date.now()}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const messages = await res.json();

        const feed = document.getElementById('botspace-feed');
        feed.innerHTML = messages.slice(0, 15).map(msg => `
            <div class="chat-msg ${msg.type === 'alert' ? 'alert' : ''}">
                <span class="chat-user">${escapeHtml(msg.icon || '')} ${escapeHtml(msg.name || 'SYSTEM')}:</span>
                ${escapeHtml(msg.content)}
            </div>
        `).join('');
        feed.scrollTop = feed.scrollHeight;
    } catch(e) {
        console.log('BotSpace offline:', e.message);
        // Don't clear existing messages on error -- show stale data
    }
}

async function postChat() {
    const input = document.getElementById('chat-input');
    if (!input.value.trim()) return;

    try {
        await fetch(`${FACEBOT_URL}/api/post`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                username: 'tripp',
                content: input.value.trim()
            })
        });
        input.value = '';
        loadChat(); // Immediate refresh after posting
    } catch(e) {
        console.log('Post failed:', e.message);
    }
}

// HTML escaping to prevent XSS (CONCERNS.md flags this)
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Start chat polling (every 5 seconds)
setInterval(loadChat, 5000);
loadChat(); // Initial load
```

**CORS requirement:** FaceBot already includes `app.use(cors())` -- this allows the dashboard (localhost:8787) to call the API (localhost:4000). No additional CORS configuration needed.

**Confidence: HIGH** - `fetch` + `setInterval` is the most straightforward pattern for this use case. The dashboard already uses this exact pattern for stats and news. No new concepts introduced.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| RSS Parsing | Python `xml.etree.ElementTree` | `feedparser` (pip) | Project constraint: no pip dependencies |
| RSS Parsing | Python `xml.etree.ElementTree` | `grep -oP` (current) | Breaks on CDATA, HTML entities, multi-line elements |
| RSS Parsing | Python `xml.etree.ElementTree` | `xmllint --xpath` | Not always installed; awkward for extracting multiple fields |
| SQLite (Node) | `sqlite3` + promisify | `better-sqlite3` | Native compilation failures (existing known issue) |
| SQLite (Node) | `sqlite3` + promisify | `sql.js` (Wasm) | In-memory only, manual serialization, unusual pattern |
| SQLite (Node) | `sqlite3` + promisify | `drizzle-orm` / `prisma` | Heavy ORM overkill for 2 tables on a personal project |
| Chat transport | `fetch` polling | WebSockets (`ws`) | Over-engineering for single-user localhost BBS |
| Chat transport | `fetch` polling | Server-Sent Events | Adds complexity for imperceptible benefit at this scale |
| UUID generation | `crypto.randomUUID()` | `uuid` npm package | uuid not in package.json; randomUUID() is built into Node 19+ |

## Additional Dependencies Needed

### FaceBot (~/Documents/facebot)

```bash
# Install existing dependencies (node_modules missing)
cd ~/Documents/facebot && npm install

# uuid is imported but not in package.json -- either:
# Option A: Add it
npm install uuid && npm install -D @types/uuid

# Option B (preferred): Replace with crypto.randomUUID() in server.ts
# No install needed -- built into Node.js 19+
```

### Radio Free Albany (~/Documents/radio-free-albany)

```bash
# No new dependencies needed
# Python xml.etree.ElementTree is stdlib
# curl already used
# No pip install required
```

## What NOT to Use

| Technology | Why Avoid |
|------------|-----------|
| `jq` for RSS parsing | Not an XML parser. Current project notes suggest jq for JSON but RSS is XML. |
| `feedparser` via pip | Violates zero-dependency constraint for radio-free-albany scripts |
| `axios` for FaceBot HTTP | Express already handles HTTP; dashboard uses native `fetch` |
| `socket.io` | Massive dependency for a feature that polling handles fine |
| `sequelize` / `typeorm` | ORM overhead for 2 tables is absurd |
| `node-fetch` in Node.js | Node 18+ has native `fetch`; no polyfill needed |
| `better-sqlite3` | Known native compilation issues per PROJECT.md |
| Long polling | More complex than simple polling, no benefit at this scale |

## Version Constraints

| Dependency | Minimum Version | Reason |
|------------|----------------|--------|
| Python 3 | 3.6+ | f-strings used in existing code, `xml.etree.ElementTree` stable since 2.x |
| Node.js | 19+ | `crypto.randomUUID()` (if replacing uuid package) |
| Node.js | 18+ | Native `fetch` in Node (if needed server-side) |
| sqlite3 (npm) | ^5.1.7 | Already specified in package.json |
| Express | ^4.19.2 | Already specified in package.json |
| TypeScript | ^5.4.5 | Already specified in package.json |

## Sources

- Codebase analysis: `/home/tripp/Documents/radio-free-albany/dashboard/news-fetcher.sh` (current grep-based RSS parsing)
- Codebase analysis: `/home/tripp/Documents/facebot/src/server.ts` (current better-sqlite3 sync API)
- Codebase analysis: `/home/tripp/Documents/facebot/package.json` (sqlite3 ^5.1.7 listed, uuid missing)
- Codebase analysis: `/home/tripp/Documents/radio-free-albany/dashboard/index.html` (existing fetch + setInterval pattern, BotSpace panel)
- Project constraints: `/home/tripp/Documents/radio-free-albany/.planning/PROJECT.md` (no pip, better-sqlite3 build issues)
- Known issues: `/home/tripp/Documents/radio-free-albany/.planning/codebase/CONCERNS.md` (grep RSS fragility, XSS in chat)
- Python stdlib docs: `xml.etree.ElementTree` is stable stdlib since Python 2.5, fully supported
- Node.js stdlib: `util.promisify` stable since Node.js 8, `crypto.randomUUID()` since Node.js 19

**Note on confidence:** All RSS URL paths for Albany Herald, WALB, and WTXL are LOW confidence and must be verified at runtime. All other recommendations are HIGH confidence based on direct codebase analysis and well-established stdlib patterns.

---

*Stack research: 2026-02-08*

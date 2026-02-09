# Domain Pitfalls

**Domain:** Local news dashboard repair + chat backend integration
**Researched:** 2026-02-08

## Critical Pitfalls

Mistakes that cause rewrites or major issues.

### Pitfall 1: grep-Based RSS Parsing Breaks Silently on Format Changes

**What goes wrong:** The entire `news-fetcher.sh` uses `grep -oP '<title>\K[^<]+'` to extract titles from RSS feeds. This pattern assumes: (a) `<title>` is on a single line, (b) titles contain no `<` characters, (c) CDATA sections are not used, (d) the XML is not minified. Any of these assumptions failing produces zero results with exit code 0 -- a silent failure. The script currently has no mechanism to detect "we got zero items from CBS" versus "CBS feed is down."

**Why it happens:** RSS is XML, not a line-oriented format. Grep treats it as text. Real RSS feeds from local news stations (WALB, Albany Herald, WTXL) frequently use CDATA wrappers like `<title><![CDATA[Mayor announces...]]></title>`, which the current regex completely misses. Some feeds minify their XML onto a single line, breaking grep's line-by-line processing. Entity-encoded characters (`&amp;`, `&#39;`) in titles pass through raw, producing garbled display text.

**Consequences:** Local news categories show "NO TARGETS FOUND" permanently. User thinks there is no local news when the real problem is parsing failure. The dashboard looks broken for its primary purpose. Worse: stale data from a previous successful fetch may persist, showing week-old headlines with no indication they are outdated.

**Prevention:**
- Replace grep-based RSS extraction with Python's `xml.etree.ElementTree` or `feedparser` library for all RSS sources. The project already embeds Python for JSON processing (lines 322-345 of `news-fetcher.sh`), so this is consistent with the existing stack constraint.
- If staying pure-bash, use `xmllint --xpath` which properly handles CDATA, namespaces, and entity encoding.
- Add a per-source item count check: if a source returns zero items, log a warning and retain previous cached items for that source.
- Add a "freshness" indicator to meta.json per source, not just globally.

**Detection:**
- Dashboard local/state categories show "NO TARGETS FOUND" or "Scanning..." despite news-fetcher.sh completing without error.
- `wc -l < news.json` returns a suspiciously low number.
- Run `curl -s "https://www.walb.com/rss" | grep -oP '<title>\K[^<]+'` manually -- if it returns nothing but the page clearly has content, the regex is the problem.

**Phase:** Address in Phase 1 (news pipeline repair). This is the foundational issue.

---

### Pitfall 2: better-sqlite3 to sqlite3 Migration Is Not a Drop-In Swap

**What goes wrong:** FaceBot's `server.ts` imports `better-sqlite3` (line 6: `import sqlite3 from 'better-sqlite3'`) but `package.json` already lists `sqlite3` (the async version). The code uses `better-sqlite3`'s synchronous API throughout: `db.exec()`, `db.prepare().run()`, `db.prepare().all()`, `db.prepare().get()`. The `sqlite3` npm package has a completely different, callback-based async API. Simply changing the import produces type errors on every database call. Every single database operation in the file needs to be rewritten.

**Why it happens:** `better-sqlite3` and `sqlite3` are not interchangeable despite similar names. `better-sqlite3` is synchronous (returns values directly), while `sqlite3` uses Node.js callbacks (`db.all(sql, params, (err, rows) => {...})`). The migration requires wrapping every DB call in Promises or using a promisify wrapper, then converting every route handler to async/await. The Express route handlers on lines 60-112 currently return synchronous results -- they all need `async (req, res) => {}` signatures and `await` on every DB call.

**Consequences:** If you just change the import from `better-sqlite3` to `sqlite3`, the server will not compile. TypeScript will emit 10+ type errors. If you bypass TypeScript and run it with `ts-node` ignoring errors, the routes will return `undefined` to clients because `db.prepare().all()` returns void in `sqlite3` (the result comes via callback). The dashboard chat panel will show empty data or errors.

**Prevention:**
- Create a `db.ts` module that wraps `sqlite3` in a Promise-based interface matching the method signatures FaceBot currently uses. This isolates the migration to one file:
  ```typescript
  // db.ts
  import sqlite3 from 'sqlite3';
  import { promisify } from 'util';
  // Export: db.run(), db.all(), db.get() as async functions
  ```
- Convert each Express route handler to `async` one at a time, testing after each conversion.
- Alternative: use `better-sqlite3` if the native compilation issue can be resolved (`npm rebuild`). The native build failure is often a missing `python3` or `node-gyp` issue, not a fundamental incompatibility.

**Detection:**
- `npm start` or `ts-node src/server.ts` produces compilation errors referencing `.prepare()` or `.exec()`.
- Server starts but API endpoints return empty responses or `Cannot read property 'id' of undefined`.
- FaceBot logs show "db is not a function" or "db.prepare is not a function" errors.

**Phase:** Address in Phase 2 (FaceBot repair). Must be completed before Phase 3 (chat wiring).

---

### Pitfall 3: XSS via innerHTML in Chat Panel

**What goes wrong:** The dashboard's `postChat()` function (line 506 of `index.html`) uses `innerHTML` to render user input directly into the DOM: `div.innerHTML = '<span class="chat-user"...>PLAYER 1:</span> ' + input.value`. The `loadChat()` function (line 488) also renders backend messages with `innerHTML`: `${msg.message}`. Once the BotSpace panel is connected to a real backend, any message containing `<script>` or `<img onerror=...>` will execute arbitrary JavaScript.

**Why it happens:** The chat panel was built as a UI stub (line 509: `// TODO: Send to backend API`). When it only showed hardcoded messages and local-only input, XSS was not a risk. But once wired to FaceBot's `/api/feed` endpoint, any agent post containing HTML will be rendered as HTML, not text.

**Consequences:** A malicious or malformed post from any FaceBot agent (or a future integration) could inject scripts into the dashboard. In a localhost-only context, the blast radius is limited to Tripp's browser session. But it could still read localStorage, redirect to phishing pages, or break the dashboard UI by injecting mismatched HTML tags. More practically: agent posts with `<` or `>` characters (common in tech discussions) will be interpreted as HTML and silently eaten.

**Prevention:**
- Replace all `innerHTML` assignments for user/agent content with `textContent` for plain text, or use a sanitization function:
  ```javascript
  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
  ```
- Apply escaping in both `postChat()` (local input) and `loadChat()` (backend messages).
- On the FaceBot side, sanitize content before storing in SQLite: strip HTML tags or entity-encode on write.

**Detection:**
- Post a message containing `<b>test</b>` in the chat panel. If "test" appears bold instead of showing the literal tags, innerHTML is rendering unsanitized.
- Post a message containing `<script>alert(1)</script>`. If an alert fires, XSS is confirmed.

**Phase:** Address in Phase 3 (chat wiring). Must be fixed before connecting to live backend.

---

### Pitfall 4: Local News Stations May Not Have RSS Feeds At All

**What goes wrong:** The project assumes Albany Herald, WALB, and WTXL provide standard RSS feeds that can be fetched and parsed. Many local TV station and newspaper websites (especially those run by media conglomerates like Gray Television, which owns WALB) have removed or never provided RSS feeds. The Albany Herald is owned by Lee Enterprises, which has historically been inconsistent about RSS availability. WTXL is a Scripps station. Even when feeds exist, they may be behind Cloudflare bot protection that blocks curl requests.

**Why it happens:** RSS adoption has declined since the mid-2010s. Local news stations often rely on social media distribution instead. Corporate media groups frequently disable RSS during site redesigns or CMS migrations. The `news-fetcher.sh` assumption that "all news sources provide RSS" worked for national sources (NPR, CBS, Fox all maintain feeds) but does not hold for small-market local stations.

**Consequences:** If you add WALB/Albany Herald/WTXL as RSS sources and they do not provide feeds (or their feeds are blocked), the local news section returns zero results. The user's primary use case -- local Albany news -- fails completely. The fallback Google News RSS search for "Albany+Georgia" already exists but produces generic/low-relevance results (often picking up Albany, New York or other Albanys).

**Prevention:**
- Before writing any code, manually verify each source's feed availability:
  ```bash
  curl -s -o /dev/null -w "%{http_code}" "https://www.walb.com/rss"
  curl -s -o /dev/null -w "%{http_code}" "https://www.albanyherald.com/search/?f=rss"
  ```
- Have a tiered fallback strategy:
  1. Direct RSS feed (best)
  2. Google News RSS filtered to `site:walb.com` (e.g., `q=site:walb.com+Albany`)
  3. HTML scraping of the station's homepage headlines (last resort, most fragile)
- Use Google News site-restricted search as the reliable fallback: `https://news.google.com/rss/search?q=site:walb.com&hl=en-US&gl=US&ceid=US:en`
- Implement source health tracking: if a source fails 3 times consecutively, log a warning and fall back to alternative.

**Detection:**
- `curl -v` to the feed URL returns 403 (Cloudflare), 404 (no feed), or 301 redirect to the homepage.
- Response Content-Type is `text/html` instead of `application/rss+xml` or `application/xml`.
- Response contains `<html>` instead of `<rss>` or `<feed>`.

**Phase:** Address in Phase 1 (news pipeline repair). Verify feed availability before writing code.

## Moderate Pitfalls

### Pitfall 5: uuid Dependency Missing from FaceBot package.json

**What goes wrong:** `server.ts` imports `uuid` on line 7 (`import { v4 as uuidv4 } from 'uuid'`) but `uuid` is not listed in `package.json` dependencies. The server will crash on startup with `Cannot find module 'uuid'` after a fresh `npm install`.

**Prevention:** Either add `uuid` to package.json (`npm install uuid @types/uuid`) or replace with `crypto.randomUUID()` which is built into Node.js 19+ and requires no external dependency. The latter is simpler and aligns with reducing dependencies.

**Detection:** `npm start` fails with module-not-found error for `uuid`. Check package.json dependencies against actual imports.

**Phase:** Address in Phase 2 (FaceBot repair) alongside the sqlite3 migration.

---

### Pitfall 6: Concurrent JSON File Writes Corrupt Dashboard Data

**What goes wrong:** `news-fetcher.sh` writes to `news.json` while `system-stats.sh` writes to `stats.json` in the same `news-cache/` directory. More critically, the news-fetcher overwrites `news.json` atomically from Python (`json.dump` on line 334), but if the dashboard's JavaScript `fetch()` reads the file mid-write, it gets a partial/corrupt JSON file, causing `JSON.parse` to throw. The dashboard catches this (`catch(e)`) but shows stale data with no indication the fetch failed.

**Why it happens:** The refresh loop in `launch.sh` runs stats every 30s and news every 2 minutes. These are independent processes with no coordination. Python's `json.dump` writes directly to the target file without using a temp-file-then-rename pattern.

**Prevention:**
- Write to a temp file first, then atomically rename:
  ```bash
  python3 -c "... json.dump(items, open('$NEWS_JSON.tmp', 'w')) ..."
  mv "$NEWS_JSON.tmp" "$NEWS_JSON"
  ```
  `mv` on the same filesystem is atomic on Linux.
- Add a "last_updated" timestamp comparison in the dashboard JavaScript: if the displayed timestamp is more than 5 minutes old, show a stale-data warning.

**Detection:**
- Intermittent "Scanning..." or empty news categories that resolve on the next refresh cycle.
- Browser console shows `SyntaxError: Unexpected end of JSON input` from the `news.json` fetch.

**Phase:** Address in Phase 1 (news pipeline repair) as part of the robustness improvements.

---

### Pitfall 7: Chat Polling Creates Unnecessary Load When Backend Is Down

**What goes wrong:** The `loadChat()` function in `index.html` (lines 478-495) is designed to fetch from `news-cache/feedback.json` every 5 seconds (line 518, currently commented out). Once wired to FaceBot at `localhost:4000/api/feed`, if FaceBot is not running, the dashboard will make a failed HTTP request every 5 seconds indefinitely. The browser console fills with CORS/network errors, and the failed requests may slow down other fetches due to browser connection pool limits.

**Prevention:**
- Implement exponential backoff: if a fetch fails, double the interval (5s -> 10s -> 20s -> 60s max). Reset on success.
- Add a connection status indicator in the BotSpace panel header: "ONLINE" (green) vs "OFFLINE" (red).
- Check if FaceBot is running before enabling the chat polling loop. A simple initial fetch with a 2-second timeout determines if polling should start.
- Consider using Server-Sent Events (SSE) instead of polling for real-time chat. FaceBot can push new posts to connected clients. This eliminates polling overhead entirely.

**Detection:**
- Browser DevTools Network tab shows repeated failed requests to `localhost:4000` every 5 seconds.
- Dashboard becomes sluggish after running for an hour with FaceBot offline.

**Phase:** Address in Phase 3 (chat wiring). Build the polling with backoff from the start.

---

### Pitfall 8: CORS Blocking Between Dashboard (port 8787) and FaceBot (port 4000)

**What goes wrong:** The dashboard at `http://localhost:8787` makes fetch requests to FaceBot at `http://localhost:4000/api/feed`. These are cross-origin requests (different ports = different origins). FaceBot does include `cors()` middleware (line 55 of `server.ts`), but the default `cors()` configuration allows all origins -- which works. However, if CORS middleware is misconfigured during the migration, or if `cors` is removed/changed, all dashboard-to-FaceBot requests will fail silently (fetch resolves but response is opaque/empty).

**Why it happens:** CORS errors in JavaScript do not throw catchable errors -- the fetch promise resolves with an opaque response, and the `.json()` call fails with a generic parse error. Developers often debug this for hours thinking the API is broken when the issue is a missing header.

**Prevention:**
- Keep `app.use(cors())` in FaceBot. Verify with:
  ```bash
  curl -v -H "Origin: http://localhost:8787" http://localhost:4000/api/feed
  # Check for: Access-Control-Allow-Origin: *
  ```
- In the dashboard fetch calls, add explicit error detection:
  ```javascript
  const res = await fetch('http://localhost:4000/api/feed');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  ```
- Test CORS before building any dashboard integration. If it fails, fix server-side first.

**Detection:**
- Browser console shows: `Access to fetch at 'http://localhost:4000/...' from origin 'http://localhost:8787' has been blocked by CORS policy`.
- FaceBot API works fine with `curl` but fails from the dashboard.

**Phase:** Address at the start of Phase 3 (chat wiring). Verify CORS before writing integration code.

---

### Pitfall 9: Drudge Report HTML Scraping Is the Most Fragile Source

**What goes wrong:** The Drudge Report fetch (lines 147-154 of `news-fetcher.sh`) scrapes HTML, not RSS. The regex `grep -oP 'href="[^"]+">([A-Z][A-Z\s]+)</a>'` looks for all-caps links. Drudge Report changes its HTML layout periodically, and the site has no stable API or RSS feed. Any HTML structure change (different tag nesting, class attributes, JavaScript rendering) breaks this completely.

**Prevention:**
- Accept that Drudge will break periodically. Wrap it with the same zero-result detection as other sources.
- Consider removing Drudge from the automated pipeline and replacing with a more reliable conservative news RSS source (e.g., Washington Examiner RSS, which is reliably available: `https://www.washingtonexaminer.com/section/news/feed`).
- If keeping Drudge, use a Python-based HTML parser (`BeautifulSoup`) instead of grep, which can handle structural changes more gracefully.

**Detection:**
- Drudge category returns zero items while site is clearly online.
- `curl -s "https://www.drudgereport.com/" | grep -oP 'href="[^"]+">([A-Z][A-Z\s]+)</a>'` returns empty.

**Phase:** Opportunistic fix during Phase 1 (news pipeline repair).

## Minor Pitfalls

### Pitfall 10: Dead Python Heredoc Block in news-fetcher.sh

**What goes wrong:** Lines 282-319 of `news-fetcher.sh` contain a Python heredoc block that is never executed (the shell variables `$TEMP_FILE` and `$NEWS_JSON` are not expanded inside a single-quoted heredoc). The actual working Python code is on lines 322-345. This dead code causes confusion when debugging.

**Prevention:** Delete lines 282-319 entirely. The CONCERNS.md already identifies this (documented there as "Python Syntax Error"). Remove it during the first code touch to reduce confusion.

**Detection:** The heredoc Python block references `sys.argv` but is never passed arguments.

**Phase:** Quick fix during Phase 1 cleanup.

---

### Pitfall 11: News Item URLs Often Point to Generic Homepage Instead of Article

**What goes wrong:** Many `add_item` calls use the source homepage as the URL instead of the actual article link (e.g., line 126: `"https://www.cbsnews.com"`, line 133: `"https://www.nbcnews.com"`). The `grep -oP` pattern only extracts `<title>` content, not the corresponding `<link>` element. Users click a headline and land on the CBS homepage, not the article.

**Prevention:**
- Extract both `<title>` and `<link>` from RSS feeds together. With Python XML parsing, this is trivial:
  ```python
  for item in root.findall('.//item'):
      title = item.find('title').text
      link = item.find('link').text
  ```
- With grep, extract links in parallel with titles (fragile but possible):
  ```bash
  paste <(grep -oP '<title>\K[^<]+') <(grep -oP '<link>\K[^<]+')
  ```

**Detection:** Click any news headline in the dashboard. If it goes to a generic homepage instead of the article, URLs are not being extracted.

**Phase:** Address in Phase 1 (news pipeline repair). Significant UX improvement.

---

### Pitfall 12: activitypub-express Dependency in FaceBot Is Unused and May Block Install

**What goes wrong:** `package.json` lists `activitypub-express` as a dependency, but `server.ts` does not import or use it. This package may have its own native dependencies or version conflicts that cause `npm install` to fail, blocking the entire FaceBot setup even though the package is not needed.

**Prevention:** Remove `activitypub-express` from `package.json` since it is not imported. The ActivityPub endpoints in `server.ts` (lines 97-112) are implemented manually without this library. Re-add it later if federation is actually needed.

**Detection:** `npm install` fails or warns about `activitypub-express` peer dependency conflicts.

**Phase:** Address in Phase 2 (FaceBot repair) during dependency cleanup.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Phase 1: News Pipeline Repair | Local station RSS feeds do not exist or are behind Cloudflare | Manually verify each URL with curl before writing parsing code. Have Google News `site:` fallback ready. |
| Phase 1: News Pipeline Repair | grep-based parsing silently returns zero items on CDATA/minified feeds | Switch to Python XML parser. Add per-source item count validation. |
| Phase 1: News Pipeline Repair | Article URLs point to homepage, not article | Extract `<link>` elements alongside `<title>` during RSS parsing rewrite. |
| Phase 2: FaceBot Repair | sqlite3 async API requires rewrite of every DB call, not just import change | Create a Promise-wrapper module in `db.ts`. Convert routes to async one at a time. |
| Phase 2: FaceBot Repair | Missing `uuid` dependency crashes server on startup | Add to package.json or replace with `crypto.randomUUID()`. |
| Phase 2: FaceBot Repair | `activitypub-express` may block npm install | Remove unused dependency from package.json. |
| Phase 3: Chat Wiring | innerHTML XSS when rendering backend messages | Use textContent or escapeHtml() for all dynamic content. |
| Phase 3: Chat Wiring | CORS blocks cross-origin requests between ports 8787 and 4000 | Verify CORS headers with curl before writing fetch code. |
| Phase 3: Chat Wiring | Polling without backoff hammers a down server every 5 seconds | Implement exponential backoff from the start. Add connection status indicator. |

## Sources

- Direct code analysis: `/home/tripp/Documents/radio-free-albany/dashboard/news-fetcher.sh` (350 lines)
- Direct code analysis: `/home/tripp/Documents/radio-free-albany/dashboard/index.html` (527 lines)
- Direct code analysis: `/home/tripp/Documents/facebot/src/server.ts` (117 lines)
- Direct code analysis: `/home/tripp/Documents/facebot/package.json` (24 lines)
- Existing codebase audit: `/home/tripp/Documents/radio-free-albany/.planning/codebase/CONCERNS.md`
- Existing integration map: `/home/tripp/Documents/radio-free-albany/.planning/codebase/INTEGRATIONS.md`
- Project context: `/home/tripp/Documents/radio-free-albany/.planning/PROJECT.md`
- Confidence: HIGH for code-level pitfalls (direct analysis), MEDIUM for local news RSS availability (unable to verify live URLs due to tool restrictions)

---

*Pitfalls audit: 2026-02-08*

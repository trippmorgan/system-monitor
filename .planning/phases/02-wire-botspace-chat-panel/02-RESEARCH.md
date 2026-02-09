# Phase 2: Wire BotSpace Chat Panel - Research

**Researched:** 2026-02-09
**Domain:** Vanilla JavaScript fetch API, cross-origin polling, XSS prevention, chat UI patterns
**Confidence:** HIGH

## Summary

Phase 2 wires the existing BotSpace chat panel in `dashboard/index.html` to the FaceBot REST API at `localhost:4000`. The dashboard already contains all the HTML structure, CSS styling, and JavaScript scaffolding needed -- the `loadChat()` function, `postChat()` function, chat input field, and SEND button all exist. The work is entirely about replacing placeholder/stub code with real fetch calls, adding XSS protection, implementing error states, and enabling the polling interval.

The FaceBot API (fixed in Phase 1) provides two relevant endpoints: `GET /api/feed` returns a JSON array of posts with fields `{id, agent_id, content, type, parent_id, created_at, username, name, icon}`, and `POST /api/post` accepts `{username, content, type?, parent_id?}` and returns `{success: true, id}`. CORS is enabled via `app.use(cors())` which defaults to `Access-Control-Allow-Origin: *`, meaning cross-origin fetch from port 8787 to port 4000 will work without additional server configuration.

The primary technical risks are XSS via innerHTML (the current code interpolates message content directly into HTML), polling a down server every 5 seconds without backoff, and silent CORS failures that are hard to debug. All three have well-established vanilla JavaScript solutions documented below.

**Primary recommendation:** Rewrite `loadChat()` to fetch from `http://localhost:4000/api/feed`, rewrite `postChat()` to POST to `http://localhost:4000/api/post`, add an `escapeHtml()` utility function, implement exponential backoff on fetch failure, and uncomment the 5-second polling interval.

## Standard Stack

### Core

This phase modifies only `dashboard/index.html`. No new libraries, packages, or dependencies.

| Technology | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Vanilla JavaScript (ES6+) | Browser native | All chat logic (fetch, DOM manipulation, polling) | Project constraint: no frameworks, no npm in dashboard |
| Fetch API | Browser native | HTTP requests to FaceBot at localhost:4000 | Standard browser API, already used by loadArcadeData() |
| Python http.server | Python 3.x stdlib | Serves dashboard at localhost:8787 | Existing infrastructure, no changes needed |
| NES.css | 2.3.0 (CDN) | Retro styling for chat input and buttons | Already loaded in index.html |

### Supporting

No supporting libraries needed. Everything is achievable with browser-native APIs.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Polling every 5s | WebSocket / Server-Sent Events | Overengineered for single-user localhost dashboard. Would require FaceBot server changes. Polling is explicitly the chosen approach per FEATURES.md anti-features list. |
| Manual escapeHtml() | DOMPurify library | Adds a CDN dependency for a problem solvable in 5 lines. DOMPurify is appropriate for rich HTML sanitization but this is plain-text-only chat. |
| setInterval polling | requestAnimationFrame loop | setInterval is simpler and appropriate for 5-second intervals. rAF is for frame-rate-sensitive operations. |

**Installation:** None required. All changes are within `dashboard/index.html`.

## Architecture Patterns

### Existing Structure (No Changes)

```
dashboard/
  index.html          # THE ONLY FILE TO MODIFY (contains all JS inline)
  launch.sh           # Starts HTTP server on port 8787 (no changes)
  stop.sh             # Stops server (no changes)
  news-cache/         # Existing JSON cache dir (no changes)

~/Documents/facebot/  # SEPARATE REPO - Phase 1 already fixed this
  src/server.ts       # FaceBot API at localhost:4000 (no changes in this phase)
```

### Pattern 1: Fetch with Error State Display

**What:** Replace silent catch blocks with visible offline indicators
**When to use:** Any cross-origin fetch that may fail (server down, CORS error, network issue)
**Example:**

```javascript
// Source: MDN Fetch API docs + OWASP XSS Prevention
const FACEBOT_URL = 'http://localhost:4000';

async function loadChat() {
    try {
        const res = await fetch(FACEBOT_URL + '/api/feed');
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const messages = await res.json();

        // Reset backoff on success
        chatBackoff = 5000;

        const feed = document.getElementById('botspace-feed');
        if (messages.length === 0) {
            feed.innerHTML = '<div class="chat-msg"><span class="chat-user">SYSTEM:</span> No messages yet. Say something!</div>';
            return;
        }

        // Render messages with XSS prevention
        feed.innerHTML = messages.reverse().map(msg => `
            <div class="chat-msg ${msg.type === 'Alert' ? 'alert' : ''}">
                <span class="chat-user">${escapeHtml(msg.name || msg.username)}:</span> ${escapeHtml(msg.content)}
            </div>
        `).join('');

        feed.scrollTop = feed.scrollHeight;
    } catch(e) {
        // Show offline state
        document.getElementById('botspace-feed').innerHTML =
            '<div class="chat-msg alert"><span class="chat-user">SYSTEM:</span> FACEBOT OFFLINE</div>';

        // Exponential backoff
        chatBackoff = Math.min(chatBackoff * 2, 60000);
    }
}
```

### Pattern 2: XSS-Safe HTML Escaping

**What:** Prevent script injection when rendering user/agent content
**When to use:** Any time external data is placed into innerHTML
**Example:**

```javascript
// Source: OWASP DOM-based XSS Prevention Cheat Sheet
function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}
```

This uses the browser's own text-to-HTML encoding. It converts `<script>` to `&lt;script&gt;`, `"` to `&quot;`, etc. It is the standard pattern recommended by OWASP for vanilla JavaScript when you need escaped HTML strings for template literals. Using `textContent` directly is preferred when you control the entire element, but for cases where you build HTML strings with template literals (as this codebase does), `escapeHtml()` is the correct approach.

### Pattern 3: Exponential Backoff Polling

**What:** Increase poll interval after failures to avoid hammering a down server
**When to use:** Any polling loop that targets a potentially unavailable service
**Example:**

```javascript
// Source: Standard exponential backoff pattern
let chatBackoff = 5000;  // Start at 5 seconds
let chatTimer = null;

function scheduleChatPoll() {
    chatTimer = setTimeout(async () => {
        await loadChat();
        scheduleChatPoll();
    }, chatBackoff);
}

// In loadChat():
// On success: chatBackoff = 5000 (reset to normal)
// On failure: chatBackoff = Math.min(chatBackoff * 2, 60000) (double up to 60s max)
```

Using `setTimeout` recursively instead of `setInterval` is important here because `setInterval` does not account for the time the fetch takes, and does not allow dynamic interval adjustment.

### Pattern 4: POST with Optimistic Update

**What:** Show the user's message immediately while the POST is in flight
**When to use:** Chat-style interfaces where responsiveness matters
**Example:**

```javascript
// Source: Standard optimistic UI pattern
async function postChat() {
    const input = document.getElementById('chat-input');
    const content = input.value.trim();
    if (!content) return;

    // Optimistic: show message immediately
    const feed = document.getElementById('botspace-feed');
    const div = document.createElement('div');
    div.className = 'chat-msg';
    const userSpan = document.createElement('span');
    userSpan.className = 'chat-user';
    userSpan.style.color = '#209cee';
    userSpan.textContent = 'TRIPP:';
    div.appendChild(userSpan);
    div.appendChild(document.createTextNode(' ' + content));
    feed.appendChild(div);
    feed.scrollTop = feed.scrollHeight;

    input.value = '';

    // Fire and forget POST
    try {
        const res = await fetch(FACEBOT_URL + '/api/post', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: 'tripp', content: content })
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
    } catch(e) {
        // Mark message as failed
        div.style.borderLeftColor = '#e76e55';
        div.appendChild(document.createTextNode(' [SEND FAILED]'));
    }
}
```

Note: The optimistic message will be replaced on the next poll cycle when the server's version appears in `/api/feed`. This creates a brief duplicate, but it is visually acceptable and standard for chat UIs.

### Anti-Patterns to Avoid

- **innerHTML with user content:** Never `innerHTML = ... + userInput + ...`. Always use `escapeHtml()` or build DOM nodes with `textContent`. The existing `postChat()` does exactly this wrong thing.
- **setInterval for polling a potentially-down service:** `setInterval(loadChat, 5000)` cannot adjust timing on failure. Use recursive `setTimeout` with backoff.
- **Swallowing fetch errors silently:** The existing `loadChat()` has an empty `catch(e) {}` block. Always display an error state to the user.
- **Checking CORS by reading response headers in JS:** CORS failures are opaque to JavaScript -- the browser blocks the response entirely. You cannot detect "this failed because of CORS" vs "server is down" in code. Both manifest as a TypeError from `fetch()`. Test CORS with `curl -v -H "Origin: http://localhost:8787"` from the command line instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTML entity encoding | Custom regex replacement for <, >, &, " | `escapeHtml()` via `textContent`/`innerHTML` round-trip | Regex approaches miss edge cases (backticks, null bytes, Unicode). The DOM-based approach uses the browser's own encoder. |
| Polling timer management | Manual `clearInterval`/`setInterval` swapping | Recursive `setTimeout` with a closure variable | Simpler, naturally supports dynamic intervals, avoids overlapping calls if fetch takes > 5 seconds |
| CORS configuration | Custom headers on fetch requests | FaceBot's existing `cors()` middleware (default `*` origin) | The server already handles CORS. Adding `mode: 'cors'` to fetch is redundant (it is the default). Don't add credentials or custom headers that would trigger preflight. |

**Key insight:** This phase has zero new dependencies. Every requirement is solvable with `fetch()`, `document.createElement()`, `textContent`, and `setTimeout`. The temptation to add complexity (WebSockets, DOMPurify, a polling library) should be resisted.

## Common Pitfalls

### Pitfall 1: innerHTML XSS in Chat Rendering

**What goes wrong:** Current `loadChat()` uses template literals with `innerHTML`, rendering message content as HTML. Current `postChat()` also uses `innerHTML` with `input.value`. Any message containing `<script>`, `<img onerror=...>`, or even innocent `<b>tags</b>` will be interpreted as HTML.
**Why it happens:** The code was originally a UI stub with hardcoded messages. XSS was not a risk with static content.
**How to avoid:** Add `escapeHtml()` function. Apply to ALL dynamic content in chat rendering: `msg.content`, `msg.name`, `msg.username`. For `postChat()`, switch to DOM node construction with `textContent` (as shown in Pattern 4 above).
**Warning signs:** Post `<b>test</b>` in chat. If "test" appears bold, XSS is active. This is explicitly success criterion #4.

### Pitfall 2: Silent CORS Failure

**What goes wrong:** If FaceBot's CORS middleware is misconfigured or removed, fetch from port 8787 to port 4000 fails silently. The fetch promise rejects with a TypeError, but the error message is deliberately vague for security reasons. The developer sees "Failed to fetch" and doesn't know if the server is down or CORS is blocking.
**Why it happens:** Browser CORS security intentionally hides details from JavaScript.
**How to avoid:** Before writing any dashboard fetch code, verify CORS with: `curl -v -H "Origin: http://localhost:8787" http://localhost:4000/api/feed` and check for `Access-Control-Allow-Origin: *` in response headers. FaceBot uses `app.use(cors())` which defaults to `*`, so this should work. But verify, don't assume.
**Warning signs:** `loadChat()` catch block fires, but `curl http://localhost:4000/api/feed` works fine from terminal. This means CORS is the issue, not the server.

### Pitfall 3: Polling a Down Server Every 5 Seconds

**What goes wrong:** If FaceBot is not running, the dashboard fires a failed fetch every 5 seconds forever. The browser console fills with errors. With `setInterval`, these pile up and cannot be slowed down.
**Why it happens:** `setInterval` fires at a fixed rate regardless of success/failure.
**How to avoid:** Use recursive `setTimeout` with exponential backoff (5s -> 10s -> 20s -> 40s -> 60s cap). Reset to 5s on first successful fetch. Display "FACEBOT OFFLINE" during backoff.
**Warning signs:** Browser DevTools network tab shows repeating red failed requests to localhost:4000 every 5 seconds.

### Pitfall 4: Feed Order Assumption

**What goes wrong:** FaceBot's `GET /api/feed` returns posts ordered `DESC` (newest first) with `LIMIT 50`. The dashboard chat should display oldest-at-top, newest-at-bottom (standard chat order). If you render the array directly, newest messages appear at the top, which is confusing for a chat panel.
**Why it happens:** FaceBot orders by `created_at DESC` (line 76 of server.ts). This is correct for a "feed" (like Twitter) but wrong for a "chat" (like Slack).
**How to avoid:** Reverse the array before rendering: `messages.reverse()`. Or use `.slice(-N).reverse()` if you want to limit displayed messages.
**Warning signs:** Most recent message appears at the top of the BotSpace panel instead of the bottom.

### Pitfall 5: Auto-Scroll Overriding User Scroll Position

**What goes wrong:** Setting `feed.scrollTop = feed.scrollHeight` every 5 seconds snaps the view to the bottom even when the user has scrolled up to read older messages.
**Why it happens:** The auto-scroll fires unconditionally on every poll cycle.
**How to avoid:** Before updating, check if user is already at (or near) the bottom: `const isAtBottom = feed.scrollHeight - feed.scrollTop - feed.clientHeight < 50;`. Only auto-scroll if `isAtBottom` is true. This is a nice-to-have since success criterion #5 only requires auto-scroll on new messages (not preventing scroll-up), but it is worth implementing for UX.
**Warning signs:** User scrolls up to read chat history and gets snapped back to bottom every 5 seconds.

### Pitfall 6: Optimistic Update Duplication

**What goes wrong:** `postChat()` adds a message optimistically to the DOM. The next poll cycle fetches the same message from the server and adds it again. User sees their message twice briefly.
**Why it happens:** The optimistic DOM node and the server-fetched node are rendered independently.
**How to avoid:** This is acceptable behavior for a 5-second poll interval on a personal dashboard. The `loadChat()` function replaces the entire `innerHTML` of the feed on each poll, so the duplicate disappears on the next successful fetch (the optimistic node is overwritten). No special deduplication logic is needed -- the full-replace rendering approach handles it naturally.
**Warning signs:** A message appears twice for up to 5 seconds after sending. This is expected and acceptable.

## Code Examples

### Complete escapeHtml Utility

```javascript
// Source: OWASP DOM-based XSS Prevention Cheat Sheet
// Uses browser's own text encoding -- handles all HTML special characters
function escapeHtml(str) {
    if (str == null) return '';
    const div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML;
}
```

### FaceBot API Response Shape

From direct analysis of `/home/tripp/Documents/facebot/src/server.ts` (lines 71-82):

```javascript
// GET /api/feed returns array of:
[
  {
    "id": "uuid-string",
    "agent_id": "uuid-string",
    "content": "Message text",
    "type": "Note",           // or "Alert"
    "parent_id": null,
    "created_at": "2026-02-09 12:34:56",
    "username": "firstofficer",
    "name": "First Officer",
    "icon": "pointing-satellite-dish-emoji"
  }
]

// POST /api/post request body:
{ "username": "tripp", "content": "Hello world" }

// POST /api/post response:
{ "success": true, "id": "uuid-string" }

// POST /api/post error (agent not found):
{ "error": "Agent not found" }  // HTTP 404
```

### Enter Key Submission

```javascript
// Allow Enter key to send chat messages (standard chat UX)
document.getElementById('chat-input').addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        postChat();
    }
});
```

## State of the Art

| Old Approach (current code) | Current Approach (what to implement) | Why Change |
|---------------------------|-------------------------------------|------------|
| `loadChat()` fetches from `news-cache/feedback.json` | Fetch from `http://localhost:4000/api/feed` | FaceBot is the real data source; feedback.json was a placeholder |
| `postChat()` has `// TODO: Send to backend API` | POST to `http://localhost:4000/api/post` with `{username: 'tripp', content}` | Phase 1 fixed FaceBot, so the backend now exists |
| `innerHTML` with raw `msg.message` | `escapeHtml()` on all dynamic content | Prevents XSS once connected to live backend |
| Empty `catch(e) {}` on fetch failure | Display "FACEBOT OFFLINE" with red alert styling | User needs feedback when server is down |
| `setInterval(loadChat, 5000)` (commented out) | Recursive `setTimeout` with exponential backoff | Prevents hammering a down server |
| User shown as "PLAYER 1" | User shown as "TRIPP" (matching FaceBot username) | Consistency with FaceBot agent name |

## FaceBot API Contract (Phase 1 Output)

This is the exact API surface verified during Phase 1 completion. Phase 2 depends on these being stable.

| Endpoint | Method | Request | Response | Verified |
|----------|--------|---------|----------|----------|
| `/api/feed` | GET | (none) | `[{id, agent_id, content, type, parent_id, created_at, username, name, icon}]` | Yes (Phase 1) |
| `/api/post` | POST | `{username, content, type?, parent_id?}` | `{success: true, id}` | Yes (Phase 1) |
| `/api/agent/:username` | GET | (none) | `{id, username, name, icon}` | Yes (Phase 1) |

**CORS:** `app.use(cors())` with default config = `Access-Control-Allow-Origin: *`. Verified in source code (line 66 of server.ts).

**Port:** Default 4000, configurable via PORT env. Note from Phase 1 verification: port 4000 may be occupied by another process on this system. Dashboard code should use a configurable constant, not a hardcoded URL.

## Open Questions

1. **Port 4000 availability**
   - What we know: Phase 1 verification found port 4000 occupied by another process. FaceBot tested on port 4001. Server code defaults to 4000 but reads PORT env.
   - What's unclear: Whether port 4000 has been freed since Phase 1 completion.
   - Recommendation: Define FACEBOT_URL as a constant at the top of the script section (`const FACEBOT_URL = 'http://localhost:4000'`). If the port changes, only one line needs updating. The planner should include a CORS verification step that also confirms the actual port.

2. **Message field naming: `msg.message` vs `msg.content`**
   - What we know: The existing `loadChat()` stub references `msg.message` (line 488 of index.html). FaceBot returns `msg.content` (from the `content` column in the posts table).
   - What's unclear: Nothing -- this is definitely a bug in the stub code.
   - Recommendation: Use `msg.content` to match the FaceBot API response. Also use `msg.username` and `msg.name` instead of `msg.user`.

3. **Feed message limit**
   - What we know: FaceBot returns up to 50 messages (`LIMIT 50`). The old stub displayed last 10 (`.slice(-10)`).
   - What's unclear: Whether 50 messages will render well in the 300px-tall chat panel.
   - Recommendation: Display all 50. The panel has `overflow-y: auto` (scrollable), so rendering all messages is fine. Users can scroll up. If performance becomes an issue, slice to last 20, but 50 is not a concern.

## Sources

### Primary (HIGH confidence)
- Direct code analysis of `/home/tripp/Documents/radio-free-albany/dashboard/index.html` (527 lines) -- current BotSpace implementation
- Direct code analysis of `/home/tripp/Documents/facebot/src/server.ts` (119 lines) -- FaceBot API endpoints and CORS setup
- Direct code analysis of `/home/tripp/Documents/facebot/package.json` -- confirmed cors dependency present
- Phase 1 summary at `/home/tripp/Documents/radio-free-albany/.planning/phases/01-fix-facebot-server/01-01-SUMMARY.md` -- API verification results
- Phase 1 verification at `/home/tripp/Documents/radio-free-albany/.planning/phases/01-fix-facebot-server/01-VERIFICATION.md` -- port 4000 issue documented
- Existing research at `/home/tripp/Documents/radio-free-albany/.planning/research/FEATURES.md` -- chat integration features analysis
- Existing research at `/home/tripp/Documents/radio-free-albany/.planning/research/PITFALLS.md` -- XSS, CORS, polling pitfalls

### Secondary (MEDIUM confidence)
- [OWASP DOM-based XSS Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/DOM_based_XSS_Prevention_Cheat_Sheet.html) -- escapeHtml pattern verification
- [MDN Fetch API docs](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch) -- fetch error handling patterns
- [Express CORS middleware docs](https://expressjs.com/en/resources/middleware/cors.html) -- default `cors()` behavior = `Access-Control-Allow-Origin: *`
- [MDN CORS guide](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS) -- cross-origin request mechanics
- [MDN Element.scrollTop](https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollTop) -- auto-scroll behavior
- [Go Make Things - XSS Prevention with innerHTML](https://gomakethings.com/preventing-cross-site-scripting-attacks-when-using-innerhtml-in-vanilla-javascript/) -- escapeHtml pattern

### Tertiary (LOW confidence)
- None. All findings verified against primary sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all browser-native APIs, verified against existing codebase
- Architecture: HIGH -- single-file modification, patterns derived from direct code analysis of both dashboard and FaceBot
- Pitfalls: HIGH -- all six pitfalls verified against actual code (line numbers referenced), three flagged in existing PITFALLS.md research
- API contract: HIGH -- verified by Phase 1 execution and verification report

**Research date:** 2026-02-09
**Valid until:** Indefinite (browser APIs and FaceBot API are stable; no fast-moving dependencies)

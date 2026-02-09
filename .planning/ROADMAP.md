# Roadmap: Radio Free Albany - Arcade Edition Upgrade

## Overview

This upgrade fixes three broken data pipelines in Radio Free Albany and verifies the arcade dashboard is operational. Phase 1 repairs the FaceBot chat server so it actually starts (sqlite3 migration, missing dependencies). Phase 2 wires the existing BotSpace UI panel to the now-running FaceBot API. Phase 3 replaces the brittle grep-based RSS parsing with proper Python XML parsing and adds local Albany, GA news sources. Phase 4 is end-to-end verification that the full dashboard works at localhost:8787.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Fix FaceBot Server** - Repair the FaceBot Express server so it starts and serves its API
- [ ] **Phase 2: Wire BotSpace Chat Panel** - Connect the dashboard chat UI to the running FaceBot API
- [ ] **Phase 3: Fix News Fetcher** - Replace grep RSS parsing with Python XML and add local Albany sources
- [ ] **Phase 4: Verify Arcade Dashboard** - End-to-end verification that all panels render at localhost:8787

## Phase Details

### Phase 1: Fix FaceBot Server
**Goal**: FaceBot server starts cleanly and serves chat data via its REST API at localhost:4000
**Depends on**: Nothing (first phase)
**Requirements**: FBOT-01, FBOT-02, FBOT-03, FBOT-04, FBOT-05
**Plans:** 1 plan
**Success Criteria** (what must be TRUE):
  1. `npm install` in ~/Documents/facebot completes with zero native compilation errors
  2. `npm start` launches FaceBot without crashes or import errors
  3. `curl http://localhost:4000/api/feed` returns a JSON array (even if empty)
  4. `curl -X POST http://localhost:4000/api/post -d '{"username":"tripp","content":"test"}' -H 'Content-Type: application/json'` returns a success response and the post appears in subsequent /api/feed calls

**Risk flags:**
- better-sqlite3 to sqlite3 is NOT a drop-in swap -- every DB call needs async/await conversion (Pitfall 2)
- `uuid` package is imported but missing from package.json -- replace with crypto.randomUUID() (Pitfall 5)
- `activitypub-express` in package.json is unused and may block npm install (Pitfall 12)

Plans:
- [x] 01-01-PLAN.md — Fix dependencies, uuid replacement, agent seeding, and startup race condition

### Phase 2: Wire BotSpace Chat Panel
**Goal**: The BotSpace panel in the dashboard displays live chat messages from FaceBot and accepts user input
**Depends on**: Phase 1 (FaceBot must be running at localhost:4000)
**Requirements**: CHAT-01, CHAT-02, CHAT-03, CHAT-04, CHAT-05
**Plans:** 1 plan
**Success Criteria** (what must be TRUE):
  1. BotSpace panel in the dashboard shows messages from FaceBot /api/feed, refreshing every 5 seconds
  2. Typing a message and clicking SEND posts it to FaceBot as user "tripp" and it appears in the feed
  3. When FaceBot is not running, BotSpace panel shows "FACEBOT OFFLINE" instead of a blank or broken panel
  4. Posting a message containing `<b>test</b>` displays the literal text, not bold formatting (XSS prevention confirmed)
  5. New messages cause the chat panel to scroll to the bottom automatically

**Risk flags:**
- innerHTML XSS when rendering backend messages -- must use escapeHtml() or textContent (Pitfall 3)
- CORS between ports 8787 and 4000 -- verify headers before writing fetch code (Pitfall 8)
- Polling without backoff hammers a down server every 5 seconds (Pitfall 7)

Plans:
- [ ] 02-01-PLAN.md — Rewrite loadChat/postChat with FaceBot API fetch, XSS prevention, backoff polling, and Enter key support

### Phase 3: Fix News Fetcher
**Goal**: The news fetcher reliably pulls local Albany, GA news from real sources and produces valid JSON with working article links
**Depends on**: Nothing (independent of Phases 1-2)
**Requirements**: NEWS-01, NEWS-02, NEWS-03, NEWS-04, NEWS-05, NEWS-06, NEWS-07
**Success Criteria** (what must be TRUE):
  1. Running `dashboard/news-fetcher.sh` produces a news.json containing items from Albany Herald, WALB, or WTXL (or their Google News fallbacks)
  2. Local news items in news.json have category "local" and include bias labels
  3. Clicking a local news headline in the dashboard opens the actual article (not a generic homepage)
  4. news.json is written atomically (via .tmp + mv) so the dashboard never reads a partial file
  5. RSS parsing handles CDATA-wrapped titles and HTML entities without garbling text
**Plans**: TBD

**Risk flags:**
- Local news stations may not have RSS feeds at all -- must verify URLs with curl before coding (Pitfall 4)
- grep-based RSS parsing breaks silently on CDATA/minified feeds -- this is why we are switching to Python XML (Pitfall 1)
- Article URLs may point to homepage instead of article if <link> extraction is missed (Pitfall 11)
- Concurrent JSON writes can corrupt dashboard data without atomic writes (Pitfall 6)

Plans:
- [ ] 03-01: Rewrite RSS parsing and add local Albany news sources

### Phase 4: Verify Arcade Dashboard
**Goal**: The full Radio Free Albany dashboard loads and renders all panels correctly at localhost:8787
**Depends on**: Phases 1, 2, 3 (all fixes must be in place for end-to-end verification)
**Requirements**: DASH-01, DASH-02, DASH-03
**Success Criteria** (what must be TRUE):
  1. `dashboard/index.html` renders with the NES.css 8-bit arcade theme (pixel fonts, retro styling visible)
  2. `dashboard/launch.sh` starts the HTTP server and refresh loop without errors, and `stop.sh` cleanly shuts both down
  3. Opening `http://localhost:8787` in a browser shows system stats, news panels, radio player, and BotSpace chat all rendering together
**Plans**: TBD

Plans:
- [ ] 04-01: End-to-end dashboard verification and smoke test

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4
(Phases 1-2 are sequential due to dependency. Phase 3 is independent but ordered here for simplicity. Phase 4 is final verification.)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Fix FaceBot Server | 1/1 | ✓ Complete | 2026-02-09 |
| 2. Wire BotSpace Chat Panel | 0/1 | Not started | - |
| 3. Fix News Fetcher | 0/1 | Not started | - |
| 4. Verify Arcade Dashboard | 0/1 | Not started | - |

---
*Roadmap created: 2026-02-08*
*Last updated: 2026-02-09 after Phase 2 planning*

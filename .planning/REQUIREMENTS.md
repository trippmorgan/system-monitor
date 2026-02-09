# Requirements: Radio Free Albany - Arcade Edition Upgrade

**Defined:** 2026-02-08
**Core Value:** Dashboard must display live local news from Albany, GA sources and system health metrics in a single browser tab with a working chat panel connected to FaceBot.

## v1 Requirements

Requirements for this upgrade cycle. Each maps to roadmap phases.

### FaceBot Server Repair

- [x] **FBOT-01**: FaceBot server starts without errors using `sqlite3` async API (not `better-sqlite3`)
- [x] **FBOT-02**: FaceBot `/api/feed` returns JSON array of posts
- [x] **FBOT-03**: FaceBot `/api/post` accepts `{username, content}` and creates a post
- [x] **FBOT-04**: FaceBot uses `crypto.randomUUID()` instead of missing `uuid` package
- [x] **FBOT-05**: FaceBot `npm install` completes without native compilation errors

### BotSpace Chat Panel

- [x] **CHAT-01**: BotSpace panel polls FaceBot `GET /api/feed` every 5 seconds
- [x] **CHAT-02**: BotSpace panel posts messages via `POST /api/post` as "tripp"
- [x] **CHAT-03**: BotSpace panel shows "FACEBOT OFFLINE" when FaceBot is unreachable
- [x] **CHAT-04**: Chat messages are rendered with XSS prevention (no raw innerHTML for user content)
- [x] **CHAT-05**: Chat panel auto-scrolls to latest message on poll update

### News Fetcher (Local Sources)

- [x] **NEWS-01**: News fetcher pulls from Albany Herald RSS feed (or Google News fallback if unavailable)
- [x] **NEWS-02**: News fetcher pulls from WALB News 10 RSS feed (or Google News fallback)
- [x] **NEWS-03**: News fetcher pulls from WTXL ABC 27 RSS feed (or Google News fallback)
- [x] **NEWS-04**: RSS parsing uses Python `xml.etree.ElementTree` instead of grep regex
- [x] **NEWS-05**: Each news item includes a working article URL (not generic homepage link)
- [x] **NEWS-06**: Local news items are categorized as `local` with appropriate bias labels
- [x] **NEWS-07**: JSON output uses atomic writes (write to .tmp, then mv)

### Dashboard Verification

- [x] **DASH-01**: `dashboard/index.html` uses NES.css arcade theme (confirmed active)
- [x] **DASH-02**: `dashboard/launch.sh` starts HTTP server and refresh loop without errors
- [x] **DASH-03**: Dashboard loads at `http://localhost:8787` and renders all panels

## v2 Requirements

Deferred to future upgrade. Tracked but not in current roadmap.

### Enhanced Features

- **ENH-01**: System alerts routed to BotSpace as chat messages from "SECURITY_BOT"
- **ENH-02**: Agent-authored status messages posted to BotSpace after each fetch cycle
- **ENH-03**: News source health dashboard showing per-source up/down status
- **ENH-04**: News deduplication across overlapping sources
- **ENH-05**: All 8 news category panels rendered (currently only 4 visible)
- **ENH-06**: Scrolling ticker populated from breaking news headlines

## Out of Scope

| Feature | Reason |
|---------|--------|
| WebSocket real-time chat | Overengineered for single-user dashboard; polling is sufficient |
| User authentication | Localhost-only personal tool; no multi-user |
| Full-text article scraping | ToS violations, complex per-site parsing, storage bloat |
| Mobile-responsive redesign | Workstation-only dashboard; NES.css pixel aesthetic is desktop-first |
| AI news sentiment analysis | Adds ML dependencies for marginal value on headlines |
| RSS feed management UI | Edit shell script directly; config changes are infrequent |
| Chat message persistence in dashboard | FaceBot already persists in SQLite; don't duplicate |
| Desktop notification sounds | Browser notification APIs are unreliable and annoying |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FBOT-01 | Phase 1 | Complete |
| FBOT-02 | Phase 1 | Complete |
| FBOT-03 | Phase 1 | Complete |
| FBOT-04 | Phase 1 | Complete |
| FBOT-05 | Phase 1 | Complete |
| CHAT-01 | Phase 2 | Complete |
| CHAT-02 | Phase 2 | Complete |
| CHAT-03 | Phase 2 | Complete |
| CHAT-04 | Phase 2 | Complete |
| CHAT-05 | Phase 2 | Complete |
| NEWS-01 | Phase 3 | Complete |
| NEWS-02 | Phase 3 | Complete |
| NEWS-03 | Phase 3 | Complete |
| NEWS-04 | Phase 3 | Complete |
| NEWS-05 | Phase 3 | Complete |
| NEWS-06 | Phase 3 | Complete |
| NEWS-07 | Phase 3 | Complete |
| DASH-01 | Phase 4 | Complete |
| DASH-02 | Phase 4 | Complete |
| DASH-03 | Phase 4 | Complete |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-02-08*
*Last updated: 2026-02-09 after Phase 4 completion — ALL REQUIREMENTS SATISFIED*

# Radio Free Albany — Arcade Edition Upgrade

## What This Is

Radio Free Albany is a personal system monitoring dashboard and local news aggregator for Tripp's Ubuntu workstation. It uses an 8-bit arcade theme (NES.css) to display system health metrics, curated news feeds across 8 categories, a live radio stream, and a BotSpace chat panel. This upgrade fixes broken data pipelines and connects the FaceBot chat server.

## Core Value

The dashboard must display live local news from Albany, GA sources and system health metrics in a single browser tab — everything Tripp needs at a glance.

## Requirements

### Validated

- ✓ System health monitoring (CPU, memory, disk, GPU, services) — existing
- ✓ Arcade-themed web dashboard with NES.css — existing
- ✓ System stats collection via shell scripts — existing
- ✓ Live radio stream player — existing
- ✓ Multi-agent architecture (System Tech, News Curator, Orchestrator) — existing
- ✓ Background refresh loop (stats every 30s, news every 2min) — existing
- ✓ Threshold-based alerting with state persistence — existing
- ✓ Process lifecycle management (launch.sh/stop.sh) — existing
- ✓ Configurable thresholds via config.sh — existing

### Active

- [ ] Fix news fetcher to pull from local Albany sources (Herald, WALB, WTXL)
- [ ] Fix FaceBot server (sqlite3 dependency, server.ts async→sync update)
- [ ] Connect BotSpace chat panel to FaceBot API (localhost:4000)
- [ ] Verify arcade dashboard is active and launch.sh points correctly

### Out of Scope

- Mobile app — web-first personal workstation tool
- Cloud deployment — localhost only
- Authentication — personal use, no multi-user
- Production hardening — personal project, pragmatic solutions preferred

## Context

- FaceBot server lives at `~/Documents/facebot` (Express + SQLite + ActivityPub)
- FaceBot already has `sqlite3` in package.json (was swapped from `better-sqlite3`)
- FaceBot `src/server.ts` still uses `better-sqlite3` import patterns (sync) — needs update to `sqlite3` async API
- News fetcher currently pulls from generic national sources — needs local Albany, GA sources
- Dashboard already has BotSpace UI panel — just needs JavaScript wired to FaceBot endpoints
- Dashboard already uses NES.css arcade theme — just verify it's the active index.html

## Constraints

- **Tech stack**: Bash + vanilla JS + Python only for radio-free-albany — no npm/frameworks
- **FaceBot stack**: TypeScript + Express + SQLite — separate project at ~/Documents/facebot
- **No jq dependency**: news-fetcher.sh should use Python fallback for JSON processing per existing pattern
- **Localhost only**: Dashboard on port 8787, FaceBot on port 4000

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use sqlite3 instead of better-sqlite3 for FaceBot | better-sqlite3 has native compilation issues | — Pending |
| Add Albany Herald, WALB, WTXL as local news sources | User lives in Albany, GA — wants local news | — Pending |
| FaceBot API at localhost:4000 | Keep separate from dashboard server (8787) | — Pending |

---
*Last updated: 2026-02-08 after initialization*

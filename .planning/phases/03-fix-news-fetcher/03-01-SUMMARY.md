---
phase: 03-fix-news-fetcher
plan: 01
subsystem: news-aggregation
tags: [rss, xml-parsing, python, bash, albany-ga, news-feeds]

# Dependency graph
requires:
  - phase: none
    provides: standalone plan
provides:
  - "Working RSS aggregation with 8 feeds across 5 categories"
  - "Atomic JSON output for dashboard consumption"
  - "Albany Herald, WALB, WTXL, Google News local coverage"
  - "Hacker News tech feed"
affects: [dashboard-display, news-categories]

# Tech tracking
tech-stack:
  added: [hnrss.org]
  patterns: [atomic-file-write, cdata-sanitization, per-source-bias-labels]

key-files:
  created: []
  modified: [dashboard/news-fetcher.sh]

key-decisions:
  - "Albany Herald 403 on article pages is Cloudflare bot protection -- URLs are valid article paths, work in browser"
  - "Google News Albany capped at 3 items to avoid noise from tangential matches"
  - "Per-source bias_label replaces hardcoded NEUTRAL for all sources"

patterns-established:
  - "Atomic JSON write: tempfile.mkstemp + os.rename for crash-safe output"
  - "clean_title(): strip HTML tags, unescape entities, collapse whitespace"
  - "get_link(): extract URL from RSS link element with protocol validation"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 3 Plan 1: Fix News Fetcher Summary

**Rewrote news-fetcher.sh with 8 verified RSS feeds (Albany Herald, WALB, WTXL, Google News Albany, Hacker News, GA Wildlife, WTXL Sports, BBC World), atomic JSON output, CDATA/entity sanitization, and per-source bias labels**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-09T20:28:14Z
- **Completed:** 2026-02-09T20:30:54Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- All 8 RSS feeds verified working and producing items (38 total, 18 local)
- Albany Herald, WALB, and WTXL all returning local Albany news items
- Hacker News feed added for tech category (was missing entirely)
- Atomic JSON write prevents partial/corrupt news.json on crashes
- CDATA-wrapped titles (WALB, Google News) rendered as clean text
- Script completes in 4.4 seconds (under 30s requirement)

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite news-fetcher.sh feed config, parsing, and output** - `f3c2287` (feat)
2. **Task 2: Validate news.json structure and article link quality** - no commit (validation-only, no code changes)

## Files Created/Modified
- `dashboard/news-fetcher.sh` - Rewritten Python block with 8 feeds, clean_title(), get_link(), atomic write

## Decisions Made
- Albany Herald returns 403 on article pages via Cloudflare bot protection, but URLs are valid article paths (slug-based, not homepage) and work in browsers -- accepted as-is
- Google News Albany limited to 3 items (max_items) to reduce noise from loosely-matching results
- Per-source bias_label values assigned: CENTER for Herald/WALB/WTXL/WTXL Sports, MIXED for Google News Albany, NEUTRAL for Hacker News/GA Wildlife, CENTER-LEFT for BBC World

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Albany Herald article pages return 403 to curl/automated requests (Cloudflare bot protection). RSS feed itself works fine (200). Article URLs are valid article paths with slugs, not generic homepages. Users clicking links in the dashboard will reach the articles normally via their browser.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- News fetcher fully operational with local Albany coverage
- Dashboard can consume news-cache/news.json via existing fetch() path
- Ready for Phase 4 or any remaining dashboard work

## Self-Check: PASSED

- FOUND: dashboard/news-fetcher.sh
- FOUND: dashboard/news-cache/news.json
- FOUND: 03-01-SUMMARY.md
- FOUND: f3c2287 (Task 1 commit)

---
*Phase: 03-fix-news-fetcher*
*Completed: 2026-02-09*

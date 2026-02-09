---
phase: 02-wire-botspace-chat-panel
plan: 01
subsystem: ui
tags: [vanilla-js, fetch-api, xss-prevention, polling, chat, facebot]

# Dependency graph
requires:
  - phase: 01-fix-facebot-server
    provides: "Working FaceBot server at localhost:4000 with /api/feed, /api/post"
provides:
  - "Live BotSpace chat panel polling FaceBot /api/feed every 5s with exponential backoff"
  - "Chat posting to FaceBot /api/post as username 'tripp' with optimistic UI"
  - "XSS-safe rendering via escapeHtml() on all dynamic content"
  - "Offline state display with 'FACEBOT OFFLINE' alert"
affects: [dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "escapeHtml() via DOM textContent/innerHTML round-trip for XSS prevention in template literals"
    - "Recursive setTimeout with exponential backoff for resilient polling (5s -> 60s cap)"
    - "DOM createElement/textContent for optimistic message rendering (no innerHTML with user input)"
    - "Auto-scroll detection: scrollHeight - scrollTop - clientHeight < 50 threshold"

key-files:
  created: []
  modified:
    - "dashboard/index.html"

key-decisions:
  - "Used DOM-based escapeHtml() instead of regex replacement -- browser's own encoder handles all edge cases"
  - "Recursive setTimeout over setInterval for polling -- enables dynamic backoff adjustment"
  - "chatFirstLoad flag for unconditional first-load scroll -- ensures initial render scrolls to bottom"

patterns-established:
  - "escapeHtml(str): canonical XSS prevention for all innerHTML template literals in dashboard"
  - "scheduleChatPoll(): recursive setTimeout pattern for polling with variable intervals"

# Metrics
duration: 2min
completed: 2026-02-09
---

# Phase 2 Plan 1: Wire BotSpace Chat Panel Summary

**BotSpace chat panel wired to FaceBot REST API with XSS-safe rendering, exponential backoff polling, optimistic post UI, and Enter key submission**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-09T12:41:59Z
- **Completed:** 2026-02-09T12:43:37Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Rewrote loadChat() to fetch from FaceBot /api/feed with escapeHtml() on all dynamic fields (content, name, username)
- Implemented exponential backoff polling via recursive setTimeout (5s -> 10s -> 20s -> 40s -> 60s cap)
- Added "FACEBOT OFFLINE" alert display when server is unreachable, with automatic recovery on reconnection
- Rewrote postChat() to POST to FaceBot /api/post with XSS-safe optimistic UI using DOM createElement/textContent
- Added Enter key submission (Shift+Enter excluded) for standard chat UX
- Failed POST messages marked with red border and "[SEND FAILED]" text

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite loadChat() with FaceBot API fetch, XSS protection, offline state, and backoff polling** - `a4a0cde` (feat)
2. **Task 2: Rewrite postChat() with FaceBot API POST, XSS-safe optimistic UI, and Enter key support** - `4e7353c` (feat)

## Files Created/Modified
- `dashboard/index.html` - Complete BotSpace chat integration with FaceBot API (loadChat, postChat, escapeHtml, scheduleChatPoll, Enter key listener)

## Decisions Made
- Used DOM-based escapeHtml() (textContent/innerHTML round-trip) instead of regex -- OWASP recommended, handles all edge cases including null bytes and Unicode
- Used recursive setTimeout instead of setInterval for polling -- naturally supports dynamic backoff intervals and avoids overlapping calls
- Added chatFirstLoad flag to ensure first render always scrolls to bottom regardless of scroll position

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required. FaceBot must be running at localhost:4000 for chat to function (falls back to "FACEBOT OFFLINE" gracefully).

## Next Phase Readiness
- BotSpace chat panel is fully functional when FaceBot is running
- Dashboard gracefully handles FaceBot being offline with visible state and backoff
- Ready for Phase 3 (News Fetcher) which is independent of chat functionality

## Self-Check: PASSED

- FOUND: dashboard/index.html
- FOUND: 02-01-SUMMARY.md
- FOUND: commit a4a0cde (Task 1)
- FOUND: commit 4e7353c (Task 2)
- FOUND: FACEBOT_URL constant
- FOUND: escapeHtml function
- FOUND: scheduleChatPoll function
- FOUND: FACEBOT OFFLINE state
- FOUND: chatBackoff variable
- FOUND: /api/post endpoint
- FOUND: /api/feed endpoint
- FOUND: Enter key listener
- FOUND: SEND FAILED handling
- FOUND: DOM createElement usage

---
*Phase: 02-wire-botspace-chat-panel*
*Completed: 2026-02-09*

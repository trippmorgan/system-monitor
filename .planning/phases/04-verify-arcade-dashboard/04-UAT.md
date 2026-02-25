---
status: testing
phase: 04-verify-arcade-dashboard
source: 01-01-SUMMARY.md, 02-01-SUMMARY.md, 03-01-SUMMARY.md, 04-01-SUMMARY.md
started: 2026-02-09T22:30:00Z
updated: 2026-02-09T22:30:00Z
---

## Current Test

number: 1
name: Dashboard Launches with Arcade Theme
expected: |
  Run `ENABLE_BROWSER_OPEN=0 bash dashboard/launch.sh` then open http://localhost:8787 in your browser. You should see an 8-bit retro arcade-styled dashboard with pixel fonts (Press Start 2P), NES.css styled containers with thick borders, and a "RADIO FREE ALBANY" header.
awaiting: user response

## Tests

### 1. Dashboard Launches with Arcade Theme
expected: Run `ENABLE_BROWSER_OPEN=0 bash dashboard/launch.sh` then open http://localhost:8787 in browser. Page shows 8-bit retro arcade-styled dashboard with pixel fonts (Press Start 2P), NES.css styled containers, and "RADIO FREE ALBANY" header.
result: [pending]

### 2. System Vitals Panel Shows Live Stats
expected: The System Vitals panel shows CPU load, Memory usage, and Disk usage with percentage bars. Values should reflect your actual system (e.g., Memory ~4%, Disk ~26%).
result: [pending]

### 3. Local News Panel Shows Albany Headlines
expected: The Local News panel shows headlines from Albany Herald, WALB News 10, and/or WTXL with real article titles (not placeholder text). At least a few headlines should be clearly about Albany, GA or South Georgia.
result: [pending]

### 4. News Headlines Open Actual Articles
expected: Click a local news headline in the dashboard. It should open the actual article page in a new tab (not a generic homepage like walb.com or albanyherald.com). Note: Albany Herald links may show a Cloudflare challenge page — that's expected (bot protection), the URL itself is correct.
result: [pending]

### 5. Breaking News and Sports Panels Populated
expected: The Breaking News panel shows BBC World headlines. The Sports panel shows WTXL Sports headlines. The Outdoors panel shows GA Wildlife blog posts. None of these panels are empty.
result: [pending]

### 6. BotSpace Chat Shows Offline State
expected: The BotSpace BBS panel should show "FACEBOT OFFLINE" since FaceBot is not currently running. It should NOT show a blank panel or JavaScript errors.
result: [pending]

### 7. Dashboard Stops Cleanly
expected: Run `bash dashboard/stop.sh`. Output should say "Stopping Radio Free Albany..." and "Done." Refreshing localhost:8787 in your browser should show a connection error (page not loading). No orphan processes left.
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0

## Gaps

[none yet]

# Codebase Concerns

**Analysis Date:** 2026-02-08

## Tech Debt

**Bash Error Handling:**
- Issue: Scripts lack comprehensive error handling. No `set -e`, `set -u`, or `set -o pipefail` directives. Silent failures likely.
- Files: `dashboard/news-fetcher.sh`, `dashboard/system-stats.sh`, `dashboard/launch.sh`, `scripts/system-monitor-assistant.sh`, `scripts/health-check.sh`
- Impact: Failed curl requests, missing files, or invalid JSON go unnoticed. Dashboard may display stale data indefinitely while background processes silently fail.
- Fix approach: Add shebang with error flags. Implement explicit error checking after curl/file operations. Propagate errors to calling processes.

**JSON Parsing Without jq:**
- Issue: `news-fetcher.sh` (lines 282-319) contains duplicate Python code blocks for JSON conversion. First block (PYEOF) is dead code never executed.
- Files: `dashboard/news-fetcher.sh` lines 282-345
- Impact: Confusing and wasteful. The first Python heredoc is abandoned in favor of second `-c` variant. Makes debugging harder and wastes cycles parsing both.
- Fix approach: Remove the dead PYEOF heredoc block (lines 282-319). Keep only the executed python3 -c version (lines 322-345).

**Unquoted Variables in Bash:**
- Issue: Multiple instances of unquoted variables passed to echo/sed/awk: `$TITLE`, `$URL`, `$source`, etc.
- Files: `dashboard/news-fetcher.sh` (lines 90-96), `scripts/system-monitor-assistant.sh` (line 245)
- Impact: Word splitting and glob expansion could break on titles with spaces/special chars. RSS feeds often contain special characters that will cause command injection or data loss.
- Fix approach: Always quote variables in critical sections. Use `"$TITLE"` not `$TITLE`.

**Grep-Based JSON Extraction:**
- Issue: `scripts/system-monitor-assistant.sh` (lines 88-97) and `dashboard/system-stats.sh` use grep fallback for JSON parsing when jq unavailable.
- Files: `scripts/system-monitor-assistant.sh`, `system-stats.sh`
- Impact: Fragile regex patterns will fail on malformed JSON or quoted special chars. The fallback is less reliable than primary jq path.
- Fix approach: Declare jq as hard requirement, or use Python for all JSON parsing consistently.

**Hardcoded Service Names:**
- Issue: Service names hardcoded in multiple places: `postgresql@14-main` appears in `config.sh`, `system-stats.sh`, `system-monitor-assistant.sh`.
- Files: `config.sh` (line 60), `dashboard/system-stats.sh` (line 86), `scripts/system-monitor-assistant.sh` (line 141)
- Impact: If PostgreSQL version changes to 15+, all monitoring breaks silently. Configuration is centralized but implementation details scattered.
- Fix approach: Extract service names to `config.sh` as arrays/list, source once from config.

**Python Syntax Error in news-fetcher.sh:**
- Issue: Lines 288 in embedded Python tries to use f-strings with shell variable substitution: `sys.argv[1] if len(sys.argv) > 1 else "/tmp/news_temp"` but passes hardcoded temp file name.
- Files: `dashboard/news-fetcher.sh` (lines 282-319)
- Impact: Dead code (never runs), but if activated would fail due to argument mismatch between shell variables and Python args.
- Fix approach: Remove dead heredoc block entirely.

## Known Bugs

**News Fetcher Fails Silently on Network Error:**
- Symptoms: News feed stops updating. Dashboard shows "Scanning..." indefinitely or stale news.
- Files: `dashboard/news-fetcher.sh` (entire script, esp. lines 108-272)
- Trigger: Network timeout, DNS failure, or API endpoint down. All curl commands ignore errors.
- Workaround: Restart dashboard with `./stop.sh && ./launch.sh`. Check `news.json` exists: `ls -la dashboard/news-cache/news.json`.

**Memory Leak in Monitor Loop:**
- Symptoms: Dashboard becomes slow after hours of uptime. System memory usage of monitoring process increases.
- Files: `scripts/system-monitor-assistant.sh` (lines 232-248, infinite while loop)
- Trigger: Process runs for >12 hours. Each iteration may accumulate state or temp data.
- Workaround: Restart monitor periodically: `pkill -f system-monitor-assistant.sh` and relaunch.

**Empty JSON on Concurrent Updates:**
- Symptoms: Dashboard displays "No targets found" or "Level complete" when news.json corrupted mid-write.
- Files: `dashboard/news-fetcher.sh` (line 334 writes to `$NEWS_JSON` without lock), concurrent `system-stats.sh` writes to same directory
- Trigger: If news-fetcher.sh runs while dashboard refreshes simultaneously, partial write occurs.
- Workaround: Manually refresh: `./dashboard/news-fetcher.sh`.

**GPU Monitoring Fails on Non-NVIDIA Systems:**
- Symptoms: Stats display "N/A" for GPU metrics. No error logged.
- Files: `dashboard/system-stats.sh` (lines 62-74), `scripts/system-monitor-assistant.sh` (lines 132-137)
- Trigger: Running on AMD/Intel GPU or no nvidia-smi installed.
- Workaround: This is by design (graceful degradation). Set `ENABLE_GPU_MONITORING=0` in config.sh if unwanted.

## Security Considerations

**Hardcoded Audio Stream URL:**
- Risk: Stream URL embedded in `dashboard/index.html` (line 358) as plaintext. If radio station changes streams, code must be updated and redeployed.
- Files: `dashboard/index.html` (line 358: `https://stream.aiir.com/0ompkrc5jxntv`)
- Current mitigation: Localhost-only server (line 109 of launch.sh), not publicly exposed.
- Recommendations: Move URL to config.sh, update via JSON. Consider CORS implications if exposed remotely.

**No Input Validation on Chat:**
- Risk: `dashboard/index.html` (lines 497-511) accepts arbitrary user input in chat without sanitization. XSS possible if backend implemented.
- Files: `dashboard/index.html` (lines 505-506 directly interpolate `input.value` to DOM)
- Current mitigation: Backend (TODO on line 509) not implemented. Local-only usage.
- Recommendations: If backend ever added, escape input with `textContent` not `innerHTML`.

**Local HTTP Server Binding:**
- Risk: Dashboard bound to 127.0.0.1 only (launch.sh line 109), limiting access to localhost. Good security posture for personal workstation.
- Files: `dashboard/launch.sh` (line 109)
- Current mitigation: `--bind 127.0.0.1` prevents remote access.
- Recommendations: Keep this. If remote access needed, add authentication layer.

**No Rate Limiting on News Fetching:**
- Risk: `dashboard/news-fetcher.sh` makes 30+ curl requests with no delay between them (lines 108-272). Could trigger rate-limiting or IP blocks from news sources.
- Files: `dashboard/news-fetcher.sh` (lines 108-272)
- Current mitigation: Timeout per curl command (max-time 10-15s), but parallel requests possible.
- Recommendations: Add `sleep 0.5` between requests, or implement exponential backoff on 429 responses.

**External Dependency on Third-Party URLs:**
- Risk: News fetcher relies on 10+ external APIs (Google News, Hacker News, news.google.com, etc.). Any endpoint down breaks entire category.
- Files: `dashboard/news-fetcher.sh` (lines 109, 124, 131, 138, 147, 162, 169, 180, 190, 199, etc.)
- Current mitigation: Each category independently fetches, one failure doesn't block others.
- Recommendations: Add fallback cache (serve previous news if fetch fails). Log failed sources separately. Consider periodic health check.

**Process IDs Not Validated on Stop:**
- Risk: `dashboard/stop.sh` reads PIDs from files but doesn't verify they're still running. Could kill unrelated process if PID reused.
- Files: `dashboard/stop.sh`
- Current mitigation: PIDs checked via kill -0 before signal (good practice if implemented).
- Recommendations: Verify file contains pidof check.

## Performance Bottlenecks

**News Fetcher Sequential Requests:**
- Problem: 30+ curl commands run sequentially (lines 108-272). Takes 2-3 minutes total.
- Files: `dashboard/news-fetcher.sh` (entire news fetching section)
- Cause: Each curl blocks until completion. No parallelization.
- Improvement path: Run curl commands in background with `&`, wait for all with `wait`. Could reduce fetch time from 3min to 30sec.

**Grep-Based News Extraction:**
- Problem: Crude regex parsing of RSS/HTML. Many retries needed, often incomplete extraction.
- Files: `dashboard/news-fetcher.sh` (lines 109-272, all `grep -oP` patterns)
- Cause: RSS feeds have inconsistent formatting. HTML scraping is brittle. Regex doesn't account for entity encoding.
- Improvement path: Use dedicated RSS parser library (feedparser in Python) instead of grep. Faster and more reliable.

**Full System Scan Every 30 Seconds:**
- Problem: Dashboard calls `system-stats.sh` every 30s even if nothing changed. Runs `free`, `df`, `nvidia-smi`, `systemctl` every 30s.
- Files: `dashboard/launch.sh` (lines 88-101), triggered by `system-monitor-assistant.sh` (line 212)
- Cause: No conditional refreshes. All metrics collected regardless of change.
- Improvement path: Cache results, only refresh if >5% change detected. Skip GPU queries if not used.

**No Connection Pooling for HTTP:**
- Problem: Python HTTP server creates new process per request (fork-based). Dashboard with many assets loads slowly.
- Files: `dashboard/launch.sh` (line 109 uses `python3 -m http.server` default handler)
- Cause: Built-in server not optimized for concurrency.
- Improvement path: Switch to lightweight async server (e.g., `uvicorn`, `aiohttp`) if scale needed. For personal workstation, acceptable.

## Fragile Areas

**News Fetcher Regex Patterns:**
- Files: `dashboard/news-fetcher.sh` (lines 109-272)
- Why fragile: Relies on consistent RSS/HTML structure. Any site redesign breaks pattern matching. Google News pagination changes would halt all local/state/sports categories.
- Safe modification: Test each `grep -oP` pattern against sample RSS manually before changing. Use `curl ... | grep ...` in terminal first.
- Test coverage: No tests. Manual verification only.

**System-Monitor-Assistant JSON Parsing:**
- Files: `scripts/system-monitor-assistant.sh` (lines 88-98)
- Why fragile: Fallback grep parsing assumes clean JSON. Quoted values with colons break parsing.
- Safe modification: Always test `json_get` function with edge cases: quoted strings, null values, missing keys.
- Test coverage: None. Implicit assumption jq is available.

**Hardcoded Threshold Logic:**
- Files: `scripts/system-monitor-assistant.sh` (lines 166-203), thresholds in `config.sh` (lines 21-42)
- Why fragile: Compare operators use numeric thresholds directly. No validation that WARN < CRIT.
- Safe modification: Add validation in config.sh that WARN < CRIT for each metric.
- Test coverage: None.

**Dashboard HTML/JavaScript Coupling:**
- Files: `dashboard/index.html` (entire script section lines 362-520)
- Why fragile: Assumes `news-cache/news.json` and `news-cache/stats.json` always exist with exact structure. No validation.
- Safe modification: Add defensive checks: `if (!stats || !stats.cpu)` before accessing properties. Parse try/catch around JSON.loads.
- Test coverage: None. Relies on manual testing.

## Scaling Limits

**Single-File JSON State:**
- Current capacity: Up to ~100 news items + system stats in memory. Dashboard loads entire file into memory.
- Limit: At 1000+ news items, browser JSON.parse becomes slow. File I/O blocks.
- Scaling path: Split news.json by category. Implement pagination. Use local IndexedDB cache on client side.

**Infinite Alert Log:**
- Current capacity: `logs/alerts.log` grows unbounded. No rotation.
- Limit: After 6+ months of 24/7 monitoring, log could exceed 100MB, causing read/seek slowness.
- Scaling path: Implement log rotation in `config.sh`. Use logrotate or add weekly cleanup in cron.

**Blocking HTTP Server:**
- Current capacity: Python http.server handles ~10 concurrent requests per core.
- Limit: If dashboard accessed by 100+ clients simultaneously, server blocks.
- Scaling path: For personal workstation, not applicable. If needed, upgrade to async server.

## Dependencies at Risk

**External News APIs (High Risk):**
- Risk: Google News, Hacker News, CBS/NBC/Fox RSS endpoints could change, disable, or rate-limit without warning.
- Impact: Categories stop updating silently. User unaware of missing data.
- Migration plan: Maintain fallback cache. Implement API health check. Consider self-hosted RSS aggregator (Miniflux) as fallback.

**nvidia-smi (Medium Risk):**
- Risk: NVIDIA driver updates could change output format. nvidia-smi might be removed in future NVIDIA architectures.
- Impact: GPU monitoring silently fails, displays "N/A".
- Migration plan: Already handled gracefully. Add logging when GPU monitoring fails (currently silent).

**Python 3 (Low Risk):**
- Risk: Python 2 EOL, but Python 3 widely maintained. However, json module is stable.
- Impact: Unlikely to break.
- Migration plan: No action needed.

**Bash (Low Risk):**
- Risk: Bash 4+ features used (e.g., associative arrays not used here, but `declare` could break on very old systems).
- Impact: Should work on Ubuntu 18.04+.
- Migration plan: Add shebang version check or document minimum bash version (4.0).

## Missing Critical Features

**No Persistence:**
- Problem: All data is ephemeral. If `launch.sh` stops, all history (alerts, uptime tracking) resets.
- Blocks: Can't generate weekly/monthly reports of system health. Can't trend uptime.
- Recommendation: Add SQLite database to persist alerts, stats snapshots every hour.

**No Authentication:**
- Problem: Dashboard bound to localhost only, but no password/token.
- Blocks: Can't safely expose remotely. No user isolation.
- Recommendation: Add basic HTTP auth for future remote access.

**No Alerting Delivery:**
- Problem: Alerts only logged to file. No email, Slack, or SMS notifications.
- Blocks: Critical alerts (disk full, service down) go unnoticed if not actively watching dashboard.
- Recommendation: Add webhook support or email integration in alert logic.

**No News Categorization Accuracy:**
- Problem: Bias scoring hardcoded (CBS = -10, Fox = +15). No actual source verification. User can't customize.
- Blocks: Bias tags are editorial assumptions, not verifiable.
- Recommendation: Make bias scores configurable in config.sh. Add user feedback mechanism.

## Test Coverage Gaps

**News Fetcher:**
- What's not tested: API failures, malformed RSS, network timeouts, missing fields.
- Files: `dashboard/news-fetcher.sh`
- Risk: Silent failures. Bad data passed to dashboard without validation. User unaware news is stale.
- Priority: High - this is critical path for dashboard content.

**System Monitor Alerts:**
- What's not tested: Threshold edge cases (load=6.0 vs 6.1), service state transitions, concurrent refreshes.
- Files: `scripts/system-monitor-assistant.sh`
- Risk: False positives or missed alerts near thresholds. Alert storms on flapping services.
- Priority: High - false alerts cause alert fatigue.

**Dashboard JavaScript:**
- What's not tested: JSON parse failures, missing keys, large datasets, browser compatibility.
- Files: `dashboard/index.html` (lines 399-453)
- Risk: White screen on parse error. No fallback. User left with "Scanning..." forever.
- Priority: Medium - UX impact but dashboard degrades gracefully to missing data currently.

**Health Check Report:**
- What's not tested: Report format, threshold logic, file permissions for log write.
- Files: `scripts/health-check.sh`
- Risk: Cron job fails silently. Reports never generated. User unaware.
- Priority: Medium - runs nightly, low visibility to issues.

---

*Concerns audit: 2026-02-08*

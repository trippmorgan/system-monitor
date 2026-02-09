# External Integrations

**Analysis Date:** 2026-02-08

## APIs & External Services

**News Aggregation:**
- **Hacker News** - Tech news and world stories
  - Endpoint: `https://hacker-news.firebaseio.com/v0/topstories.json`
  - Method: HTTP GET (public, no auth)
  - Usage: `dashboard/news-fetcher.sh` lines 109-116
  - Bias score: 5 (Center)
  - Category: tech

- **Google News RSS** - Regional and topical news
  - Endpoint: `https://news.google.com/rss/search?q={query}&hl=en-US&gl=US&ceid=US:en`
  - Method: RSS feed parsing
  - Usage: `dashboard/news-fetcher.sh` lines 189-272
  - Used for: local news, state news, sports, politics, nature, conservation
  - No authentication required

- **Major Networks (CBS, NBC, Fox News, NPR)**
  - Sources:
    - CBS News: `https://www.cbsnews.com/latest/rss/main` (bias: -10, Center-Left)
    - NBC News: `https://feeds.nbcnews.com/nbcnews/public/news` (bias: -12, Center-Left)
    - Fox News: `https://moxie.foxnews.com/google-publisher/latest.xml` (bias: +15, Right)
    - NPR: `https://feeds.npr.org/1001/rss.xml` (bias: -8, Center-Left)
  - Method: RSS feed parsing
  - Usage: `dashboard/news-fetcher.sh` lines 123-183
  - Bias labels: Center-Left to Right spectrum
  - Category: breaking news

- **Alternative News Sources (Daily Wire, Breitbart)**
  - Daily Wire: `https://www.dailywire.com/feeds/rss.xml` (bias: +18, Right)
  - Breitbart: `https://feeds.feedburner.com/breitbart` (bias: +20, Right)
  - Method: RSS feed parsing
  - Usage: `dashboard/news-fetcher.sh` lines 160-172
  - Category: politics, alt
  - No authentication required

- **Drudge Report** (News aggregator)
  - URL: `https://www.drudgereport.com/`
  - Method: HTML parsing (grep-based)
  - Usage: `dashboard/news-fetcher.sh` lines 147-154
  - Bias score: +10 (Center-Right)
  - Category: breaking

## Data Storage

**Databases:**
- None - Project uses only file-based JSON storage
- No SQL database required
- No persistent data beyond JSON cache files

**File Storage:**
- Local filesystem only
- Cache location: `dashboard/news-cache/`
  - `news.json` - Aggregated news items
  - `stats.json` - System metrics
  - `meta.json` - Cache metadata

**Caching:**
- In-memory: None (stateless)
- File-based cache: `dashboard/news-cache/` with TTL configuration
- News cache TTL: Configurable via `NEWS_CACHE_TTL` (default: 3600 seconds = 1 hour)
- Cleanup: Auto-cleanup of logs after 30 days (configurable via `LOG_RETENTION_DAYS`)

## Authentication & Identity

**Auth Provider:**
- None - All integrations are public endpoints
- No API keys required
- No user authentication
- No OAuth/OIDC

**Implementation:**
- Public feeds only (RSS, JSON)
- HTTP requests via `curl` with Mozilla user-agent headers
- No credential management required

## Monitoring & Observability

**Error Tracking:**
- None - No external error tracking service
- Errors logged locally to `logs/alerts.log`

**Logs:**
- Local file-based logging
- Files: `logs/daily-report-YYYY-MM-DD.log`, `logs/alerts.log`, `logs/cleanup-YYYY-MM-DD.log`
- System journal monitoring via `journalctl` (counts errors in `/sys` logs)
- Alert logging: `logs/alerts.log` appended with state-change alerts

## CI/CD & Deployment

**Hosting:**
- Local Linux workstation (Ubuntu/Debian)
- No cloud deployment
- No external hosting required

**CI Pipeline:**
- None - No automated testing or deployment pipeline
- Manual execution of scripts via cron or shell commands

**Web Server:**
- Python `http.server` (built-in module)
- Bound to `127.0.0.1` only (localhost)
- Port: 8787 (configurable via `DASHBOARD_PORT`)
- Started by `dashboard/launch.sh`

## Environment Configuration

**Required Environment Variables:**
None required - all config uses defaults or `config.sh` sourcing.

**Configuration Via `config.sh`:**
- `MONITOR_HOME` - Base directory (default: `$HOME/system-monitor`)
- `LOG_DIR` - Logs directory
- `DASHBOARD_DIR` - Dashboard directory
- `NEWS_CACHE_DIR` - News cache directory
- Alert thresholds: `CPU_WARN`, `CPU_CRIT`, `MEM_WARN`, `MEM_CRIT`, `DISK_WARN`, `DISK_CRIT`, `GPU_TEMP_WARN`, `GPU_TEMP_CRIT`
- Timing: `CHECK_INTERVAL`, `NEWS_REFRESH_INTERVAL`, `NEWS_CACHE_TTL`
- Services to monitor: `MONITORED_SERVICES`
- Feature flags: `ENABLE_GPU_MONITORING`, `ENABLE_NEWS_FETCHING`, `ENABLE_BROWSER_OPEN`
- Local search term: `LOCAL_NEWS_SEARCH` (default: "Albany+Georgia")

**Secrets Location:**
- No secrets required - all external APIs are public endpoints
- No `.env` file needed
- Optional user overrides via `~/.config/system-monitor/config`

**User Configuration File:**
- Path: `~/.config/system-monitor/config`
- Purpose: Override any setting in `config.sh` without modifying main repo
- Example (from README):
  ```bash
  export CPU_WARN=4
  export LOCAL_NEWS_SEARCH="Austin+Texas"
  export DASHBOARD_PORT=9000
  ```

## Webhooks & Callbacks

**Incoming:**
- None - No webhook endpoints

**Outgoing:**
- None - No external webhooks
- All data flow is pull-based (fetch news, collect stats)

## System Service Monitoring

**Monitored systemd Services:**
- `docker` - Container runtime
- `postgresql@14-main` - PostgreSQL 14 database
- `ollama` - Local LLM service
- `ssh` - SSH server
- `nxserver` - NoMachine remote desktop (optional)

**Monitoring Method:**
- `systemctl is-active <service>` status checks
- Status written to `stats.json` for dashboard display
- No automatic service restart (read-only monitoring)

## External Tool Dependencies

**Network Tools:**
- `curl` - HTTP requests (news fetching)
- User-agent: `Mozilla/5.0` (standard browser header)
- Timeout: 10-15 seconds per request (configurable in scripts)

**System Monitoring Tools:**
- `free` - Memory info from `/proc/meminfo`
- `df` - Disk info from `/proc/mounts`
- `uptime` - System uptime
- `ss` / `netstat` - Network connection status
- `journalctl` - System logs and error counting
- `nvidia-smi` - GPU monitoring (optional, graceful fallback)

**Text Processing:**
- `awk`, `sed`, `grep`, `cut`, `tr` - Log parsing and data extraction
- `jq` (optional) - JSON parsing (fallback to Python/grep parsing)

## Network Requirements

**Connectivity:**
- Internet access required for news fetching (HTTP/HTTPS)
- Public URLs only (no VPN or special network required)
- Timeouts: 10-15 seconds per request (scripts handle failures gracefully)

**Ports:**
- 8787 (configurable) - Dashboard HTTP server (localhost only)
- No inbound connections required
- Outbound: 443 (HTTPS), 80 (HTTP) for news feeds

**Failure Handling:**
- If news fetch fails, previous cache is used
- If system metrics fail, "N/A" is displayed
- No blocking errors - missing data is non-fatal
- All external API calls use `curl -s` (silent mode)

## Rate Limiting & Quotas

**News Fetching:**
- News refresh every 2 minutes (configurable)
- ~12 requests per refresh cycle (1 per Hacker News item + RSS feeds)
- RSS feeds are public (no rate limits)
- Hacker News Firebase API has no documented rate limits for public access

**System Monitoring:**
- Stats refresh every 30 seconds
- No external API calls (all local metrics)
- Log retention: 30 days (auto-cleanup)

---

*Integration audit: 2026-02-08*

# Architecture

**Analysis Date:** 2026-02-08

## Pattern Overview

**Overall:** Multi-layer data pipeline with three specialized agent roles and event-driven dashboard refresh.

**Key Characteristics:**
- **Separation of concerns**: System monitoring, news aggregation, and user interaction are decoupled
- **Agent-based**: Three specialized Claude agents (System Tech, News Curator, Orchestrator) handle different domains
- **Event-driven refresh**: Dashboard updates trigger on schedule (stats every 30s, news every 2 minutes)
- **JSON data exchange**: All data flows through JSON files in `news-cache/`
- **Stateful alerting**: Monitor keeps track of previous state to alert only on changes

## Layers

**Collection Layer:**
- Purpose: Gather data from system and external sources
- Location: `dashboard/system-stats.sh`, `dashboard/news-fetcher.sh`
- Contains: Shell scripts that execute system commands and HTTP calls
- Depends on: `config.sh`, /proc filesystem, curl, systemctl
- Used by: Refresh loop in `launch.sh`
- Output format: JSON written to `news-cache/stats.json` and `news-cache/news.json`

**Presentation Layer:**
- Purpose: Display collected data in user-facing interface
- Location: `dashboard/index.html`, `dashboard/dashboard.sh`
- Contains: Web UI (NES.css arcade theme), terminal alternative, real-time refresh logic
- Depends on: JSON data from `news-cache/`, vanilla JavaScript
- Used by: Users through browser or terminal

**Monitoring & Alerting Layer:**
- Purpose: Continuous background monitoring with change-based alerting
- Location: `scripts/system-monitor-assistant.sh`, `scripts/health-check.sh`
- Contains: Threshold checks, state persistence, alert logging
- Depends on: `config.sh`, system metrics, previous state file
- Used by: Cron scheduler, manual execution, refresh loop
- Output: `logs/alerts.log` and `logs/daily-report-YYYY-MM-DD.log`

**Agent Layer:**
- Purpose: Specialized Claude agents for user interaction
- Location: `agents/system-tech/CLAUDE.md`, `agents/news-curator/CLAUDE.md`, `agents/orchestrator/CLAUDE.md`
- Contains: Agent role definitions and capabilities
- Depends on: `dispatch.sh` launcher, read-only access to monitoring/news data
- Used by: Users via command line (`claude` in agent directories)

**Orchestration Layer:**
- Purpose: Process lifecycle management
- Location: `dispatch.sh`, `dashboard/launch.sh`, `dashboard/stop.sh`
- Contains: Background process spawning, PID tracking, server startup
- Depends on: Python HTTP server, bash process control
- Used by: Users initiating dashboard or agent dispatch

## Data Flow

**Dashboard Startup Flow:**

1. User executes `dashboard/launch.sh`
2. Launch script sources `config.sh` for configuration
3. Initial data fetch: Runs `system-stats.sh` and `news-fetcher.sh`
4. Background refresh loop spawned: Calls stats every 30s, news every 2 minutes
5. Python HTTP server starts on port 8787
6. Browser opens to `http://localhost:8787/index.html`
7. Dashboard JavaScript fetches `news-cache/stats.json` and `news-cache/news.json` every 30s

**Alert Flow (Background):**

1. `system-monitor-assistant.sh` runs continuously (daemon)
2. Reads current metrics via /proc and system commands
3. Compares against previous state in `$LOG_DIR/.monitor-state.json`
4. If value crosses threshold or changes significantly: writes to `logs/alerts.log`
5. System Tech agent can read alerts file and inform user

**News Fetch Flow:**

1. `news-fetcher.sh` invoked by refresh loop (every 2 minutes by default)
2. Fetches from: Hacker News Firebase API, CBS/NBC/Fox RSS, Drudge Report, Google News
3. Parses titles and applies bias scoring (-20 to +20 scale)
4. Categorizes: breaking, local, state, sports, politics, tech, nature, fishing, conservation
5. Writes combined JSON to `news-cache/news.json` with timestamps
6. Dashboard reads and renders by category

**Agent Dispatch Flow:**

1. User runs `dispatch.sh` (shows menu)
2. Selects agent (1=System Tech, 2=News Curator, 3=Orchestrator)
3. Script changes directory to agent folder and runs `claude` command
4. Agent loads CLAUDE.md role definition
5. Agent has read-only access to relevant data files and scripts
6. Agent can execute authorized scripts (system-stats.sh, news-fetcher.sh, etc.)

## Key Abstractions

**Configuration Abstraction:**
- Purpose: Centralize all thresholds and settings
- Examples: `config.sh`
- Pattern: All scripts source config.sh; users can override with `~/.config/system-monitor/config`
- Variables: CPU_WARN, MEM_CRIT, DISK_WARN, NEWS_REFRESH_INTERVAL, MONITORED_SERVICES, etc.

**Data Model - Stats JSON:**
- Purpose: Represent system state
- Location: `dashboard/news-cache/stats.json`
- Structure: cpu.load, memory.percent, disk.percent, gpu.temp, uptime.days, services.{docker,postgresql,ollama,ssh}
- Consumed by: Dashboard UI, alert comparisons

**Data Model - News JSON:**
- Purpose: Represent aggregated news articles
- Location: `dashboard/news-cache/news.json`
- Structure: Array of {source, title, url, bias, bias_label, category, timestamp}
- Consumed by: Dashboard UI, news-curator agent

**State Persistence:**
- Purpose: Track previous metric values for change-based alerting
- Location: `$LOG_DIR/.monitor-state.json`
- Pattern: JSON file with last-known values; compare new values against this for thresholds

**Process Management:**
- Purpose: Track background processes
- Location: `dashboard/.refresh.pid` (stats refresh loop), `dashboard/.server.pid` (HTTP server)
- Pattern: Stored PIDs used by stop.sh to cleanly terminate processes

## Entry Points

**Dashboard Web UI:**
- Location: `dashboard/index.html`
- Triggers: User navigates to http://localhost:8787/index.html after running launch.sh
- Responsibilities: Display system vitals, news by category, radio stream player, BotSpace chat

**Launch Script:**
- Location: `dashboard/launch.sh`
- Triggers: User executes manually
- Responsibilities: Start data collection, spawn refresh loop, start HTTP server, open browser

**Health Check Cron:**
- Location: `scripts/health-check.sh`
- Triggers: Daily at 8:00 AM (cron: `0 8 * * *`)
- Responsibilities: Generate daily system health report, log critical issues to alerts.log

**System Monitor Daemon:**
- Location: `scripts/system-monitor-assistant.sh`
- Triggers: Manual execution or background service
- Responsibilities: Continuous monitoring with change-based alerting every 30 seconds

**Dispatch Menu:**
- Location: `dispatch.sh`
- Triggers: User executes manually
- Responsibilities: Show agent menu, launch selected agent with proper context

**News Curator Assistant:**
- Location: `scripts/news-curator-assistant.sh`
- Triggers: User runs in terminal
- Responsibilities: Interactive terminal UI for browsing and filtering news by category

## Error Handling

**Strategy:** Graceful degradation with informative logging

**Patterns:**
- **Missing config**: Scripts fall back to hardcoded defaults (e.g., `DASHBOARD_PORT=8787`)
- **Missing data files**: Dashboard shows "Scanning..." or "N/A" rather than crashing
- **API failures**: curl commands with timeouts; failed fetches silently skip that source
- **GPU monitoring**: Gracefully skips if nvidia-smi not available; sets GPU_TEMP="N/A"
- **Process errors**: stderr redirected to /dev/null by default; alerts logged to alerts.log
- **Failed news fetch**: Dashboard uses stale data from previous fetch rather than failing
- **HTTP server failure**: Warning shown but doesn't block other components

## Cross-Cutting Concerns

**Logging:**
- Alert logs: `logs/alerts.log` (append mode, shared by all monitors)
- Daily reports: `logs/daily-report-YYYY-MM-DD.log` (timestamped files)
- Dashboard data: `news-cache/stats.json` and `news-cache/news.json` (clobbered on each refresh)

**Validation:**
- Title length checks (minimum 5 characters) in news-fetcher
- Regex extraction with fallback parsing in news fetchers
- Service status checks via `systemctl is-active`

**Authentication:**
- No authentication for dashboard (localhost only via bind 127.0.0.1)
- API keys/secrets not embedded; external APIs use public endpoints (Hacker News Firebase, RSS feeds)

**Bias Tagging:**
- All news items include bias score (-20 to +20) and label (Left/Center-Left/Center/Center-Right/Right)
- Bias scores hardcoded per source in `news-fetcher.sh`
- Dashboard displays bias score in news-meta

---

*Architecture analysis: 2026-02-08*

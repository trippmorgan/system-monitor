# System Monitor - Claude Code Instructions

This document provides context for Claude when working with this codebase.

## Project Purpose

**System Monitor** is a personal system monitoring and news aggregation suite designed for Tripp's Ubuntu workstation. It serves two primary functions:

1. **System Health Monitoring** - Automated tracking of CPU, memory, disk, GPU, and services with threshold-based alerting
2. **News Aggregation** - Curated news feeds across 8 categories tailored to personal interests

## Architecture Overview

The project consists of three main components:

### 1. Scripts (`scripts/`)
Shell scripts for automated monitoring and maintenance:
- `health-check.sh` - Daily health report generator (runs via cron at 8 AM)
- `system-monitor-assistant.sh` - Continuous background monitor with change-based alerting
- `cleanup.sh` - System maintenance for freeing disk space (weekly via cron)
- `news-curator-assistant.sh` - Interactive terminal news browser

### 2. Dashboard (`dashboard/`)
Web-based Radio Free Albany with supporting scripts:
- `index.html` - Drudge Report-style 3-column layout with scrolling tickers
- `launch.sh` / `stop.sh` - Process management for HTTP server and refresh loop
- `system-stats.sh` - Generates `stats.json` with current system metrics
- `news-fetcher.sh` - Aggregates news from Hacker News and Google News RSS
- `dashboard.sh` - Terminal-based alternative dashboard

### 3. Logs (`logs/`)
Generated output files:
- `daily-report-YYYY-MM-DD.log` - Health check reports
- `alerts.log` - Real-time alert history
- `cleanup-YYYY-MM-DD.log` - Cleanup operation logs

## Key Design Decisions

1. **No external dependencies** - Uses only bash, curl, python3, and standard Unix tools
2. **JSON data exchange** - Stats and news stored as JSON for dashboard consumption
3. **State-based alerting** - Only alerts when values change to reduce noise
4. **Configurable thresholds** - Warning and critical levels for each metric
5. **Bias labeling** - News sources tagged with political bias indicators

## Important Files

When modifying this project, key files to understand:

| File | Purpose |
|------|---------|
| `scripts/health-check.sh` | Main health check logic and thresholds |
| `scripts/system-monitor-assistant.sh` | Alert thresholds and monitoring loop |
| `dashboard/index.html` | Dashboard UI, JavaScript refresh logic |
| `dashboard/news-fetcher.sh` | News sources and categories |
| `dashboard/system-stats.sh` | System metric collection |

## Thresholds Reference

Current alert thresholds (defined in `system-monitor-assistant.sh`):

| Metric | Warning | Critical |
|--------|---------|----------|
| CPU Load | > 6 | > 8 cores |
| Memory | > 70% | > 90% |
| Disk | > 80% | > 90% |
| GPU Temp | > 70C | > 85C |
| Uptime | > 14 days | > 30 days |

## News Categories

Eight categories tailored to user interests:
- `local` - Albany, Georgia news
- `state` - Georgia state news
- `sports` - College football (CFP, UGA)
- `politics` - Major political news only
- `tech` - Hacker News top stories
- `nature` - Outdoor adventure, national parks
- `fishing` - Fly fishing, duck hunting
- `conservation` - Water policy, wildlife conservation

## Monitored Services

The dashboard tracks these systemd services:
- `docker` - Container runtime
- `postgresql@14-main` - Database server
- `ollama` - Local LLM service
- `ssh` - SSH server
- `nxserver` - NoMachine remote desktop

## Common Tasks

### Adding a new metric to monitoring
1. Add collection logic to `dashboard/system-stats.sh`
2. Update JSON output format
3. Add display logic to `dashboard/index.html`
4. Update ticker and status sections as needed

### Adding a new news category
1. Add fetch logic to `dashboard/news-fetcher.sh` with appropriate RSS URL
2. Add category to JavaScript categorization in `index.html`
3. Add section to HTML layout

### Modifying alert thresholds
Edit the threshold variables at the top of `scripts/system-monitor-assistant.sh`

## Cron Schedule

```
0 8 * * *   health-check.sh   # Daily at 8:00 AM
0 3 * * 0   cleanup.sh        # Sundays at 3:00 AM
```

## Testing Changes

After modifying scripts:
```bash
# Test health check
./scripts/health-check.sh

# Test news fetcher
./dashboard/news-fetcher.sh

# Restart Radio Free Albany to see changes
./dashboard/stop.sh && ./dashboard/launch.sh
```

## Notes for Claude

- This is a personal workstation project, not production software
- User prefers pragmatic solutions over over-engineering
- Shell scripts use bash with standard Unix tools (no jq by design)
- Dashboard uses vanilla JavaScript (no frameworks)
- Keep error messages user-friendly and actionable

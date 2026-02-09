# Technology Stack

**Analysis Date:** 2026-02-08

## Languages

**Primary:**
- Bash 4.0+ - All monitoring scripts, orchestration, data collection
- HTML/CSS/JavaScript - Web dashboard UI (`dashboard/index.html`)
- Python 3 - HTTP server, JSON processing, news aggregation

**Interpreted:**
- Shell scripting (bash) - Primary language for system monitoring and automation

## Runtime

**Environment:**
- Linux (Ubuntu/Debian) with systemd
- Bash 4.0+
- Python 3.x (built-in http.server module)

**Package Manager:**
- APT (for system dependencies)
- No npm/pip dependencies - zero external package management

## Frameworks

**Web:**
- NES.css 2.3.0 (CDN) - 8-bit retro UI styling (`https://unpkg.com/nes.css@2.3.0/css/nes.min.css`)
- Press Start 2P font (Google Fonts CDN) - Arcade-style typography
- Vanilla JavaScript (no frameworks) - Client-side dashboard logic

**Utilities:**
- Python's built-in `http.server` module - Web server for dashboard
- Bash `curl` - HTTP requests for news fetching and API calls
- Bash `bc` - Floating-point arithmetic for load calculations

## Key Dependencies

**Critical (Required):**
- `bash` 4.0+ - Script execution
- `bc` - Floating-point math (`bc -l` for load calculations)
- `curl` - HTTP requests (news fetching, API calls)
- `python3` - HTTP server, JSON processing
- Standard Unix tools: `awk`, `sed`, `grep`, `cut`, `tr`, `wc`, `sort`

**Infrastructure:**
- `systemctl` - Service status monitoring (docker, postgresql@14-main, ollama, ssh)
- `free` - Memory usage metrics
- `df` - Disk usage metrics
- `uptime` - System uptime
- `nproc` - CPU core count
- `ss` or `netstat` - Network connection counting
- `journalctl` - System journal logs

**GPU (Optional):**
- `nvidia-smi` - NVIDIA GPU monitoring (gracefully disabled if unavailable)

**Optional:**
- `jq` - Faster JSON parsing (fallback to Python/grep parsing if missing)
- `xdg-open` / `firefox` / `google-chrome` - Browser launching for dashboard

## Configuration

**Environment:**
- Centralized in `config.sh` with environment variable exports
- User overrides via `~/.config/system-monitor/config` (optional)
- No `.env` files required - all configuration in shell scripts

**Build:**
- No build step required
- Scripts are executable bash files
- HTML/CSS/JavaScript served as-is
- All data exchange via JSON files

**Key Configuration Files:**
- `config.sh` - Thresholds (CPU, memory, disk, GPU), timing intervals, monitored services, feature flags
- `dashboard/index.html` - UI layout, refresh intervals, styling
- `CLAUDE.md` - Project documentation and context

## Platform Requirements

**Development:**
- Linux workstation (Ubuntu/Debian preferred)
- bash 4.0+
- Common Unix utilities (standard on Linux)

**Production (Runtime):**
- Ubuntu/Debian Linux with systemd
- Python 3.x
- Standard system utilities
- Port 8787 available for dashboard HTTP server
- Optional: NVIDIA GPU with nvidia-smi for GPU monitoring

**System Services Monitored:**
- `docker` - Container runtime
- `postgresql@14-main` - PostgreSQL 14 database
- `ollama` - Local LLM service
- `ssh` - SSH server
- `nxserver` - NoMachine remote desktop (mentioned in CLAUDE.md)

## Data Exchange

**JSON Data Files:**
- `dashboard/news-cache/news.json` - Aggregated news items (array of objects)
- `dashboard/news-cache/stats.json` - System metrics snapshot
- `dashboard/news-cache/meta.json` - Cache metadata (timestamp)

**JSON Structure Examples:**

News item:
```json
{
  "source": "Hacker News",
  "title": "Article Title",
  "url": "https://...",
  "bias": 5,
  "bias_label": "Center",
  "category": "tech",
  "timestamp": 1707434521
}
```

System stats:
```json
{
  "timestamp": "2026-02-08 14:30:00",
  "cpu": { "load": "2.5", "cores": "8" },
  "memory": { "used": "8192", "total": "16384", "percent": "50" },
  "disk": { "percent": "45", "available": "250G" },
  "gpu": { "temp": "65", "util": "45", "mem": "2048/8192" },
  "uptime": { "text": "3 weeks, 2 days", "days": "23" },
  "network": { "connections": "45" },
  "services": { "docker": "active", "postgresql": "active", "ollama": "inactive", "ssh": "active" },
  "alerts": { "count": "3", "recent": "..." }
}
```

## API Integration Points

**External APIs (Read-Only):**
- Hacker News Firebase API - `https://hacker-news.firebaseio.com/v0/topstories.json`
- Google News RSS - `https://news.google.com/rss/search?q=...`
- Major news sources (CBS, NBC, Fox, NPR, Daily Wire, Breitbart via RSS feeds)

**No Authentication Required:**
- All news feeds are public RSS/JSON endpoints
- No API keys stored or required
- Graceful degradation if APIs are unavailable

## Cron/Scheduling

**Automated Tasks:**
- Daily health check at 8:00 AM: `0 8 * * * /home/tripp/system-monitor/scripts/health-check.sh`
- Weekly cleanup at 3:00 AM (Sunday): `0 3 * * 0 /home/tripp/system-monitor/scripts/cleanup.sh`

**Background Processes (via launch.sh):**
- System stats refresh: Every 30 seconds (configurable via `CHECK_INTERVAL`)
- News refresh: Every 2 minutes (configurable via `NEWS_REFRESH_INTERVAL`)
- HTTP server: Continuous (Python http.server on port 8787)

## File Storage

**Local File System Only:**
- Logs: `~/system-monitor/logs/` (daily reports, alerts, cleanup logs)
- News cache: `~/system-monitor/dashboard/news-cache/` (JSON files)
- Scripts: `~/system-monitor/scripts/` and `~/system-monitor/dashboard/`

**No Database:**
- Project uses JSON files for all data storage
- No SQL database required
- No PostgreSQL connection from monitoring code (PostgreSQL is only monitored as a service)

---

*Stack analysis: 2026-02-08*

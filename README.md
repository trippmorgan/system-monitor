# System Monitor

A personal system monitoring and news aggregation suite for Ubuntu workstations. Features a Drudge Report-style web dashboard, automated health checks, and curated news feeds.

---

## Quick Start

```bash
# 1. Validate your installation
~/system-monitor/scripts/validate.sh

# 2. Launch the web-based Command Center (recommended)
~/system-monitor/dashboard/launch.sh

# Or use the terminal dashboard for a quick view
~/system-monitor/dashboard/dashboard.sh

# Run a manual health check
~/system-monitor/scripts/health-check.sh

# Browse news interactively
~/system-monitor/scripts/news-curator-assistant.sh
```

**After launching the Command Center**, your browser opens to `http://localhost:8787` with a live dashboard showing system metrics and news.

---

## Installation

### Requirements

**Required:**
- bash 4.0+
- bc (for floating-point math)
- curl (for news fetching)
- python3 (for HTTP server and JSON processing)
- Standard Unix tools (awk, sed, grep)

**Optional (recommended):**
- jq (faster JSON parsing)
- nvidia-smi (for GPU monitoring)

### Install Steps

```bash
# 1. Clone or copy to your home directory
git clone <repo-url> ~/system-monitor
# or
cp -r system-monitor ~/system-monitor

# 2. Make scripts executable
chmod +x ~/system-monitor/scripts/*.sh
chmod +x ~/system-monitor/dashboard/*.sh

# 3. Install dependencies (Ubuntu/Debian)
sudo apt install bc curl jq

# 4. Validate installation
~/system-monitor/scripts/validate.sh

# 5. (Optional) Add aliases to ~/.bashrc
echo 'alias command-center="~/system-monitor/dashboard/launch.sh"' >> ~/.bashrc
echo 'alias dashboard="~/system-monitor/dashboard/dashboard.sh"' >> ~/.bashrc
echo 'alias news-desk="~/system-monitor/scripts/news-curator-assistant.sh"' >> ~/.bashrc
source ~/.bashrc

# 6. (Optional) Set up cron jobs
crontab -e
# Add:
# 0 8 * * * /home/$USER/system-monitor/scripts/health-check.sh
# 0 3 * * 0 /home/$USER/system-monitor/scripts/cleanup.sh
```

---

## Features

### System Monitoring
- **CPU, Memory, Disk, GPU** - Real-time metrics with threshold-based alerts
- **Service Status** - Tracks Docker, PostgreSQL, Ollama, SSH, and more
- **Automated Health Checks** - Daily reports with issue detection
- **Background Monitoring** - Continuous monitoring with change-based alerts

### News Aggregation
- **8 Categories** - Local (Albany GA), Georgia State, Politics, Tech, Sports, Nature, Fishing/Hunting, Conservation
- **Bias Labels** - Each story shows source bias (Left/Center/Right)
- **Hacker News Integration** - Tech news from the front page
- **Google News RSS** - Regional and topical news feeds

### Dashboard Options
- **Command Center** - Browser-based Drudge-style 3-column layout with scrolling tickers
- **Terminal Dashboard** - Quick command-line view with color-coded status
- **News Desk** - Interactive terminal menu for browsing news categories

---

## Directory Structure

```
~/system-monitor/
├── config.sh                   # Centralized configuration (thresholds, paths, features)
├── dispatch.sh                 # Multi-agent selection menu
├── README.md                   # This file
├── CLAUDE.md                   # AI assistant context file
│
├── agents/                     # Specialized Claude agents
│   ├── system-tech/            # System monitoring agent
│   │   └── CLAUDE.md
│   ├── news-curator/           # News curation agent
│   │   └── CLAUDE.md
│   └── orchestrator/           # Request routing agent
│       └── CLAUDE.md
│
├── scripts/                    # Automation and monitoring scripts
│   ├── health-check.sh         # Daily health report generator
│   ├── system-monitor-assistant.sh  # Background monitor with alerts
│   ├── cleanup.sh              # System maintenance and cache cleanup
│   ├── news-curator-assistant.sh    # Interactive news browser
│   └── validate.sh             # Installation validation script
│
├── dashboard/                  # Web dashboard and data fetchers
│   ├── index.html              # Main Command Center web interface
│   ├── launch.sh               # Starts everything (server + refresh)
│   ├── stop.sh                 # Stops background processes
│   ├── dashboard.sh            # Terminal-based dashboard
│   ├── system-stats.sh         # Generates stats.json for dashboard
│   ├── news-fetcher.sh         # Fetches and categorizes news
│   └── news-cache/             # Cached JSON data
│       ├── stats.json          # Current system metrics
│       ├── news.json           # Aggregated news items
│       └── meta.json           # Last update timestamp
│
└── logs/                       # Generated logs and reports
    ├── daily-report-YYYY-MM-DD.log  # Daily health reports
    ├── alerts.log              # Real-time alert history
    └── cleanup-YYYY-MM-DD.log  # Cleanup operation logs
```

---

## Scripts Reference

### scripts/health-check.sh

Comprehensive system health report generator. Runs daily via cron.

**What it checks:**
- CPU load vs core count
- Memory and swap usage (alerts at 90%+ memory, 50%+ swap)
- Disk usage (warns at 85%, critical at 90%)
- GPU temperature and VRAM (alerts at 80°C+)
- System uptime (recommends reboot after 30 days)
- Failed systemd services
- Top memory/CPU consuming processes
- Network connections
- Journal error count (alerts at 100+ errors/24h)

**Output:** `~/system-monitor/logs/daily-report-YYYY-MM-DD.log`

**Usage:**
```bash
~/system-monitor/scripts/health-check.sh
```

---

### scripts/system-monitor-assistant.sh

Background monitoring daemon with intelligent alerting.

**Features:**
- Runs continuously, checking every 30 seconds
- Only alerts when values change (reduces noise)
- Configurable thresholds for CPU, memory, disk, GPU
- Monitors key services (Docker, PostgreSQL, Ollama)
- Auto-refreshes dashboard data when changes detected

**Thresholds:**
| Metric | Warning | Critical |
|--------|---------|----------|
| CPU Load | > 6 | > 8 |
| Memory | > 70% | > 90% |
| Disk | > 80% | > 90% |
| GPU Temp | > 70°C | > 85°C |

**Usage:**
```bash
# Run in foreground
~/system-monitor/scripts/system-monitor-assistant.sh

# Run in background
nohup ~/system-monitor/scripts/system-monitor-assistant.sh &
```

---

### scripts/cleanup.sh

System maintenance script for freeing disk space.

**What it cleans:**
- Old monitoring logs (30+ days)
- Browser caches (Chrome, Chromium, Firefox)
- Thumbnail cache
- APT package cache (requires sudo)
- Journal logs (limits to 500MB, requires sudo)
- Temp files older than 7 days

**Usage:**
```bash
~/system-monitor/scripts/cleanup.sh
```

---

### scripts/news-curator-assistant.sh

Interactive terminal-based news browser.

**Menu options:**
1. Refresh all news feeds
2. Show headlines by category
3. Local News (Albany, GA)
4. Georgia State News
5. College Football
6. Nature & Outdoors
7. Fly Fishing & Hunting
8. Tech News
9. Show all headlines
0. Exit
c. Chat with Claude about the news

**Usage:**
```bash
~/system-monitor/scripts/news-curator-assistant.sh
# or use the alias:
news-desk
```

---

### scripts/validate.sh

Installation validation and diagnostic script.

**What it checks:**
- Required dependencies (bash, bc, curl, python3, awk)
- Optional dependencies (jq, nvidia-smi)
- Configuration file validity
- Directory structure and permissions
- Script executability
- Basic functionality (CPU, memory, disk, network readings)
- Port availability

**Usage:**
```bash
~/system-monitor/scripts/validate.sh
```

**Output:** Color-coded pass/fail/warning status for each check, with summary and quick-fix suggestions.

---

### dashboard/launch.sh

Starts the complete Command Center ecosystem.

**What it does:**
1. Kills any existing dashboard processes
2. Fetches initial system stats and news
3. Starts background refresh loop (stats every 30s, news every 5min)
4. Starts Python HTTP server on port 8787
5. Opens dashboard in your default browser

**Usage:**
```bash
~/system-monitor/dashboard/launch.sh
# or use the alias:
command-center
```

**To stop:**
```bash
~/system-monitor/dashboard/stop.sh
```

---

### dashboard/dashboard.sh

Terminal-based dashboard for quick system overview.

**Displays:**
- System status (CPU, Memory, Disk, GPU, Uptime, Network)
- Service status with colored indicators
- Recent alerts
- Top processes by CPU
- Hacker News headlines (cached for 1 hour)

**Usage:**
```bash
~/system-monitor/dashboard/dashboard.sh
# or use the alias:
dashboard
```

---

## Cron Jobs

The following cron jobs are configured:

```cron
# Daily health check at 8:00 AM
0 8 * * * /home/tripp/system-monitor/scripts/health-check.sh

# Weekly cleanup on Sunday at 3:00 AM
0 3 * * 0 /home/tripp/system-monitor/scripts/cleanup.sh
```

To edit: `crontab -e`

---

## Aliases

Add these to your `~/.bashrc` for convenience:

```bash
alias command-center='~/system-monitor/dashboard/launch.sh'
alias dashboard='~/system-monitor/dashboard/dashboard.sh'
alias news-desk='~/system-monitor/scripts/news-curator-assistant.sh'
```

---

## Configuration

All configuration is centralized in `config.sh`. Scripts automatically load this file and fall back to sensible defaults if it's missing.

### config.sh

```bash
# Paths
export MONITOR_HOME="$HOME/system-monitor"
export LOG_DIR="$MONITOR_HOME/logs"
export DASHBOARD_DIR="$MONITOR_HOME/dashboard"

# Alert Thresholds
export CPU_WARN=6           # Warn when load exceeds 6
export CPU_CRIT=8           # Critical when load exceeds 8
export MEM_WARN=70          # Warn at 70% memory usage
export MEM_CRIT=90          # Critical at 90% memory usage
export DISK_WARN=80         # Warn at 80% disk usage
export DISK_CRIT=90         # Critical at 90% disk usage
export GPU_TEMP_WARN=70     # Warn at 70°C GPU temp
export GPU_TEMP_CRIT=85     # Critical at 85°C GPU temp
export UPTIME_CRIT=30       # Recommend reboot after 30 days

# Timing
export CHECK_INTERVAL=30          # Seconds between monitor checks
export NEWS_REFRESH_INTERVAL=5    # Minutes between news refreshes
export DASHBOARD_PORT=8787        # HTTP server port

# Feature Flags
export ENABLE_GPU_MONITORING=1    # Set to 0 to disable GPU checks
export ENABLE_NEWS_FETCHING=1     # Set to 0 to disable news
export ENABLE_BROWSER_OPEN=1      # Set to 0 to skip auto-open

# News
export LOCAL_NEWS_SEARCH="Albany+Georgia"  # Customize for your area
```

### User Overrides

Create `~/.config/system-monitor/config` to override any setting without modifying the main config:

```bash
mkdir -p ~/.config/system-monitor
cat > ~/.config/system-monitor/config << 'EOF'
# My custom settings
export CPU_WARN=4
export LOCAL_NEWS_SEARCH="Austin+Texas"
export DASHBOARD_PORT=9000
EOF
```

### News Categories

News sources and categories are defined in `dashboard/news-fetcher.sh`. Each category uses Google News RSS with specific search terms. Enable/disable categories in config.sh:

```bash
export NEWS_TECH_ENABLED=1
export NEWS_LOCAL_ENABLED=1
export NEWS_SPORTS_ENABLED=1
# etc.
```

---

## Dependencies

**Required:**
- bash 4.0+
- bc (floating-point math)
- curl (news fetching)
- python3 (HTTP server and JSON processing)
- Standard Unix tools (awk, sed, grep)

**Optional:**
- jq (faster, more robust JSON parsing)
- nvidia-smi (for GPU monitoring)
- xdg-open / firefox / google-chrome (for auto-opening dashboard)

---

## Security

### HTTP Server

The Command Center uses Python's built-in HTTP server (`python3 -m http.server`). This is designed for **local use only**.

**Current protections:**
- Server binds to `127.0.0.1` only (not accessible from network)
- No authentication (relies on localhost binding)
- Serves static files only (no server-side code execution)

**Important considerations:**
- **Do not expose to the internet** - The HTTP server has no authentication
- **Local network access** - Even localhost binding may be accessible via SSH tunnels
- **No HTTPS** - All traffic is unencrypted (fine for localhost)

**If you need remote access:**

1. **SSH Tunnel (Recommended):**
   ```bash
   # From remote machine, create tunnel to your workstation
   ssh -L 8787:localhost:8787 user@workstation
   # Then open http://localhost:8787 on remote machine
   ```

2. **VPN:** Access your home network via VPN, then use the local IP

3. **Nginx Reverse Proxy (Advanced):**
   ```nginx
   location /dashboard/ {
       proxy_pass http://127.0.0.1:8787/;
       auth_basic "System Monitor";
       auth_basic_user_file /etc/nginx/.htpasswd;
   }
   ```

### File Permissions

The monitor reads system information that's world-readable:
- `/proc/loadavg`, `/proc/uptime` - CPU and uptime
- `free`, `df` - Memory and disk
- `nvidia-smi` - GPU (requires appropriate permissions)
- `systemctl` - Service status

No elevated privileges required for basic monitoring. Cleanup script uses `sudo` optionally for apt and journal cleanup.

### Data Storage

- Logs stored in `~/system-monitor/logs/` (user-readable only)
- News cache stored in `~/system-monitor/dashboard/news-cache/`
- No sensitive data is collected or stored
- No external services contacted except news APIs (Google News RSS, Hacker News Firebase)

---

## Logs

| Log File | Purpose | Rotation |
|----------|---------|----------|
| `logs/daily-report-*.log` | Daily health check reports | Auto-cleaned after 30 days |
| `logs/alerts.log` | Real-time alerts | Manual cleanup |
| `logs/cleanup-*.log` | Cleanup operation records | Auto-cleaned after 30 days |

---

## Troubleshooting

**First step - run validation:**
```bash
~/system-monitor/scripts/validate.sh
```

This checks all dependencies, permissions, and basic functionality.

**Dashboard won't load:**
```bash
# Check if server is running
curl http://localhost:8787/news-cache/stats.json

# Check port usage
ss -tuln | grep 8787

# Restart everything
~/system-monitor/dashboard/stop.sh
~/system-monitor/dashboard/launch.sh
```

**No news appearing:**
```bash
# Manually fetch news
~/system-monitor/dashboard/news-fetcher.sh

# Check the cache
cat ~/system-monitor/dashboard/news-cache/news.json

# Test network connectivity
curl -s "https://hacker-news.firebaseio.com/v0/topstories.json" | head -c 50
```

**High alert count:**
```bash
# View recent alerts
tail -20 ~/system-monitor/logs/alerts.log

# Clear old alerts (careful!)
> ~/system-monitor/logs/alerts.log
```

**Config not loading:**
```bash
# Test config file
source ~/system-monitor/config.sh && echo "CPU_WARN=$CPU_WARN"

# Check for syntax errors
bash -n ~/system-monitor/config.sh
```

---

## Multi-Agent Architecture

This project includes three specialized Claude Code agents, each scoped to specific tasks.

### Agents

| Agent | Purpose | Directory |
|-------|---------|-----------|
| System Tech | Health checks, services, logs, diagnostics | `agents/system-tech/` |
| News Curator | Headlines, news summaries, RSS feeds | `agents/news-curator/` |
| Orchestrator | Routes you to the right agent | `agents/orchestrator/` |

### Usage

**Quick dispatch menu:**
```bash
~/system-monitor/dispatch.sh
```

**Direct access:**
```bash
# System questions
cd ~/system-monitor/agents/system-tech && claude

# News questions
cd ~/system-monitor/agents/news-curator && claude

# Not sure which?
cd ~/system-monitor/agents/orchestrator && claude
```

**Full access (no restrictions):**
```bash
cd ~/system-monitor && claude
```

### How It Works

Each agent directory contains a `CLAUDE.md` file that scopes what Claude can do:
- System Tech can only use system scripts and read system logs
- News Curator can only use news scripts and read news cache
- Orchestrator can only advise - it cannot run anything

This prevents accidental cross-contamination and keeps each agent focused.

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run `scripts/validate.sh` to ensure everything works
4. Submit a pull request

---

## License

MIT License - Use freely, modify as needed, no warranty provided.

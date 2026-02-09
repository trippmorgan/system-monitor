# Coding Conventions

**Analysis Date:** 2026-02-08

## Naming Patterns

**Files:**
- Shell scripts: `lowercase-with-hyphens.sh` (e.g., `health-check.sh`, `system-stats.sh`, `news-fetcher.sh`)
- HTML: `index.html` (standard web convention)
- JSON outputs: `lowercase.json` (e.g., `stats.json`, `news.json`, `feedback.json`)

**Functions (Bash):**
- Command-style: `verb_noun()` in uppercase sections with underscores (e.g., `add_item()`, `get_current_stats()`, `compare_and_alert()`)
- Logging functions: `log_alert()`, `log_info()`, `log_error()`
- Helper functions: `json_get()`, `show_menu()`, `refresh_news()`
- Declared at top of script in comment sections

**Variables (Bash):**
- Constants: `UPPERCASE_WITH_UNDERSCORES` (e.g., `SCRIPT_DIR`, `CONFIG_FILE`, `ALERT_LOG`)
- Exported config: `export VAR_NAME` (sourced from `config.sh`)
- Local variables: `lowercase_with_underscores` in functions
- Computed values: Computed inline or with short descriptive names (e.g., `load`, `mem_pct`, `disk_pct`)

**Types (JavaScript/HTML):**
- HTML element IDs: `kebab-case-with-prefix` (e.g., `cpu-val`, `mem-bar`, `disk-val`, `news-local`, `botspace-feed`)
- CSS classes: `kebab-case` (e.g., `arcade-header`, `panel-title`, `news-item`, `chat-msg`)
- Variables: `camelCase` (e.g., `cpuVal`, `memVal`, `diskVal`, `allNews`)
- Object properties: `camelCase` (e.g., `timestamp`, `bias_label`, `category`)

## Code Style

**Formatting:**
- No automatic formatter configured (no .eslintrc, .prettierrc, tsconfig.json)
- Bash: Uses bash formatting conventions with consistent indentation (4 spaces implied by code)
- HTML/CSS: 4-space indentation in inline styles
- JavaScript: 4-space indentation, semicolons at statement ends

**Linting:**
- No linter configured
- Code relies on manual review and bash syntax checking via `validate.sh`

**Comments:**
- Bash header blocks: Large sectional headers with `#` dividers (70+ char lines)
  ```bash
  #===============================================================================
  # Section Title
  #===============================================================================
  ```
- Subsection headers: Medium dividers (65 char lines)
  ```bash
  #-----------------------------------------------------------------------
  # Subsection Title
  #-----------------------------------------------------------------------
  ```
- Inline comments: Sparse, used mainly for complex logic or non-obvious intent
- Function comments: Documented in header blocks above function definition
- Function header format:
  ```bash
  # functionName() - Short description
  # Args: $1 = description, $2 = description
  # Returns: description or "nothing"
  # Usage: example usage
  ```

## Import Organization

**Bash:**
- Configuration sourced at script start:
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CONFIG_FILE="$SCRIPT_DIR/../config.sh"
  if [ -f "$CONFIG_FILE" ]; then
      source "$CONFIG_FILE"
  else
      # Fallback defaults
  fi
  ```
- Pattern: Always define paths relative to script location
- Pattern: Always provide fallback defaults if config missing

**JavaScript:**
- Inline in HTML `<script>` tags at end of document (no separate files)
- Fetch order: Stats first, then News, then Chat
- No external npm dependencies

**HTML:**
- Single-file structure: CSS in `<style>` tags (inline), JavaScript in `<script>` tags (inline)
- External libraries via CDN: `unpkg.com` for CSS (NES.css), `googleapis.com` for fonts
- Structure: Head (meta, links, inline styles), Body (HTML content, inline script at bottom)

## Error Handling

**Patterns (Bash):**
- Silent failure with defaults: `command 2>/dev/null || echo "default"`
- Graceful degradation: `if command -v nvidia-smi &>/dev/null; then`
- Error redirection: `2>/dev/null` to suppress stderr
- Conditional logic: `if [ -f "$FILE" ]; then SOURCE; else USE_DEFAULTS; fi`
- Exit codes: `validate.sh` returns 0 (pass) or 1 (fail) based on check counts

**Pattern (JavaScript):**
- Try/catch for fetch operations with silent fallback:
  ```javascript
  try {
      const res = await fetch(...);
      // Process data
  } catch(e) {
      console.log("Offline - Using Mock Data");
  }
  ```
- No error callbacks, assumes offline gracefully with empty/default UI

## Logging

**Framework:** Bash `echo`, redirected to files or stdout

**Patterns:**
- Alert logs (critical): `alert()` function writes to `alerts.log` and prints
- Info logs (informational): `info()` function writes to daily report and prints
- Error logs (stderr): `log_error()` function writes to stderr
- Chat-style logging: `chat-msg` divs in DOM (dashboard only)

**Logging function locations:**
- `scripts/health-check.sh`: `alert()`, `info()`
- `scripts/system-monitor-assistant.sh`: `log_alert()`, `log_info()`, `log_error()`
- `scripts/cleanup.sh`: `log()`
- All use consistent timestamp format: `YYYY-MM-DD HH:MM:SS`

## Comments

**When to Comment:**
- Function headers always present (purpose, args, returns)
- Sectional dividers for major code blocks
- Complex shell logic (e.g., floating-point comparisons with `bc`)
- Non-obvious intent or workarounds

**When NOT to Comment:**
- Obvious variable assignments
- Standard control flow
- Simple loops

**JSDoc/TSDoc:**
- Not used (no TypeScript, minimal JavaScript)
- Bash functions use inline doc format in header blocks

## Function Design

**Size:** Typically 5-30 lines for utility functions, up to 50+ lines for main loops
- `get_current_stats()` (`40 lines`): Collects all metrics at once
- `add_item()` (`15 lines`): Adds single news item
- Main monitoring loop: Infinite `while true` in launching script

**Parameters:**
- Bash functions typically take 1-3 positional args
- Arguments prefixed with `$1`, `$2`, documented in header
- JavaScript functions take object or simple parameters

**Return Values:**
- Bash functions: Echo output, use exit codes for validation
- JavaScript functions: Return objects/arrays or `undefined`
- `json_get()` pattern: Return parsed value or `empty` with jq

## Module Design

**Exports:**
- Bash: All functions in each script, sourced variables from `config.sh`
- JavaScript: Functions directly in script context (loadArcadeData, renderArcadeList, postChat)
- HTML: Single module - all logic in one file

**Barrel Files:**
- Not applicable - no module bundling or explicit exports
- `config.sh` acts as centralized config exports (all variables)

**File structure pattern:**
```
script.sh
├── Header comment (purpose, usage, output)
├── Configuration loading section
├── Helper functions section
├── Main logic section
└── Execution at script level
```

---

*Convention analysis: 2026-02-08*

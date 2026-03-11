#===============================================================================
# news-curator-assistant.ps1 - Interactive News Browser (Windows)
#===============================================================================
# PURPOSE:
#   Interactive terminal-based news desk for browsing curated news feeds.
#   Menu-driven access to 8 news categories with Claude integration.
#
# USAGE:
#   .\system-monitor\scripts\news-curator-assistant.ps1
#===============================================================================

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MonitorHome = Split-Path -Parent $ScriptDir
$NewsDir = Join-Path $MonitorHome "dashboard\news-cache"
$NewsJson = Join-Path $NewsDir "news.json"
$Fetcher = Join-Path $MonitorHome "dashboard\news-fetcher.ps1"

# Load config for Python path
$ConfigFile = Join-Path (Split-Path -Parent $ScriptDir) "config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$PythonCmd = if ($PYTHON_EXE) { $PYTHON_EXE } else { $null }

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "+================================================================+" -ForegroundColor Cyan
    Write-Host "|                   NEWS DESK - COMMAND CENTER                   |" -ForegroundColor Cyan
    Write-Host "|              Your Personal News Curator Assistant              |" -ForegroundColor Cyan
    Write-Host "+================================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {
    Write-Host "What would you like to do?" -ForegroundColor White
    Write-Host ""
    Write-Host "  1) Refresh all news feeds" -ForegroundColor Cyan
    Write-Host "  2) Show headlines by category"
    Write-Host "  3) Show Local News (Albany, GA)"
    Write-Host "  4) Show Georgia State News"
    Write-Host "  5) Show College Football"
    Write-Host "  6) Show Nature & Outdoors"
    Write-Host "  7) Show Fly Fishing & Hunting"
    Write-Host "  8) Show Tech News"
    Write-Host "  9) Show all headlines"
    Write-Host "  0) Exit"
    Write-Host ""
    Write-Host "  c) Chat about the news (opens Claude)" -ForegroundColor Yellow
    Write-Host ""
}

function Invoke-RefreshNews {
    Write-Host "Fetching fresh news from all sources..." -ForegroundColor Yellow
    Write-Host ""
    if (Test-Path $Fetcher) {
        & $Fetcher
    } else {
        Write-Host "News fetcher not found at $Fetcher" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "News refreshed!" -ForegroundColor Green
    Write-Host ""
}

function Show-Category {
    param(
        [string]$Category,
        [string]$Title
    )

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Magenta
    Write-Host ""

    if (-not (Test-Path $NewsJson)) {
        Write-Host "No news data. Run refresh first." -ForegroundColor Red
        return
    }

    if (-not $PythonCmd) {
        Write-Host "Python not found. Cannot display news." -ForegroundColor Red
        return
    }

    $PyScript = @"
import json
try:
    with open(r'$($NewsJson -replace "'", "\'")') as f:
        news = json.load(f)
    items = [n for n in news if n.get('category') == '$Category']
    if not items:
        print('  No news in this category.')
    else:
        for i, item in enumerate(items[:10], 1):
            title = item.get('title', 'No title')[:80]
            source = item.get('source', 'Unknown')
            bias = item.get('bias_label', '')
            url = item.get('url', '')
            print(f'  {i}. {title}')
            print(f'     {source} [{bias}]')
            if url:
                short_url = url[:60] + '...' if len(url) > 60 else url
                print(f'     {short_url}')
            print()
except Exception as e:
    print(f'Error: {e}')
"@
    & $PythonCmd -c $PyScript
}

function Show-AllHeadlines {
    Write-Host ""
    Write-Host "=== ALL HEADLINES ===" -ForegroundColor Magenta
    Write-Host ""

    if (-not (Test-Path $NewsJson)) {
        Write-Host "No news data. Run refresh first." -ForegroundColor Red
        return
    }

    if (-not $PythonCmd) {
        Write-Host "Python not found." -ForegroundColor Red
        return
    }

    $PyScript = @"
import json
try:
    with open(r'$($NewsJson -replace "'", "\'")') as f:
        news = json.load(f)
    categories = {}
    for item in news:
        cat = item.get('category', 'other')
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(item)
    cat_names = {
        'local': 'LOCAL (Albany, GA)',
        'state': 'GEORGIA STATE',
        'sports': 'COLLEGE FOOTBALL',
        'politics': 'POLITICS (Major)',
        'tech': 'TECH & WORLD',
        'nature': 'NATURE & OUTDOORS',
        'fishing': 'FLY FISHING & HUNTING',
        'conservation': 'CONSERVATION',
        'breaking': 'BREAKING / WORLD'
    }
    for cat in ['local', 'state', 'sports', 'nature', 'fishing', 'conservation', 'tech', 'politics', 'breaking']:
        if cat in categories and categories[cat]:
            print(f'{cat_names.get(cat, cat.upper())}')
            for item in categories[cat][:4]:
                title = item.get('title', '')[:70]
                source = item.get('source', '')
                print(f'  * {title}')
                print(f'    {source}')
            print()
except Exception as e:
    print(f'Error: {e}')
"@
    & $PythonCmd -c $PyScript
}

function Show-Summary {
    Write-Host "News Summary:" -ForegroundColor White
    if ((Test-Path $NewsJson) -and $PythonCmd) {
        $PyScript = @"
import json
with open(r'$($NewsJson -replace "'", "\'")') as f:
    d = json.load(f)
cats = {}
for item in d:
    c = item.get('category', 'other')
    cats[c] = cats.get(c, 0) + 1
print(f'  Total stories: {len(d)}')
for k, v in sorted(cats.items()):
    print(f'    {k}: {v}')
"@
        & $PythonCmd -c $PyScript 2>$null
    } else {
        Write-Host "  No news data yet."
    }
    Write-Host ""
}

function Open-ClaudeChat {
    Write-Host ""
    Write-Host "Starting Claude for news discussion..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can ask Claude about:"
    Write-Host "  - Summarize today's news"
    Write-Host "  - What's happening in Albany?"
    Write-Host "  - Any big college football news?"
    Write-Host "  - What's new in conservation?"
    Write-Host ""
    Write-Host "Press Enter to open Claude, or 'q' to go back..." -ForegroundColor Yellow
    $response = Read-Host
    if ($response -ne 'q') {
        if (Get-Command claude -ErrorAction SilentlyContinue) {
            & claude
        } else {
            Write-Host "Claude CLI not found. Install from https://claude.ai/code" -ForegroundColor Red
        }
    }
}

#===============================================================================
# Main Interactive Loop
#===============================================================================
Show-Banner
Show-Summary

while ($true) {
    Show-Menu
    $choice = Read-Host "Choose option"

    switch ($choice) {
        '1' { Invoke-RefreshNews }
        '2' { Show-Summary }
        '3' { Show-Category -Category "local" -Title "LOCAL NEWS - Albany, GA" }
        '4' { Show-Category -Category "state" -Title "GEORGIA STATE NEWS" }
        '5' { Show-Category -Category "sports" -Title "COLLEGE FOOTBALL" }
        '6' { Show-Category -Category "nature" -Title "NATURE & OUTDOORS" }
        '7' { Show-Category -Category "fishing" -Title "FLY FISHING & HUNTING" }
        '8' { Show-Category -Category "tech" -Title "TECH & WORLD NEWS" }
        '9' { Show-AllHeadlines }
        '0' { Write-Host "Goodbye!"; exit 0 }
        'c' { Open-ClaudeChat }
        'C' { Open-ClaudeChat }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
    Show-Banner
}

#===============================================================================
# news-fetcher.ps1 - News Fetcher for Radio Free Albany (Windows)
#===============================================================================
# PURPOSE:
#   Fetches local Albany & national news via RSS feeds using embedded Python.
#   Outputs: dashboard/news-cache/news.json
#
# USAGE:
#   .\system-monitor\dashboard\news-fetcher.ps1
#===============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CacheDir = Join-Path $ScriptDir "news-cache"
$OutputFile = Join-Path $CacheDir "news.json"

if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

Write-Host "Scanning frequencies..."

# Load config for Python path
$ConfigFile = Join-Path (Split-Path -Parent $ScriptDir) "config.ps1"
if (Test-Path $ConfigFile) { . $ConfigFile }

$PythonCmd = if ($PYTHON_EXE) { $PYTHON_EXE } else { $null }

if (-not $PythonCmd) {
    Write-Host "ERROR: Python not found. Install from https://python.org" -ForegroundColor Red
    exit 1
}

$PythonScript = @"
import urllib.request
import json
import xml.etree.ElementTree as ET
import time
import ssl
import re
import html
import tempfile
import os

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

feeds = [
    # LOCAL - Albany, GA
    {'url': 'https://albanyherald.com/feed/', 'category': 'local', 'source': 'Albany Herald', 'bias_label': 'CENTER'},
    {'url': 'https://www.walb.com/arc/outboundfeeds/rss/?outputType=xml', 'category': 'local', 'source': 'WALB News 10', 'bias_label': 'CENTER'},
    {'url': 'https://www.wtxl.com/news/local-news.rss', 'category': 'local', 'source': 'WTXL Local', 'bias_label': 'CENTER'},
    {'url': 'https://news.google.com/rss/search?q=%22Albany+GA%22&hl=en-US&gl=US&ceid=US:en', 'category': 'local', 'source': 'Google News (Albany)', 'bias_label': 'MIXED', 'max_items': 3},

    # STATE - Georgia
    {'url': 'https://www.gpb.org/rss/news', 'category': 'state', 'source': 'GPB News', 'bias_label': 'CENTER'},
    {'url': 'https://news.google.com/rss/search?q=Georgia+state+government+OR+%22Georgia+legislature%22&hl=en-US&gl=US&ceid=US:en', 'category': 'state', 'source': 'Google News (GA)', 'bias_label': 'MIXED', 'max_items': 5},

    # BREAKING
    {'url': 'http://feeds.bbci.co.uk/news/world/rss.xml', 'category': 'breaking', 'source': 'BBC World', 'bias_label': 'CENTER-LEFT'},
    {'url': 'https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en', 'category': 'breaking', 'source': 'Google News (Top)', 'bias_label': 'MIXED', 'max_items': 5},

    # TECH
    {'url': 'https://hnrss.org/frontpage', 'category': 'tech', 'source': 'Hacker News', 'bias_label': 'NEUTRAL'},

    # POLITICS
    {'url': 'https://news.google.com/rss/topics/CAAqIggKIhxDQkFTRHdvSkwyMHZNRFZ4ZERBU0FoSnBkQ2dBUAE?hl=en-US&gl=US&ceid=US:en', 'category': 'politics', 'source': 'Google News (Politics)', 'bias_label': 'MIXED', 'max_items': 5},
    {'url': 'https://feeds.bbci.co.uk/news/politics/rss.xml', 'category': 'politics', 'source': 'BBC Politics', 'bias_label': 'CENTER-LEFT'},

    # SPORTS
    {'url': 'https://www.wtxl.com/sports.rss', 'category': 'sports', 'source': 'WTXL Sports', 'bias_label': 'CENTER'},
    {'url': 'https://news.google.com/rss/search?q=UGA+football+OR+%22college+football+playoff%22&hl=en-US&gl=US&ceid=US:en', 'category': 'sports', 'source': 'Google News (CFB)', 'bias_label': 'MIXED', 'max_items': 3},

    # NATURE
    {'url': 'https://georgiawildlife.blog/feed/', 'category': 'nature', 'source': 'GA Wildlife', 'bias_label': 'NEUTRAL'},
    {'url': 'https://news.google.com/rss/search?q=national+parks+OR+outdoor+adventure+hiking&hl=en-US&gl=US&ceid=US:en', 'category': 'nature', 'source': 'Google News (Outdoors)', 'bias_label': 'MIXED', 'max_items': 3},

    # FISHING & HUNTING
    {'url': 'https://news.google.com/rss/search?q=%22fly+fishing%22+OR+%22bass+fishing%22+OR+%22duck+hunting%22&hl=en-US&gl=US&ceid=US:en', 'category': 'fishing', 'source': 'Google News (Fishing)', 'bias_label': 'MIXED', 'max_items': 5},

    # CONSERVATION
    {'url': 'https://news.google.com/rss/search?q=wildlife+conservation+OR+%22water+policy%22+OR+%22endangered+species%22&hl=en-US&gl=US&ceid=US:en', 'category': 'conservation', 'source': 'Google News (Conservation)', 'bias_label': 'MIXED', 'max_items': 5},
]

def clean_title(element):
    if element is None or element.text is None:
        return 'Untitled'
    text = element.text
    text = re.sub(r'<[^>]+>', '', text)
    text = html.unescape(text)
    text = ' '.join(text.split())
    return text.strip() or 'Untitled'

def get_link(item):
    link = item.find('link')
    if link is not None:
        url = link.text or link.get('href', '')
        if url and url.strip().startswith(('http://', 'https://')):
            return url.strip()
    return ''

all_news = []

for feed in feeds:
    try:
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
        }
        req = urllib.request.Request(feed['url'], headers=headers)
        with urllib.request.urlopen(req, context=ctx, timeout=15) as response:
            xml_data = response.read()
            root = ET.fromstring(xml_data)
            items = root.findall('.//item') + root.findall('.//{http://www.w3.org/2005/Atom}entry')
            max_items = feed.get('max_items', 5)
            for item in items[:max_items]:
                title = clean_title(item.find('title'))
                link = get_link(item)
                all_news.append({
                    'title': title,
                    'url': link,
                    'source': feed['source'],
                    'category': feed['category'],
                    'timestamp': int(time.time()),
                    'bias': 0,
                    'bias_label': feed.get('bias_label', 'NEUTRAL')
                })
                print(f'Found: {title[:60]}...')
    except Exception as e:
        print(f'Error fetching {feed["source"]}: {e}')

output_file = r'$($OutputFile -replace "\\", "\\\\")'
cache_dir = os.path.dirname(output_file)
tmp_fd, tmp_path = tempfile.mkstemp(dir=cache_dir, suffix='.json')
try:
    with os.fdopen(tmp_fd, 'w') as f:
        json.dump(all_news, f, indent=2)
    # On Windows, remove target first if it exists (os.rename won't overwrite)
    if os.path.exists(output_file):
        os.remove(output_file)
    os.rename(tmp_path, output_file)
except:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
"@

& $PythonCmd -c $PythonScript

Write-Host "News updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

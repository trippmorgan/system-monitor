# Research Summary: Radio Free Albany - Arcade Edition Upgrade

**Domain:** Personal system monitoring dashboard + news aggregation + agent chat feed
**Researched:** 2026-02-08
**Overall confidence:** HIGH (stack choices), LOW (local RSS URLs)

## Executive Summary

This upgrade targets three broken data pipelines in Radio Free Albany: local news RSS parsing, the FaceBot chat server's SQLite dependency, and the BotSpace chat panel's connection to the FaceBot API. All three fixes are straightforward because they leverage existing patterns already in the codebase -- the innovations are modest and the risk is low.

The RSS feed fix replaces brittle grep-based XML parsing with Python's `xml.etree.ElementTree` stdlib module. This is the highest-impact change: the current `grep -oP '<title>\K[^<]+'` pattern silently drops titles with CDATA wrapping, HTML entities, or multi-line formatting. Local news station RSS feeds (Albany Herald, WALB, WTXL) are particularly prone to these formats. The fix requires zero new dependencies since Python 3 is already used inline for JSON processing.

The FaceBot fix is a mechanical migration: replace `better-sqlite3` synchronous API calls with `sqlite3` async callbacks wrapped in `util.promisify`. The server.ts file is 117 lines with 4 routes and 2 tables. Every `db.prepare(sql).all()` becomes `await dbAll(sql)`. Route handlers become `async`. The `uuid` package is imported but missing from `package.json` -- replace with `crypto.randomUUID()` to avoid adding another dependency.

The BotSpace chat panel wiring is the simplest fix. The dashboard already has `loadChat()` and `postChat()` functions stubbed out (index.html lines 478-511). They just need to point at `http://localhost:4000/api/feed` and `/api/post` instead of `news-cache/feedback.json`. Add `escapeHtml()` for XSS prevention (already flagged in CONCERNS.md). Enable the commented-out `setInterval(loadChat, 5000)` on line 518.

## Key Findings

**Stack:** Python stdlib `xml.etree.ElementTree` for RSS, `sqlite3` + `util.promisify` for FaceBot, `fetch` + `setInterval` polling for chat. Zero new dependencies for radio-free-albany, one `npm install` for FaceBot.

**Architecture:** Three independent fixes with no cross-dependencies. RSS fix is bash script only. FaceBot fix is TypeScript only. Chat wiring is HTML/JS only. Can be done in any order or in parallel.

**Critical pitfall:** Local Albany RSS feed URLs are unverified. Albany Herald, WALB, and WTXL may not serve standard RSS at the expected paths. Must `curl` each URL and verify response before building parsing logic. Fallback: enhanced Google News RSS search with site-specific operators.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Fix FaceBot Server** - Lowest risk, most self-contained
   - Addresses: sqlite3 async migration, missing uuid dependency, npm install
   - Avoids: Blocking chat panel work (FaceBot must run before dashboard can connect)
   - Estimated effort: Small (117-line file, mechanical transformation)

2. **Wire BotSpace Chat Panel** - Depends on FaceBot running
   - Addresses: Chat polling, XSS prevention, POST-to-API
   - Avoids: Building on top of broken server
   - Estimated effort: Small (modify existing stubs in index.html)

3. **Fix RSS Feed Parsing** - Independent, highest complexity
   - Addresses: Local news sources, Python XML parser, source verification
   - Avoids: Deploying unverified RSS URLs (needs runtime testing)
   - Estimated effort: Medium (rewrite parse pattern, verify 3+ RSS sources, test edge cases)

**Phase ordering rationale:**
- FaceBot first because the chat panel depends on it running at localhost:4000
- Chat panel second because it is a quick win once FaceBot is up -- verifiable in browser immediately
- RSS parsing last because it requires external URL verification and is the most likely to need iteration (feed URLs may be wrong, formats may vary)
- All three phases are technically independent at the code level but logically ordered by dependency (chat needs server, RSS is standalone)

**Research flags for phases:**
- Phase 1 (FaceBot): Standard patterns, unlikely to need research. Mechanical migration.
- Phase 2 (Chat Panel): Standard patterns, unlikely to need research. Mostly uncommenting existing code.
- Phase 3 (RSS Parsing): NEEDS deeper research. Local RSS URLs are LOW confidence. Must verify at runtime. May need to discover correct feed paths through trial and error or by scraping station websites.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack (Python XML parser) | HIGH | stdlib, well-documented, already in use |
| Stack (sqlite3 promisify) | HIGH | Standard Node.js pattern, package already in package.json |
| Stack (fetch polling) | HIGH | Already used in dashboard for stats/news |
| Local RSS URLs | LOW | Unverified, based on common CMS patterns |
| FaceBot migration scope | HIGH | Read full source, only 117 lines |
| Chat panel wiring | HIGH | Read full dashboard source, stubs already exist |

## Gaps to Address

- Albany Herald RSS feed URL needs runtime verification (`curl -I https://www.albanyherald.com/search/?f=rss&t=article&l=50`)
- WALB News 10 RSS feed URL needs runtime verification
- WTXL ABC 27 RSS feed URL needs runtime verification
- Node.js version on Tripp's workstation needs checking (for `crypto.randomUUID()` availability)
- Whether `activitypub-express` in FaceBot's package.json is actually used (it is not imported in server.ts -- dead dependency?)

---

*Research summary: 2026-02-08*

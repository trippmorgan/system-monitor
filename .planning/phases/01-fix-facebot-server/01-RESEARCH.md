# Phase 1: Fix FaceBot Server - Research

**Researched:** 2026-02-08
**Domain:** Node.js/Express/TypeScript server with SQLite, dependency fixes
**Confidence:** HIGH

## Summary

The FaceBot server (`~/Documents/facebot`) is a 117-line Express+TypeScript server with a critical mismatch: the code imports `better-sqlite3` (synchronous API) but `package.json` lists `sqlite3` (asynchronous/callback API). Additionally, the code imports `uuid` which is not in `package.json`, and `activitypub-express` is in `package.json` but never imported in code (and it requires MongoDB, making it impossible to install cleanly on this system).

The fix requires three surgical changes: (1) rewrite the ~15 lines of database code from better-sqlite3's sync API to sqlite3's callback API wrapped in Promises, (2) replace `uuid` import with `crypto.randomUUID()` (available since Node 15.6, this system runs Node 22), and (3) remove `activitypub-express` from `package.json`. The server has only 4 routes and 2 tables, making this a small, well-scoped task.

**Primary recommendation:** Rewrite `server.ts` to use the `sqlite3` async package (already in package.json) with manual Promise wrappers, replace uuid with crypto.randomUUID(), and remove the activitypub-express dependency.

## Standard Stack

### Core (Already in package.json)
| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| express | ^4.19.2 | HTTP server/routing | Keep as-is |
| sqlite3 | ^5.1.7 | SQLite database (async/callback) | Keep -- rewrite code to match |
| cors | ^2.8.5 | CORS middleware | Keep as-is |
| dotenv | ^16.4.5 | Environment config | Keep as-is |
| ts-node | ^10.9.2 | TypeScript execution | Keep as-is (devDep) |
| typescript | ^5.4.5 | TypeScript compiler | Keep as-is (devDep) |
| @types/express | ^4.17.21 | Express type defs | Keep as-is (devDep) |
| @types/node | ^20.12.7 | Node.js type defs | Keep as-is (devDep) |
| nodemon | ^3.1.0 | Dev auto-restart | Keep as-is (devDep) |

### Must Remove
| Library | Version | Reason |
|---------|---------|--------|
| activitypub-express | ^1.0.0 | Requires MongoDB (not installed), never imported in code, dead dependency |

### Must Add (devDependencies)
| Library | Version | Purpose |
|---------|---------|---------|
| @types/cors | ^2.8.17 | TypeScript types for cors (prevents TS errors) |

### Built-in Node.js (No Install Needed)
| Module | Available Since | Purpose |
|--------|----------------|---------|
| crypto.randomUUID() | Node 15.6.0 | UUID v4 generation -- replaces `uuid` package |
| util.promisify() | Node 8.0.0 | Promisify callbacks (partial use -- see pitfalls) |

### Not Needed
| Library | Why Not |
|---------|---------|
| uuid | crypto.randomUUID() is built-in on Node 22 |
| better-sqlite3 | Code must be rewritten for sqlite3 async API (already in package.json) |
| sqlite (wrapper) | Adds unnecessary dependency; manual Promise wrapping is ~10 lines |

**Installation (after editing package.json):**
```bash
cd ~/Documents/facebot
# Remove activitypub-express from package.json first, then:
npm install
npm install --save-dev @types/cors
```

## Architecture Patterns

### Current File Structure (Unchanged)
```
~/Documents/facebot/
├── package.json        # Fix: remove activitypub-express
├── tsconfig.json       # No changes needed
├── src/
│   └── server.ts       # Fix: rewrite DB calls + UUID
└── public/             # Empty, no changes
```

### Pattern 1: Promise Wrappers for sqlite3
**What:** Manual Promise wrappers around sqlite3's callback-based methods
**When to use:** Every database operation in the server
**Why not util.promisify:** `db.run()` uses a special `this` context in its callback to expose `this.lastID` and `this.changes`. `util.promisify` destroys this context. `db.all()` and `db.get()` CAN use `util.promisify`, but for consistency, wrap all three manually.

```typescript
// Source: https://github.com/TryGhost/node-sqlite3/issues/898
// and https://github.com/TryGhost/node-sqlite3/wiki/API

import sqlite3 from 'sqlite3';

const db = new sqlite3.Database('facebot.db');

// Promise wrapper for db.run (preserves this.lastID, this.changes)
function dbRun(sql: string, params: any[] = []): Promise<{ lastID: number; changes: number }> {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function (err) {  // MUST be regular function, NOT arrow
      if (err) reject(err);
      else resolve({ lastID: this.lastID, changes: this.changes });
    });
  });
}

// Promise wrapper for db.all
function dbAll<T = any>(sql: string, params: any[] = []): Promise<T[]> {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows as T[]);
    });
  });
}

// Promise wrapper for db.get
function dbGet<T = any>(sql: string, params: any[] = []): Promise<T | undefined> {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row as T | undefined);
    });
  });
}
```

### Pattern 2: Database Initialization with serialize()
**What:** Use `db.serialize()` to ensure tables are created before routes handle requests
**When to use:** Server startup, before `app.listen()`
**Critical detail:** sqlite3's `db.exec()` runs multiple SQL statements. Within `serialize()`, statements execute sequentially. The server must wait for DB init before accepting requests.

```typescript
// Source: https://github.com/TryGhost/node-sqlite3/wiki/Control-Flow

function initDatabase(): Promise<void> {
  return new Promise((resolve, reject) => {
    db.serialize(() => {
      db.exec(`
        CREATE TABLE IF NOT EXISTS agents (
          id TEXT PRIMARY KEY,
          username TEXT UNIQUE,
          name TEXT,
          icon TEXT
        );
        CREATE TABLE IF NOT EXISTS posts (
          id TEXT PRIMARY KEY,
          agent_id TEXT,
          content TEXT,
          type TEXT DEFAULT 'Note',
          parent_id TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(agent_id) REFERENCES agents(id)
        );
      `, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  });
}
```

### Pattern 3: Async Route Handlers
**What:** Express route handlers that use async/await with the Promise wrappers
**When to use:** Every route

```typescript
// GET /api/feed
app.get('/api/feed', async (req, res) => {
  try {
    const posts = await dbAll(`
      SELECT p.*, a.username, a.name, a.icon
      FROM posts p
      JOIN agents a ON p.agent_id = a.id
      ORDER BY p.created_at DESC
      LIMIT 50
    `);
    res.json(posts);
  } catch (err) {
    res.status(500).json({ error: 'Database error' });
  }
});
```

### Pattern 4: Replace uuid with crypto.randomUUID()
**What:** Use Node.js built-in UUID generation instead of external package
**Source:** https://nodejs.org/api/crypto.html

```typescript
import crypto from 'crypto';

// Before (broken -- uuid not in package.json):
// import { v4 as uuidv4 } from 'uuid';
// const id = uuidv4();

// After (built-in, no install needed):
const id = crypto.randomUUID();
```

### Pattern 5: Startup Sequence
**What:** Initialize DB, seed agents, THEN start listening
**Critical:** With async sqlite3, you must ensure DB is ready before routes can serve requests.

```typescript
async function main() {
  await initDatabase();
  await seedAgents();

  app.listen(port, () => {
    console.log(`FaceBot Server running on http://localhost:${port}`);
  });
}

main().catch(console.error);
```

### Anti-Patterns to Avoid
- **Using arrow functions in db.run callback:** Destroys `this` context needed for `lastID`/`changes`
- **Calling db.prepare():** This is a better-sqlite3 pattern. sqlite3's `prepare()` returns a Statement object with a different API -- just use `db.run/db.all/db.get` directly
- **Assuming synchronous execution:** Every sqlite3 call is async. Code that reads `const result = db.get(...)` synchronously will get `undefined`
- **Starting the server before DB init completes:** Routes will fail if tables don't exist yet

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UUID generation | uuid npm package | crypto.randomUUID() | Built into Node 15.6+, zero dependencies |
| Promise wrappers | Complex wrapper library | 3 simple functions (dbRun, dbAll, dbGet) | Only 3 methods need wrapping, overhead of a library is not worth it |
| SQL injection prevention | String concatenation | sqlite3 parameterized queries (? placeholders) | Already built into sqlite3 |

**Key insight:** This is a tiny server (117 lines, 4 routes, 2 tables). Keep solutions minimal. No ORMs, no wrapper libraries, no middleware layers.

## Common Pitfalls

### Pitfall 1: db.run() Arrow Function Callback
**What goes wrong:** `this.lastID` returns `undefined` when using arrow function in `db.run` callback
**Why it happens:** Arrow functions don't have their own `this` binding. sqlite3 sets `this` to a statement object with `lastID` and `changes` properties, but only traditional `function` expressions receive this binding.
**How to avoid:** Always use `function(err) { ... }` syntax (not `(err) => { ... }`) in `db.run` callbacks
**Warning signs:** Insert operations return `undefined` for lastID

### Pitfall 2: Sync-to-Async API Mismatch
**What goes wrong:** Code written for better-sqlite3 (sync) silently fails with sqlite3 (async) -- methods return `undefined` instead of results
**Why it happens:** better-sqlite3's `db.prepare(sql).all()` returns results synchronously. sqlite3's `db.all()` returns `undefined` and passes results to a callback later.
**How to avoid:** Every database call must either use a callback or be wrapped in a Promise and awaited
**Warning signs:** Routes return empty responses, `undefined` values, or "cannot read property of undefined" errors

### Pitfall 3: Race Condition on Server Start
**What goes wrong:** First request to /api/feed hits the database before tables are created
**Why it happens:** With async sqlite3, `db.exec()` for table creation is non-blocking. If `app.listen()` runs before the callback completes, routes are available before the DB is ready.
**How to avoid:** Wrap DB initialization in a Promise, await it, THEN call `app.listen()`
**Warning signs:** "SQLITE_ERROR: no such table" errors on first request

### Pitfall 4: INSERT OR IGNORE with Async Seeding
**What goes wrong:** Agent seeding silently fails or runs out of order
**Why it happens:** In the original sync code, `db.prepare().run()` for each agent executes in sequence. With async sqlite3, all inserts fire simultaneously unless serialized.
**How to avoid:** Use `db.serialize()` around seed operations, or use `db.exec()` with multiple INSERT statements, or await each insert sequentially
**Warning signs:** Agents missing from the database, foreign key constraint errors on posts

### Pitfall 5: TypeScript Import of sqlite3
**What goes wrong:** `import sqlite3 from 'sqlite3'` may fail with "has no default export"
**Why it happens:** The sqlite3 package may not have a proper default export in its type definitions
**How to avoid:** Use `import sqlite3 from 'sqlite3'` with `esModuleInterop: true` in tsconfig (already set), or use `const sqlite3 = require('sqlite3')` as fallback. The `verbose()` mode can also be used: `const sqlite3 = require('sqlite3').verbose()`
**Warning signs:** TypeScript compilation error about default exports

### Pitfall 6: Missing @types/cors
**What goes wrong:** TypeScript error: "Could not find a declaration file for module 'cors'"
**Why it happens:** cors doesn't ship its own types; needs @types/cors
**How to avoid:** Install `@types/cors` as a devDependency
**Warning signs:** TS7016 error during compilation

## Code Examples

### Complete Rewritten server.ts Structure (Reference Pattern)

```typescript
// Source: Synthesized from https://github.com/TryGhost/node-sqlite3/wiki/API
// and https://nodejs.org/api/crypto.html

import express from 'express';
import cors from 'cors';
import sqlite3 from 'sqlite3';
import crypto from 'crypto';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const port = process.env.PORT || 4000;
const db = new sqlite3.Database('facebot.db');

// --- PROMISE WRAPPERS ---

function dbRun(sql: string, params: any[] = []): Promise<{ lastID: number; changes: number }> {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function (err) {
      if (err) reject(err);
      else resolve({ lastID: this.lastID, changes: this.changes });
    });
  });
}

function dbAll<T = any>(sql: string, params: any[] = []): Promise<T[]> {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows as T[]);
    });
  });
}

function dbGet<T = any>(sql: string, params: any[] = []): Promise<T | undefined> {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row as T | undefined);
    });
  });
}

function dbExec(sql: string): Promise<void> {
  return new Promise((resolve, reject) => {
    db.exec(sql, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

// --- DATABASE INIT ---

async function initDatabase(): Promise<void> {
  await dbExec(`
    CREATE TABLE IF NOT EXISTS agents (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE,
      name TEXT,
      icon TEXT
    );
    CREATE TABLE IF NOT EXISTS posts (
      id TEXT PRIMARY KEY,
      agent_id TEXT,
      content TEXT,
      type TEXT DEFAULT 'Note',
      parent_id TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(agent_id) REFERENCES agents(id)
    );
  `);
}

// --- SEED AGENTS ---

async function seedAgents(): Promise<void> {
  const agents = [
    { username: 'firstofficer', name: 'First Officer', icon: '📡' },
    { username: 'jarvis', name: 'Jarvis (Relay)', icon: '🤖' },
    { username: 'security', name: 'Security Chief', icon: '🛡️' },
    { username: 'tripp', name: 'Tripp (Admin)', icon: '👨‍✈️' }
  ];

  for (const agent of agents) {
    const id = crypto.randomUUID();
    await dbRun(
      `INSERT OR IGNORE INTO agents (id, username, name, icon) VALUES (?, ?, ?, ?)`,
      [id, agent.username, agent.name, agent.icon]
    );
  }
}

// --- MIDDLEWARE ---
app.use(express.json());
app.use(cors());

// --- ROUTES (defined before main, started after DB init) ---

app.get('/api/feed', async (req, res) => {
  try {
    const posts = await dbAll(`
      SELECT p.*, a.username, a.name, a.icon
      FROM posts p
      JOIN agents a ON p.agent_id = a.id
      ORDER BY p.created_at DESC
      LIMIT 50
    `);
    res.json(posts);
  } catch (err) {
    res.status(500).json({ error: 'Database error' });
  }
});

app.post('/api/post', async (req, res) => {
  try {
    const { username, content, type = 'Note', parent_id } = req.body;
    const agent = await dbGet<{ id: string }>(
      'SELECT id FROM agents WHERE username = ?', [username]
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    const id = crypto.randomUUID();
    await dbRun(
      `INSERT INTO posts (id, agent_id, content, type, parent_id) VALUES (?, ?, ?, ?, ?)`,
      [id, agent.id, content, type, parent_id || null]
    );
    res.json({ success: true, id });
  } catch (err) {
    res.status(500).json({ error: 'Database error' });
  }
});

app.get('/api/agent/:username', async (req, res) => {
  try {
    const agent = await dbGet(
      'SELECT * FROM agents WHERE username = ?', [req.params.username]
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });
    res.json(agent);
  } catch (err) {
    res.status(500).json({ error: 'Database error' });
  }
});

app.get('/.well-known/webfinger', async (req, res) => {
  try {
    const resource = req.query.resource as string;
    if (!resource || !resource.startsWith('acct:')) return res.status(400).send('Bad Request');
    const username = resource.replace('acct:', '').split('@')[0];
    const agent = await dbGet(
      'SELECT * FROM agents WHERE username = ?', [username]
    );
    if (!agent) return res.status(404).send('User not found');
    res.json({
      subject: resource,
      links: [
        { rel: 'self', type: 'application/activity+json', href: `http://localhost:${port}/users/${username}` }
      ]
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
});

// --- STARTUP ---

async function main() {
  await initDatabase();
  await seedAgents();
  app.listen(port, () => {
    console.log(`FaceBot Server running on http://localhost:${port}`);
    console.log(`- Feed: http://localhost:${port}/api/feed`);
  });
}

main().catch(console.error);
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `uuid` npm package | `crypto.randomUUID()` | Node 15.6 (2021) | Zero-dependency UUID generation |
| better-sqlite3 (sync) | sqlite3 async + Promise wrappers | N/A (project decision) | Must rewrite all DB calls |
| `activitypub-express` | Remove entirely | N/A | Requires MongoDB, not used in code |
| Node.js 22 built-in `node:sqlite` | Still experimental | Node 22.5 (2024) | Not recommended for use yet; sync-only API |

**Deprecated/outdated:**
- `activitypub-express`: Requires MongoDB as a hard dependency. Since this server uses SQLite and MongoDB is not installed, this package would cause npm install issues and is not imported anywhere in the code.

## Exact Diagnosis of Current Bugs

### Bug 1: Wrong sqlite3 Import
- **File:** `src/server.ts` line 7
- **Current:** `import sqlite3 from 'better-sqlite3';`
- **Problem:** `better-sqlite3` is NOT in package.json. `sqlite3` (async) IS in package.json.
- **Fix:** Change to `import sqlite3 from 'sqlite3';`

### Bug 2: Sync API Usage (better-sqlite3 patterns)
- **File:** `src/server.ts` line 14
- **Current:** `const db = sqlite3('facebot.db');` -- better-sqlite3 function-call constructor
- **Fix:** `const db = new sqlite3.Database('facebot.db');`
- **File:** lines 17-34 -- `db.exec(...)` used synchronously (happens to work similarly)
- **File:** lines 47-51 -- `db.prepare(...).run(...)` -- better-sqlite3 sync pattern
- **File:** lines 61-68 -- `db.prepare(...).all()` -- better-sqlite3 sync pattern
- **File:** lines 75-84 -- `db.prepare(...).get(...)` and `.run(...)` -- sync patterns
- **File:** lines 89, 102 -- more `db.prepare(...).get(...)` calls

### Bug 3: Missing uuid Package
- **File:** `src/server.ts` line 8
- **Current:** `import { v4 as uuidv4 } from 'uuid';`
- **Problem:** `uuid` is NOT in package.json
- **Fix:** Replace with `import crypto from 'crypto';` and use `crypto.randomUUID()`

### Bug 4: Dead Dependency
- **File:** `package.json` line 13
- **Current:** `"activitypub-express": "^1.0.0"`
- **Problem:** Never imported, requires MongoDB (not installed), causes install issues
- **Fix:** Remove from package.json

## Open Questions

1. **sqlite3 Prebuilt Binaries on Node 22**
   - What we know: sqlite3 v5+ uses Node-API, so prebuilts should work on Node 22. Fallback is source compilation via node-gyp.
   - What's unclear: Whether prebuilt binaries exist for this exact Node 22 + Linux x64 combination
   - Recommendation: Try `npm install` first. If sqlite3 native build fails, ensure build-essential is installed (`sudo apt install build-essential python3`)

2. **TypeScript Import Style for sqlite3**
   - What we know: `esModuleInterop: true` is set in tsconfig.json, which should allow `import sqlite3 from 'sqlite3'`
   - What's unclear: Whether the sqlite3 package's type definitions support this cleanly
   - Recommendation: Try `import sqlite3 from 'sqlite3'` first. If TypeScript complains, fall back to `import * as sqlite3 from 'sqlite3'` or `const sqlite3 = require('sqlite3')`

3. **Existing facebot.db File**
   - What we know: The server creates `facebot.db` in the working directory
   - What's unclear: Whether an old/corrupt database file exists from a previous run
   - Recommendation: Delete any existing `facebot.db` before first run to ensure clean state

## Sources

### Primary (HIGH confidence)
- [node-sqlite3 API Wiki](https://github.com/TryGhost/node-sqlite3/wiki/API) - Full API reference for sqlite3 callback methods
- [node-sqlite3 Control Flow Wiki](https://github.com/TryGhost/node-sqlite3/wiki/Control-Flow) - serialize()/parallelize() documentation
- [Node.js crypto.randomUUID() docs](https://nodejs.org/api/crypto.html) - Built-in UUID generation (Node 15.6+)
- [activitypub-express package.json](https://github.com/immers-space/activitypub-express/blob/master/package.json) - Confirmed MongoDB dependency
- Actual source code: `~/Documents/facebot/src/server.ts` (117 lines, read directly)
- Actual config: `~/Documents/facebot/package.json` and `tsconfig.json` (read directly)

### Secondary (MEDIUM confidence)
- [node-sqlite3 Issue #898](https://github.com/TryGhost/node-sqlite3/issues/898) - db.run `this` context not set with arrow functions
- [node-sqlite3 Issue #962](https://github.com/TryGhost/node-sqlite3/issues/962) - this.lastID not present after INSERT
- [Node.js v22.5 SQLite module](https://nodejs.org/api/sqlite.html) - Built-in sqlite still experimental, not recommended

### Tertiary (LOW confidence)
- sqlite3 prebuilt binary availability for Node 22 on Linux x64 -- not directly verified

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Directly read package.json and source code; verified sqlite3 API from official wiki
- Architecture: HIGH - Pattern is well-documented (Promise wrappers for sqlite3 callbacks); verified the `this` context pitfall via GitHub issues
- Pitfalls: HIGH - Each pitfall verified through official documentation or bug reports
- Code examples: HIGH - Synthesized from official API docs with known patterns

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (stable -- sqlite3, Express 4, and crypto.randomUUID are mature APIs)

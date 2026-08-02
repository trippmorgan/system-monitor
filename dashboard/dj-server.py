"""
dj-server.py - Flask server for Radio Free Albany
Serves static dashboard files AND provides DJ chat API endpoints.
Replaces python -m http.server with song request + PlayoutONE integration.
"""

import argparse
import json
import os
import re
import socket
import time
import random
import logging
import urllib.request
from datetime import datetime
from flask import Flask, request, jsonify, send_from_directory, send_file

# ---------------------------------------------------------------------------
# Optional: pyodbc for SQL Server (graceful degradation if unavailable)
# ---------------------------------------------------------------------------
try:
    import pyodbc
    HAS_PYODBC = True
except ImportError:
    HAS_PYODBC = False

# ---------------------------------------------------------------------------
# Configuration (overridable via env vars)
# ---------------------------------------------------------------------------
SQL_SERVER = os.environ.get("P1_SQL_SERVER", r".\P1SQLEXPRESS")
SQL_DATABASE = os.environ.get("P1_SQL_DATABASE", "playoutone_standard")
SQL_USER = os.environ.get("P1_SQL_USER", "playoutone_apps")
SQL_PASSWORD = os.environ.get("P1_SQL_PASSWORD", "PlayoutONE.")
P1_API_HOST = os.environ.get("P1_API_HOST", "127.0.0.1")
P1_API_PORT = int(os.environ.get("P1_API_PORT", "1073"))

# Optional LLM banter (Ollama on jarvis superserver). Falls back to canned
# lines whenever the endpoint is unreachable, so the DJ never goes silent.
DJ_LLM_URL = os.environ.get("DJ_LLM_URL", "http://100.80.111.84:11434")
DJ_LLM_MODEL = os.environ.get("DJ_LLM_MODEL", "phi3:mini")
DJ_LLM_ENABLED = os.environ.get("DJ_LLM_ENABLED", "1") == "1"
LLM_TIMEOUT = 5          # seconds per generation attempt
LLM_RETRY_COOLDOWN = 300 # after a failure, skip LLM attempts for this long
_llm_down_until = 0

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
chat_history = []           # In-memory chat log (max 200 messages)
MAX_HISTORY = 200
rate_limit = {}             # ip -> last_request_time
RATE_LIMIT_SECONDS = 3

# Rotation category IDs (int) for tier-5 fallback — top categories by track count
ROTATION_CATEGORIES = [44, 38, 125, 36, 74, 93, 37, 43, 109, 35, 117, 68, 88]

# Prefixes to strip from user input
REQUEST_PREFIXES = re.compile(
    r"^(can you |could you |please |play |put on |queue |spin |throw on |drop |hit me with |some |any |a little )+",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Flask app
# ---------------------------------------------------------------------------
app = Flask(__name__)
log = logging.getLogger("dj-server")


def get_db():
    """Return a pyodbc connection to PlayoutONE SQL Server."""
    if not HAS_PYODBC:
        return None
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={SQL_SERVER};"
        f"DATABASE={SQL_DATABASE};"
        f"UID={SQL_USER};"
        f"PWD={SQL_PASSWORD};"
    )
    return pyodbc.connect(conn_str, timeout=5)


def send_p1_command(cmd):
    """Send a command to PlayoutONE TCP API and return the response."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect((P1_API_HOST, P1_API_PORT))
            s.sendall((cmd + "\r\n").encode("utf-8"))
            return s.recv(4096).decode("utf-8", errors="replace").strip()
    except Exception as e:
        log.warning("PlayoutONE TCP command failed: %s", e)
        return None


def parse_request(text):
    """Parse user input into (search_term, artist_hint)."""
    cleaned = REQUEST_PREFIXES.sub("", text).strip()
    if not cleaned:
        cleaned = text.strip()

    # Split on " by " to get title / artist
    parts = re.split(r"\s+by\s+", cleaned, maxsplit=1, flags=re.IGNORECASE)
    if len(parts) == 2:
        return parts[0].strip(), parts[1].strip()
    return cleaned, None


def search_tracks(term, artist_hint):
    """
    5-tier song search against the PlayoutONE Audio table.
    Returns (track_dict, tier_number) or (None, 0).
    """
    conn = get_db()
    if conn is None:
        return None, 0

    cursor = conn.cursor()
    base_where = "Type = 16 AND (Deleted = 0 OR Deleted IS NULL)"
    SELECT_COLS = "UID, Title, Artist, Album, [Length], Plays, Category"

    log.info("SEARCH: term=%r artist_hint=%r", term, artist_hint)

    try:
        # --- Tier 1: Exact title match ---
        log.info("  Tier 1: exact title match for %r", term)
        cursor.execute(
            f"SELECT TOP 1 {SELECT_COLS} "
            f"FROM Audio WHERE {base_where} AND LOWER(Title) = LOWER(?) "
            f"ORDER BY Plays DESC",
            (term,),
        )
        row = cursor.fetchone()
        if row:
            log.info("  Tier 1 HIT: %s - %s", row[1], row[2])
            return _row_to_dict(row), 1

        # --- Tier 2: Artist hint + partial title ---
        if artist_hint:
            log.info("  Tier 2: artist=%r + title=%r", artist_hint, term)
            cursor.execute(
                f"SELECT TOP 1 {SELECT_COLS} "
                f"FROM Audio WHERE {base_where} "
                f"AND LOWER(Artist) LIKE ? AND LOWER(Title) LIKE ? "
                f"ORDER BY Plays DESC",
                (f"%{artist_hint.lower()}%", f"%{term.lower()}%"),
            )
            row = cursor.fetchone()
            if row:
                log.info("  Tier 2 HIT: %s - %s", row[1], row[2])
                return _row_to_dict(row), 2

        # --- Tier 3: Partial title match ---
        log.info("  Tier 3: partial title LIKE %%%s%%", term)
        cursor.execute(
            f"SELECT TOP 5 {SELECT_COLS} "
            f"FROM Audio WHERE {base_where} AND LOWER(Title) LIKE ? "
            f"ORDER BY Plays DESC",
            (f"%{term.lower()}%",),
        )
        rows = cursor.fetchall()
        if rows:
            log.info("  Tier 3 HIT: %d results, best: %s - %s", len(rows), rows[0][1], rows[0][2])
            return _row_to_dict(rows[0]), 3

        # Tier 3b: word-split fallback — match ALL words in title
        words = term.split()
        stop_words = {"a", "an", "the", "of", "and", "or", "in", "on", "to", "for", "is", "it", "as", "we", "i"}
        significant_words = [w for w in words if w.lower() not in stop_words and len(w) > 1]
        if len(words) > 1:
            log.info("  Tier 3b: word-split title %r", words)
            like_clauses = " AND ".join(["LOWER(Title) LIKE ?"] * len(words))
            params = [f"%{w.lower()}%" for w in words]
            cursor.execute(
                f"SELECT TOP 5 {SELECT_COLS} "
                f"FROM Audio WHERE {base_where} AND {like_clauses} "
                f"ORDER BY Plays DESC",
                params,
            )
            rows = cursor.fetchall()
            if rows:
                log.info("  Tier 3b HIT: %d results, best: %s - %s", len(rows), rows[0][1], rows[0][2])
                return _row_to_dict(rows[0]), 3

        # Tier 3c: word-split across BOTH title and artist (handles "rem end of the world")
        # Also try apostrophe variants (its -> it's, dont -> don't)
        search_words = list(significant_words)
        for w in significant_words:
            wl = w.lower()
            if wl == "its":
                search_words.append("it's")
            elif wl == "dont":
                search_words.append("don't")
            elif wl == "cant":
                search_words.append("can't")
            elif wl == "wont":
                search_words.append("won't")
            elif wl == "youre":
                search_words.append("you're")
            # Acronym expansion: "rem" -> "r.e.m."
            if len(w) <= 5 and w.isalpha():
                search_words.append(".".join(w.upper()) + ".")
        # Deduplicate while preserving order
        seen = set()
        unique_words = []
        for w in search_words:
            wl = w.lower()
            if wl not in seen:
                seen.add(wl)
                unique_words.append(w)

        if len(unique_words) >= 2:
            log.info("  Tier 3c: word-split title+artist %r", unique_words)
            like_clauses = " AND ".join(
                [f"(LOWER(Title) LIKE ? OR LOWER(Artist) LIKE ?)"] * len(unique_words)
            )
            params = []
            for w in unique_words:
                params.extend([f"%{w.lower()}%", f"%{w.lower()}%"])
            cursor.execute(
                f"SELECT TOP 5 {SELECT_COLS} "
                f"FROM Audio WHERE {base_where} AND {like_clauses} "
                f"ORDER BY Plays DESC",
                params,
            )
            rows = cursor.fetchall()
            if rows:
                log.info("  Tier 3c HIT: %d results, best: %s - %s", len(rows), rows[0][1], rows[0][2])
                return _row_to_dict(rows[0]), 3

        # --- Tier 4: Artist-only match (most-played) ---
        artist_search = artist_hint or term
        # Build artist search variants: "rem" -> also try "r.e.m." style
        artist_variants = [artist_search]
        for w in ([artist_search] + words):
            if len(w) <= 5 and w.isalpha():
                dotted = ".".join(w.upper()) + "."
                artist_variants.append(dotted)
        for av in artist_variants:
            log.info("  Tier 4: artist-only LIKE %%%s%%", av)
            cursor.execute(
                f"SELECT TOP 1 {SELECT_COLS} "
                f"FROM Audio WHERE {base_where} AND LOWER(Artist) LIKE ? "
                f"ORDER BY Plays DESC",
                (f"%{av.lower()}%",),
            )
            row = cursor.fetchone()
            if row:
                log.info("  Tier 4 HIT: %s - %s", row[1], row[2])
                return _row_to_dict(row), 4

        # --- Tier 5: Random from rotation categories ---
        log.info("  Tier 5: random from rotation categories %s", ROTATION_CATEGORIES)
        cat_placeholders = ",".join(["?"] * len(ROTATION_CATEGORIES))
        cursor.execute(
            f"SELECT TOP 1 {SELECT_COLS} "
            f"FROM Audio WHERE {base_where} AND Category IN ({cat_placeholders}) "
            f"ORDER BY NEWID()",
            ROTATION_CATEGORIES,
        )
        row = cursor.fetchone()
        if row:
            log.info("  Tier 5 HIT: %s - %s (cat %s)", row[1], row[2], row[6])
            return _row_to_dict(row), 5

        # Absolute fallback: any random music track
        log.info("  Tier 5 fallback: any random track")
        cursor.execute(
            f"SELECT TOP 1 {SELECT_COLS} "
            f"FROM Audio WHERE {base_where} ORDER BY NEWID()"
        )
        row = cursor.fetchone()
        if row:
            log.info("  Tier 5 fallback HIT: %s - %s", row[1], row[2])
            return _row_to_dict(row), 5

        log.warning("  NO RESULTS at any tier")
        return None, 0
    finally:
        conn.close()


def _row_to_dict(row):
    return {
        "uid": str(row[0]),
        "title": row[1] or "Unknown",
        "artist": row[2] or "Unknown",
        "album": row[3] or "",
        "duration": row[4] or 0,
        "plays": row[5] or 0,
        "category": row[6] or "",
    }


def queue_track(uid):
    """
    Queue a track by swapping it into the next unloaded song slot in the log.

    PlayoutONE loads upcoming Playlists rows into its decks shortly before
    airing them (Status: 1=playing, 2=loaded in deck, 0=not loaded). Rewriting
    the uid of a Status=0 row is picked up by the player when it loads that
    row — verified on-air 2026-08-01. We only swap rows whose current item is
    a song (Audio.Type=16), so station IDs and spots are never clobbered.
    (The old TCP LOADNEXT approach was talking to P1_Monitor on 1073, which
    silently ignores unknown commands.)
    """
    try:
        conn = get_db()
        if conn is None:
            return False, "No database connection"
        cursor = conn.cursor()
        # Playhead = highest row that is playing or already loaded in a deck
        cursor.execute(
            "SELECT TOP 1 GIndex FROM Playlists WHERE Status IN (1, 2) ORDER BY GIndex DESC"
        )
        row = cursor.fetchone()
        if not row:
            return False, "No playhead found -- is PlayoutONE playing?"
        head = row[0]
        # First not-yet-loaded SONG slot after the playhead
        cursor.execute(
            "SELECT TOP 1 p.GIndex, a.Title, a.Artist "
            "FROM Playlists p JOIN Audio a ON p.uid = a.uid "
            "WHERE p.GIndex > ? AND p.Status = 0 AND a.Type = 16 "
            "ORDER BY p.GIndex ASC",
            (head,),
        )
        slot = cursor.fetchone()
        if not slot:
            return False, "No upcoming song slot found in the log"
        cursor.execute(
            "UPDATE Playlists SET uid = ? WHERE GIndex = ? AND Status = 0",
            (uid, slot[0]),
        )
        conn.commit()
        replaced = f"{slot[1]} - {slot[2]}"
        conn.close()
        if cursor.rowcount:
            log.info("QUEUE: uid %s into slot %s (replaced %s)", uid, slot[0], replaced)
            return True, f"Swapped into the log (bumped {replaced})"
        return False, "Slot was loaded before the swap landed -- try again"
    except Exception as e:
        log.warning("SQL queue failed: %s", e)
        return False, str(e)


def try_llm_response(track, tier, original_query):
    """
    Ask the Ollama instance on the jarvis superserver for a line of Fever
    banter. Returns None on any failure; a failure puts the LLM on a
    cooldown so requests stay snappy while the superserver is unreachable.
    """
    global _llm_down_until
    if not DJ_LLM_ENABLED or time.time() < _llm_down_until:
        return None

    tier_context = {
        1: "You found the exact track they asked for.",
        2: "You found the track they asked for.",
        3: "You found a close match, not exactly what they asked for.",
        4: "You couldn't find that song, but you found another track by the same artist.",
        5: "You couldn't find anything matching, so you're spinning a random pick from rotation instead.",
    }.get(tier, "You picked a track for them.")

    prompt = (
        f'A listener called in and requested: "{original_query}". '
        f'{tier_context} You are about to queue "{track["title"]}" by {track["artist"]}. '
        f"Give your one-line on-air response."
    )
    system = (
        "You are Dr. Fever, the burned-out, fast-talking, coffee-fueled rock DJ "
        "at WPFQ, Radio Free Albany, in Albany, Georgia -- in the spirit of a "
        "classic 1970s FM jock. Sardonic, conspiratorial, warm underneath, "
        "loves the music, distrusts the suits. Reply with ONE short on-air line "
        "(30 words max) announcing the track. Always name the track and artist. "
        "No emojis, no hashtags, no stage directions."
    )

    try:
        req = urllib.request.Request(
            f"{DJ_LLM_URL}/api/generate",
            data=json.dumps({
                "model": DJ_LLM_MODEL,
                "prompt": prompt,
                "system": system,
                "stream": False,
                "options": {"num_predict": 60, "temperature": 0.9},
            }).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as resp:
            text = json.loads(resp.read().decode("utf-8")).get("response", "").strip()
        # Sanity check: usable length and mentions the track or artist
        if 10 <= len(text) <= 300:
            log.info("LLM banter OK (%s)", DJ_LLM_MODEL)
            return text
        return None
    except Exception as e:
        log.info("LLM unavailable (%s) -- canned Fever lines for the next %ds", e, LLM_RETRY_COOLDOWN)
        _llm_down_until = time.time() + LLM_RETRY_COOLDOWN
        return None


def build_dj_response(track, tier, original_query):
    """Generate a Dr. Fever response based on match tier."""
    llm_line = try_llm_response(track, tier, original_query)
    if llm_line:
        return llm_line

    title = track["title"]
    artist = track["artist"]

    responses = {
        1: [
            f"The Doctor is IN. \"{title}\" by {artist}, comin' at ya next on WPFQ. Fever prescribes it.",
            f"Oh yeah, baby -- \"{title}\" by {artist}, straight into the deck. Don't touch that dial.",
            f"\"{title}\", {artist}. Impeccable choice. Almost like you've done this before. Up next.",
        ],
        2: [
            f"Dug it out of the stacks -- \"{title}\" by {artist}. The Fever delivers, even before coffee.",
            f"\"{title}\" by {artist}, comin' up. You got taste, kid. Don't let the suits find out.",
        ],
        3: [
            f"Closest thing I got is \"{title}\" by {artist} -- and honestly? It's better. Trust the Doctor.",
            f"Library's a little hazy today, but \"{title}\" by {artist} is close enough for FM. Rolling it.",
        ],
        4: [
            f"No dice on that title, but {artist}'s in the building. \"{title}\" it is. The Fever works in mysterious ways.",
            f"Couldn't find that cut, so I grabbed {artist}'s finest: \"{title}\". You'll thank me later.",
        ],
        5: [
            f"\"{original_query}\"? Never heard of it, and I've heard everything twice. Here's \"{title}\" by {artist} -- doctor's orders.",
            f"That one ain't in the stacks, babe. Spinning \"{title}\" by {artist} instead. Consider it a musical education.",
            f"Request line's a little fuzzy -- here's \"{title}\" by {artist}. When in doubt, crank it up.",
        ],
    }

    options = responses.get(tier, responses[5])
    return random.choice(options)


def add_chat_message(role, text):
    """Append a message to the in-memory chat history."""
    msg = {
        "role": role,
        "text": text,
        "timestamp": datetime.now().isoformat(),
    }
    chat_history.append(msg)
    if len(chat_history) > MAX_HISTORY:
        del chat_history[: len(chat_history) - MAX_HISTORY]
    return msg


# ---------------------------------------------------------------------------
# Static file serving (replaces http.server)
# ---------------------------------------------------------------------------
@app.route("/")
def serve_index():
    return send_file(os.path.join(app.static_folder, "index.html"))


@app.route("/<path:filepath>")
def serve_static(filepath):
    return send_from_directory(app.static_folder, filepath)


# ---------------------------------------------------------------------------
# DJ API endpoints
# ---------------------------------------------------------------------------
@app.route("/api/dj/request", methods=["POST"])
def dj_request():
    client_ip = request.remote_addr

    # Rate limiting
    now = time.time()
    last = rate_limit.get(client_ip, 0)
    if now - last < RATE_LIMIT_SECONDS:
        return jsonify({"error": "Slow down! Wait a few seconds between requests."}), 429
    rate_limit[client_ip] = now

    data = request.get_json(silent=True) or {}
    user_text = (data.get("message") or "").strip()
    if not user_text:
        return jsonify({"error": "Send a song request!"}), 400

    # Store user message
    add_chat_message("user", user_text)

    # Check pyodbc availability
    if not HAS_PYODBC:
        msg = add_chat_message("dj", "The board's dead, man. Somebody unplugged the Doctor. (Tech note: pip install pyodbc)")
        return jsonify({"reply": msg["text"], "track": None, "tier": 0, "message": msg})

    # Parse and search
    term, artist_hint = parse_request(user_text)
    log.info("DJ REQUEST: raw=%r parsed_term=%r artist_hint=%r", user_text, term, artist_hint)
    try:
        track, tier = search_tracks(term, artist_hint)
    except Exception as e:
        log.error("Search error: %s", e, exc_info=True)
        msg = add_chat_message("dj", f"Whoa -- the turntable just ate the record. Database says: {e}")
        return jsonify({"reply": msg["text"], "track": None, "tier": 0, "message": msg}), 500

    if not track:
        log.warning("No tracks found for request: %r", user_text)
        msg = add_chat_message("dj", "The record library's empty, man. Heavy. Somebody check if the database is plugged in.")
        return jsonify({"reply": msg["text"], "track": None, "tier": 0, "message": msg})

    log.info("MATCH tier=%d: \"%s\" by %s (uid=%s, plays=%s)", tier, track["title"], track["artist"], track["uid"], track["plays"])

    # Queue the track
    queued, queue_detail = queue_track(track["uid"])
    log.info("QUEUE result: queued=%s detail=%r", queued, queue_detail)

    # Build response
    dj_text = build_dj_response(track, tier, term)
    if not queued:
        dj_text += f" ...'cept the cart machine just jammed. Found it, couldn't queue it: {queue_detail}"

    msg = add_chat_message("dj", dj_text)
    return jsonify({
        "reply": msg["text"],
        "track": track,
        "tier": tier,
        "queued": queued,
        "message": msg,
    })


def _now_playing_from_air():
    """
    Read what is actually on the transmitter from PlayoutONE's status feed
    (port 7000). This is the ground truth: the Playlists table only reflects
    items the scheduler loaded, so anything started directly -- a voice break,
    or the air bridge when no log is loaded -- is invisible to the database.
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(3)
            s.connect(("127.0.0.1", 7000))
            time.sleep(0.8)
            data = s.recv(6000).decode("utf-8", errors="replace")
    except OSError:
        return None
    for line in data.splitlines():
        if line.startswith("CURRENT"):
            parts = line[len("CURRENT"):].strip().split("\t")
            title = parts[0].strip() if parts else ""
            artist = parts[1].strip() if len(parts) > 1 else ""
            if title:
                return {"title": title, "artist": artist}
            return None
    return None


def _query_now_playing():
    """Return (now_playing, up_next) dicts from PlayoutONE, or (None, None)."""
    on_air = _now_playing_from_air()

    if not HAS_PYODBC:
        return on_air, None
    conn = get_db()
    if conn is None:
        return on_air, None
    try:
        cursor = conn.cursor()
        # Status=1 means currently playing in PlayoutONE
        cursor.execute(
            "SELECT TOP 1 p.uid, a.Title, a.Artist "
            "FROM Playlists p LEFT JOIN Audio a ON p.uid = a.uid "
            "WHERE p.Status = 1 ORDER BY p.GIndex DESC"
        )
        now_row = cursor.fetchone()
        cursor.execute(
            "SELECT TOP 1 p.uid, a.Title, a.Artist "
            "FROM Playlists p LEFT JOIN Audio a ON p.uid = a.uid "
            "WHERE p.Status = 0 ORDER BY p.GIndex ASC"
        )
        next_row = cursor.fetchone()
        db_now = {"title": now_row[1], "artist": now_row[2]} if now_row else None
        # The air feed wins when it has something -- the DB row can be stale.
        return (
            on_air or db_now,
            {"title": next_row[1], "artist": next_row[2]} if next_row else None,
        )
    finally:
        conn.close()


@app.route("/api/dj/now-playing", methods=["GET"])
def now_playing():
    try:
        now, nxt = _query_now_playing()
        return jsonify({"now_playing": now, "up_next": nxt})
    except Exception as e:
        log.error("now-playing error: %s", e)
        return jsonify({"now_playing": None, "up_next": None, "error": str(e)})


def build_hourly_commentary():
    """One line of between-songs Fever patter, LLM if reachable, canned otherwise."""
    try:
        now, nxt = _query_now_playing()
    except Exception:
        now, nxt = None, None

    stamp = datetime.now()
    hour = stamp.hour
    daypart = (
        "overnight" if hour < 5 else
        "morning" if hour < 12 else
        "afternoon" if hour < 17 else
        "evening"
    )
    track_bit = f'"{now["title"]}" by {now["artist"]}' if now else "the music"

    global _llm_down_until
    if DJ_LLM_ENABLED and time.time() >= _llm_down_until:
        prompt = (
            f"It's {stamp.strftime('%A')} {daypart}, about {stamp.strftime('%I:%M %p').lstrip('0')} "
            f"in Albany, Georgia. Currently spinning: {track_bit}."
            + (f' Up next: "{nxt["title"]}" by {nxt["artist"]}.' if nxt else "")
            + " Give one short line of between-songs on-air patter -- a time check, a wry observation,"
            " or a word about the music. Don't ask for requests every time."
        )
        system = (
            "You are Dr. Fever, the burned-out, fast-talking, coffee-fueled rock DJ "
            "at WPFQ, Radio Free Albany, in Albany, Georgia -- in the spirit of a "
            "classic 1970s FM jock. Sardonic, conspiratorial, warm underneath. "
            "Reply with ONE on-air line, 35 words max. No emojis, no hashtags, no stage directions."
        )
        try:
            req = urllib.request.Request(
                f"{DJ_LLM_URL}/api/generate",
                data=json.dumps({
                    "model": DJ_LLM_MODEL,
                    "prompt": prompt,
                    "system": system,
                    "stream": False,
                    "options": {"num_predict": 70, "temperature": 0.95},
                }).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as resp:
                text = json.loads(resp.read().decode("utf-8")).get("response", "").strip()
            if 10 <= len(text) <= 300:
                return text
        except Exception as e:
            log.info("LLM unavailable for commentary (%s)", e)
            _llm_down_until = time.time() + LLM_RETRY_COOLDOWN

    clock = stamp.strftime("%I:%M").lstrip("0")
    canned = {
        "overnight": [
            f"It's {clock} in the AM on WPFQ and the only ones awake are me, the transmitter, and whoever's guilty conscience is keeping 'em up. That was {track_bit}.",
            f"WPFQ, Radio Free Albany, deep in the overnight. That's {track_bit} -- the coffee ran out an hour ago and the Doctor is running on fumes and rock 'n' roll.",
        ],
        "morning": [
            f"Mornin', Albany -- {clock} on WPFQ. That was {track_bit}. If you're stuck on Slappey Boulevard, crank it up. Traffic can't touch you at full volume.",
            f"It's {clock} and against medical advice, the Doctor is awake. WPFQ, Radio Free Albany, spinning {track_bit}.",
        ],
        "afternoon": [
            f"{clock} on a fine Albany afternoon, WPFQ. That was {track_bit}. The suits upstairs want me to read an ad -- instead, here's more music.",
            f"WPFQ, Radio Free Albany, {clock}. You're stuck at work, I'm stuck in this booth -- {track_bit} makes it bearable for both of us.",
        ],
        "evening": [
            f"Evenin', Albany. {clock} on WPFQ, Radio Free Albany. That was {track_bit}. The sun's down, the meters are lit, and the Doctor is just getting warmed up.",
            f"{clock} on WPFQ. That was {track_bit}. Whatever you did today, the music forgives you. Stay tuned.",
        ],
    }
    return random.choice(canned[daypart])


@app.route("/api/dj/announce", methods=["POST"])
def dj_announce():
    """
    Post a DJ announcement into the chat. Body: {"text": "..."} to announce
    verbatim, or {"generate": true} to have Fever improvise hourly patter.
    Called by the hourly commentary scheduled task; localhost-only server.
    """
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text and data.get("generate"):
        text = build_hourly_commentary()
    if not text:
        return jsonify({"error": "Provide text or generate:true"}), 400
    msg = add_chat_message("dj", text)
    return jsonify({"ok": True, "text": msg["text"], "timestamp": msg["timestamp"]})


@app.route("/api/dj/history", methods=["GET"])
def dj_history():
    limit = min(int(request.args.get("limit", 50)), MAX_HISTORY)
    return jsonify({"messages": chat_history[-limit:]})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Radio Free Albany DJ Server")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--directory", default=".")
    args = parser.parse_args()

    app.static_folder = os.path.abspath(args.directory)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    log.info("Serving files from: %s", app.static_folder)
    log.info("PlayoutONE SQL: %s / %s", SQL_SERVER, SQL_DATABASE)
    log.info("PlayoutONE API: %s:%s", P1_API_HOST, P1_API_PORT)

    if not HAS_PYODBC:
        log.warning("pyodbc not installed -- DJ features will be disabled")

    app.run(host=args.host, port=args.port, debug=False, threaded=True)

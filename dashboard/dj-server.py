"""
dj-server.py - Flask server for Radio Free Albany
Serves static dashboard files AND provides DJ chat API endpoints.
Replaces python -m http.server with song request + PlayoutONE integration.
"""

import argparse
import os
import re
import socket
import time
import random
import logging
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

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
chat_history = []           # In-memory chat log (max 200 messages)
MAX_HISTORY = 200
rate_limit = {}             # ip -> last_request_time
RATE_LIMIT_SECONDS = 3

# Rotation category IDs for tier-5 fallback (decade buckets, etc.)
ROTATION_CATEGORIES = [
    "60s", "70s", "80s", "90s", "00s", "2000s", "2010s", "2020s",
    "Gold", "Recurrent", "Hot", "Power",
]

# Prefixes to strip from user input
REQUEST_PREFIXES = re.compile(
    r"^(can you |could you |please |play |put on |queue |spin |throw on |drop |hit me with )+",
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

    try:
        # --- Tier 1: Exact title match ---
        cursor.execute(
            f"SELECT TOP 1 uid, Title, Artist, Album, Duration, Plays, CatID "
            f"FROM Audio WHERE {base_where} AND LOWER(Title) = LOWER(?) "
            f"ORDER BY Plays DESC",
            (term,),
        )
        row = cursor.fetchone()
        if row:
            return _row_to_dict(row), 1

        # --- Tier 2: Artist hint + partial title ---
        if artist_hint:
            cursor.execute(
                f"SELECT TOP 1 uid, Title, Artist, Album, Duration, Plays, CatID "
                f"FROM Audio WHERE {base_where} "
                f"AND LOWER(Artist) LIKE ? AND LOWER(Title) LIKE ? "
                f"ORDER BY Plays DESC",
                (f"%{artist_hint.lower()}%", f"%{term.lower()}%"),
            )
            row = cursor.fetchone()
            if row:
                return _row_to_dict(row), 2

        # --- Tier 3: Partial title match ---
        cursor.execute(
            f"SELECT TOP 5 uid, Title, Artist, Album, Duration, Plays, CatID "
            f"FROM Audio WHERE {base_where} AND LOWER(Title) LIKE ? "
            f"ORDER BY Plays DESC",
            (f"%{term.lower()}%",),
        )
        rows = cursor.fetchall()
        if rows:
            return _row_to_dict(rows[0]), 3

        # Tier 3b: word-split fallback — match ALL words
        words = term.split()
        if len(words) > 1:
            like_clauses = " AND ".join(["LOWER(Title) LIKE ?"] * len(words))
            params = [f"%{w.lower()}%" for w in words]
            cursor.execute(
                f"SELECT TOP 5 uid, Title, Artist, Album, Duration, Plays, CatID "
                f"FROM Audio WHERE {base_where} AND {like_clauses} "
                f"ORDER BY Plays DESC",
                params,
            )
            rows = cursor.fetchall()
            if rows:
                return _row_to_dict(rows[0]), 3

        # --- Tier 4: Artist-only match (most-played) ---
        artist_search = artist_hint or term
        cursor.execute(
            f"SELECT TOP 1 uid, Title, Artist, Album, Duration, Plays, CatID "
            f"FROM Audio WHERE {base_where} AND LOWER(Artist) LIKE ? "
            f"ORDER BY Plays DESC",
            (f"%{artist_search.lower()}%",),
        )
        row = cursor.fetchone()
        if row:
            return _row_to_dict(row), 4

        # --- Tier 5: Random from rotation categories ---
        cat_placeholders = ",".join(["?"] * len(ROTATION_CATEGORIES))
        cursor.execute(
            f"SELECT TOP 1 uid, Title, Artist, Album, Duration, Plays, CatID "
            f"FROM Audio WHERE {base_where} AND CatID IN ({cat_placeholders}) "
            f"ORDER BY NEWID()",
            ROTATION_CATEGORIES,
        )
        row = cursor.fetchone()
        if row:
            return _row_to_dict(row), 5

        # Absolute fallback: any random music track
        cursor.execute(
            f"SELECT TOP 1 uid, Title, Artist, Album, Duration, Plays, CatID "
            f"FROM Audio WHERE {base_where} ORDER BY NEWID()"
        )
        row = cursor.fetchone()
        if row:
            return _row_to_dict(row), 5

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
    """Queue a track as the next item in PlayoutONE."""
    # Primary: TCP command
    resp = send_p1_command(f"LOADNEXT {uid}")
    if resp is not None:
        return True, resp

    # Fallback: direct SQL INSERT into Playlists
    try:
        conn = get_db()
        if conn is None:
            return False, "No database connection"
        cursor = conn.cursor()
        # Find the current playing GIndex
        cursor.execute(
            "SELECT TOP 1 GIndex FROM Playlists WHERE Status = 1 ORDER BY GIndex DESC"
        )
        row = cursor.fetchone()
        next_idx = (row[0] + 1) if row else 1
        cursor.execute(
            "INSERT INTO Playlists (uid, GIndex, Status) VALUES (?, ?, 0)",
            (uid, next_idx),
        )
        conn.commit()
        conn.close()
        return True, "Queued via SQL fallback"
    except Exception as e:
        log.warning("SQL queue fallback failed: %s", e)
        return False, str(e)


def build_dj_response(track, tier, original_query):
    """Generate an arcade-themed DJ response based on match tier."""
    title = track["title"]
    artist = track["artist"]

    responses = {
        1: [
            f"POWER UP! Queuing \"{title}\" by {artist}. Coming up next!",
            f"DIRECT HIT! \"{title}\" by {artist} locked and loaded!",
            f"COIN INSERTED! \"{title}\" by {artist} is in the chamber!",
        ],
        2: [
            f"COMBO MATCH! Found \"{title}\" by {artist}. Queued up!",
            f"BONUS ROUND! \"{title}\" by {artist} -- great pick!",
        ],
        3: [
            f"CLOSE MATCH! Best result: \"{title}\" by {artist}. Spinning it up!",
            f"PARTIAL HIT! Loading \"{title}\" by {artist} into the deck!",
        ],
        4: [
            f"No exact title match, but {artist} is in the library! Queuing \"{title}\"!",
            f"ARTIST FOUND! Here's {artist} with \"{title}\" -- enjoy!",
        ],
        5: [
            f"Nothing matched \"{original_query}\" -- spinning a random gem: \"{title}\" by {artist}!",
            f"NO MATCH! But here's a surprise track: \"{title}\" by {artist}!",
            f"RANDOM ENCOUNTER! \"{title}\" by {artist} appears!",
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
        msg = add_chat_message("dj", "DJ OFFLINE: Database driver not installed. Run: pip install pyodbc")
        return jsonify({"reply": msg["text"], "track": None, "tier": 0, "message": msg})

    # Parse and search
    term, artist_hint = parse_request(user_text)
    try:
        track, tier = search_tracks(term, artist_hint)
    except Exception as e:
        log.error("Search error: %s", e)
        msg = add_chat_message("dj", f"GAME OVER: Database error -- {e}")
        return jsonify({"reply": msg["text"], "track": None, "tier": 0, "message": msg}), 500

    if not track:
        msg = add_chat_message("dj", f"EMPTY LIBRARY! No tracks found at all. Is the database connected?")
        return jsonify({"reply": msg["text"], "track": None, "tier": 0, "message": msg})

    # Queue the track
    queued, queue_detail = queue_track(track["uid"])

    # Build response
    dj_text = build_dj_response(track, tier, term)
    if not queued:
        dj_text += f" (Queue failed: {queue_detail} -- track found but not queued)"

    msg = add_chat_message("dj", dj_text)
    return jsonify({
        "reply": msg["text"],
        "track": track,
        "tier": tier,
        "queued": queued,
        "message": msg,
    })


@app.route("/api/dj/now-playing", methods=["GET"])
def now_playing():
    if not HAS_PYODBC:
        return jsonify({"now_playing": None, "up_next": None, "error": "pyodbc not installed"})

    try:
        conn = get_db()
        if conn is None:
            return jsonify({"now_playing": None, "up_next": None, "error": "No DB connection"})
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
        conn.close()

        return jsonify({
            "now_playing": {"title": now_row[1], "artist": now_row[2]} if now_row else None,
            "up_next": {"title": next_row[1], "artist": next_row[2]} if next_row else None,
        })
    except Exception as e:
        log.error("now-playing error: %s", e)
        return jsonify({"now_playing": None, "up_next": None, "error": str(e)})


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

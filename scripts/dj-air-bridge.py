r"""
dj-air-bridge.py - Keep WPFQ on the air when PlayoutONE has no log loaded.

BACKGROUND
  PlayoutONE can be running, licensed, and idle: the app's playlist grid is
  empty even though the database holds a full scheduled log, so the decks run
  dry and the station goes silent. `PLAY NEXT` returns nothing in that state
  (there is no "next"), so playback has to be driven item by item.

THE SAFETY RULE (learned the hard way, 2026-08-02)
  `PLAY UID` starts an item on a FREE DECK -- it does NOT replace what is
  playing. An earlier version of this script fired on "current track nearly
  over", raced, and put ~90 seconds of two- and three-track overlap on the air.

  So this version fires ONLY into confirmed silence: every deck must report
  zero progress before the next item starts. Overlap is therefore impossible
  by construction. The cost is a small gap between songs -- an honest trade
  against dead air, and it disappears the moment a real log is loaded.

HANDOVER
  If audio appears that this script did not start, real automation is back and
  the bridge stands down immediately so it never fights the console.

USAGE
  python dj-air-bridge.py [--minutes 180]
"""

import argparse
import re
import socket
import time
import urllib.parse
import urllib.request
from datetime import datetime

import pyodbc

import os

STATUS_HOST, STATUS_PORT = "127.0.0.1", 7000
HTTP_BASE = "http://localhost:81/?c="
LOG_FILE = r"C:\Users\PlayoutONE\system-monitor\logs\dj-air-bridge.log"
PID_FILE = r"C:\Users\PlayoutONE\system-monitor\logs\.bridge.pid"
# dj-voice-break.py drops an hourly break UID here instead of firing it itself
# whenever this bridge is running -- the bridge is the only thing allowed to
# start audio while it is in charge, which keeps breaks from racing the log.
PRIORITY_QUEUE = r"C:\Users\PlayoutONE\system-monitor\logs\.pending-break"


def log(msg):
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def get_db():
    # Same env vars config.ps1 exports for dj-server.py.
    return pyodbc.connect(
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=" + os.environ.get("P1_SQL_SERVER", r".\P1SQLEXPRESS") + ";"
        "DATABASE=" + os.environ.get("P1_SQL_DATABASE", "playoutone_standard") + ";"
        "UID=" + os.environ.get("P1_SQL_USER", "playoutone_apps") + ";"
        "PWD=" + os.environ.get("P1_SQL_PASSWORD", "PlayoutONE."),
        timeout=5,
    )


def air_state():
    """
    Return (current_title, max_progress_pct).
    max_progress 0.0 across every deck means the station is truly silent.
    Returns (None, None) if the status feed cannot be read -- treated as
    "unknown", never as silence.
    """
    s = socket.socket()
    s.settimeout(4)
    try:
        s.connect((STATUS_HOST, STATUS_PORT))
        time.sleep(0.8)
        data = s.recv(6000).decode(errors="replace")
    except OSError:
        return None, None
    finally:
        s.close()

    current, best = None, 0.0
    for ln in data.splitlines():
        if ln.startswith("CURRENT") and current is None:
            title = ln[len("CURRENT"):].strip().split("\t")[0].strip()
            current = title or None
        m = re.match(r"PROGRESS \d+ ([\d.]+)", ln)
        if m:
            best = max(best, float(m.group(1)))
    return current, best


def is_station_content(title):
    """
    Audio this station puts on air by other automated means -- currently the
    hourly Dr. Fever voice breaks (UIDs 93010-93012, dj-voice-break.py), which
    fire their own PLAY UID at :17. Without this the bridge would mistake its
    own station's break for automation returning and stand down mid-shift,
    leaving silence once the break ended.
    """
    return "fever" in (title or "").lower()


def play_uid(uid):
    # NOTE: PlayoutONE replies "-255" even on success. Never trust the body;
    # confirm on the status feed instead.
    try:
        with urllib.request.urlopen(
            HTTP_BASE + urllib.parse.quote(f"PLAY UID {uid}"), timeout=6
        ) as r:
            r.read()
        return True
    except OSError as e:
        log(f"  transport error on PLAY UID {uid}: {e}")
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=int, default=180)
    ap.add_argument("--from-gindex", type=float, default=None,
                    help="resume at this log position instead of auto-detecting")
    args = ap.parse_args()

    conn = get_db()
    cur = conn.cursor()

    # Resume point, best available source first. Falling back to 0 would replay
    # the oldest log in the table (weeks-old content), so never do that blindly.
    position = args.from_gindex
    if position is None:
        cur.execute("SELECT TOP 1 GIndex FROM Playlists WHERE Status IN (1, 2) ORDER BY GIndex DESC")
        row = cur.fetchone()
        if row:
            position = row[0]
    if position is None:
        # Nothing cued: find where the most recently played item sits in the log.
        cur.execute("SELECT TOP 1 UID FROM Log ORDER BY ID DESC")
        row = cur.fetchone()
        if row:
            cur.execute(
                "SELECT TOP 1 GIndex FROM Playlists WHERE uid = ? ORDER BY GIndex DESC",
                (str(row[0]),),
            )
            r2 = cur.fetchone()
            if r2:
                position = r2[0]
                log(f"resume point from last played item (uid {row[0]})")
    if position is None:
        log("FATAL: cannot determine a resume point; refusing to replay the oldest log")
        return

    log(f"BRIDGE START (silence-gated) at log position {position}, {args.minutes} min max")
    try:
        with open(PID_FILE, "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass
    deadline = time.time() + args.minutes * 60
    mine = set()

    # Something may already be mid-song at startup (e.g. a previous run, or a
    # break that is still finishing). Adopt it so we wait it out instead of
    # mistaking it for automation returning and quitting immediately.
    start_title, start_prog = air_state()
    if start_prog and start_prog > 0 and start_title:
        mine.add(start_title)
        log(f"adopting in-progress '{start_title}' -- waiting for it to end")

    while time.time() < deadline:
        current, progress = air_state()

        if progress is None:            # status feed unreadable -- wait, never fire blind
            log("status feed unreadable; waiting")
            time.sleep(10)
            continue

        if progress > 0:                # audio is playing -- NEVER fire
            if current and current not in mine and not is_station_content(current):
                log(f"external audio '{current}' -- automation is back, standing down")
                break
            time.sleep(5)
            continue

        # Confirmed silence on every deck. Re-check once to avoid a false read
        # during the instant between two items.
        time.sleep(2)
        _, confirm = air_state()
        if confirm is None or confirm > 0:
            continue

        # Anything in the priority queue jumps ahead of the scheduled log:
        # hourly Fever breaks, and hand-programmed sets. One UID per line,
        # optionally "uid|label". We consume the first line and write the rest
        # back, so the queue survives a restart mid-set.
        pending = label = None
        try:
            if os.path.exists(PRIORITY_QUEUE):
                with open(PRIORITY_QUEUE, "r", encoding="utf-8") as f:
                    entries = [ln.strip() for ln in f if ln.strip()]
                if entries:
                    first, rest = entries[0], entries[1:]
                    pending, _, label = first.partition("|")
                    pending, label = pending.strip(), (label.strip() or None)
                    if rest:
                        with open(PRIORITY_QUEUE, "w", encoding="utf-8") as f:
                            f.write("\n".join(rest) + "\n")
                    else:
                        os.remove(PRIORITY_QUEUE)
                else:
                    os.remove(PRIORITY_QUEUE)
        except OSError:
            pending = None

        if pending:
            cur.execute("SELECT Title, Artist FROM Audio WHERE UID = ?", (pending,))
            r = cur.fetchone()
            uid = pending
            title = (r[0] if r else None) or label or "queued item"
            artist = (r[1] if r else "") or ""
            gindex = "(queued)"
        else:
            cur.execute(
                "SELECT TOP 1 p.GIndex, p.uid, a.Title, a.Artist "
                "FROM Playlists p JOIN Audio a ON p.uid = a.uid "
                "WHERE p.GIndex > ? AND (a.Deleted = 0 OR a.Deleted IS NULL) "
                "ORDER BY p.GIndex ASC",
                (position,),
            )
            item = cur.fetchone()
            if not item:
                log("no further log items")
                break
            gindex, uid, title, artist = item
            position = gindex

        if not play_uid(uid):
            continue

        # Confirm it actually started before looping.
        started = False
        for _ in range(8):
            time.sleep(1.5)
            now, prog = air_state()
            if prog and prog > 0:
                mine.add(now)
                log(f"ON AIR: {title} - {artist} (uid {uid}, log {gindex})")
                started = True
                break
        if not started:
            log(f"  {title} (uid {uid}) did not start -- skipping")

    log("BRIDGE END")
    conn.close()
    try:
        os.remove(PID_FILE)
    except OSError:
        pass


if __name__ == "__main__":
    main()

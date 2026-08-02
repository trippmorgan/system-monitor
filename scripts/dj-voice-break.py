r"""
dj-voice-break.py - Put an hourly Dr. Fever voice break on the WPFQ air.

Pipeline (each step verified on-air 2026-08-01):
  1. Take commentary text from argv (or ask the DJ server to improvise one).
  2. Synthesize with edge-tts (en-US-ChristopherNeural).
  3. Drop into the AutoImporter watch folder \\P1-WPFQ-SRVS\PlayoutONE\Import\Programs
     using a rotating UID pool (93010-93012) so we never overwrite a break
     that might still be cued in a deck.
  4. Wait for ingestion into the Audio table.
  5. Swap the break into the next unloaded SONG slot in the playlist
     (Status=0, Audio.Type=16) -- the player picks it up when it loads the row.

Called by dj-hourly-comment.ps1. Exits 0 on success or graceful skip.
"""

import os
import re
import socket
import subprocess
import sys
import time
import urllib.request
from datetime import datetime

import pyodbc

IMPORT_DIR = r"\\P1-WPFQ-SRVS\PlayoutONE\Import\Programs"
VOICE = os.environ.get("DJ_TTS_VOICE", "en-US-ChristopherNeural")
UID_POOL = ["93010", "93011", "93012"]
LOG_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "logs", "dj-commentary.log")


def log(msg):
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] VOICE: {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def get_db():
    return pyodbc.connect(
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=" + os.environ.get("P1_SQL_SERVER", r".\P1SQLEXPRESS") + ";"
        "DATABASE=" + os.environ.get("P1_SQL_DATABASE", "playoutone_standard") + ";"
        "UID=" + os.environ.get("P1_SQL_USER", "playoutone_apps") + ";"
        "PWD=" + os.environ.get("P1_SQL_PASSWORD", "PlayoutONE."),
        timeout=5,
    )


PID_FILE = r"C:\Users\PlayoutONE\system-monitor\logs\.bridge.pid"
PENDING_BREAK = r"C:\Users\PlayoutONE\system-monitor\logs\.pending-break"


def bridge_running():
    """True if dj-air-bridge.py is currently driving playback."""
    try:
        with open(PID_FILE, "r", encoding="utf-8") as f:
            pid = int(f.read().strip())
    except (OSError, ValueError):
        return False
    # Cheap liveness check without extra dependencies.
    out = subprocess.run(
        ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
        capture_output=True, text=True, timeout=15,
    ).stdout
    return "python" in out.lower()


def get_remaining_seconds():
    """Remaining seconds of the playing deck, from the port-7000 status feed."""
    try:
        s = socket.socket()
        s.settimeout(3)
        s.connect(("127.0.0.1", 7000))
        time.sleep(0.5)
        data = s.recv(4000).decode(errors="replace")
        s.close()
    except OSError:
        return None
    playing_deck, best = None, 0.0
    for ln in data.splitlines():
        m = re.match(r"PROGRESS (\d+) ([\d.]+)", ln)
        if m and float(m.group(2)) > best:
            best = float(m.group(2))
            playing_deck = m.group(1)
    if playing_deck is None:
        return None
    for ln in data.splitlines():
        m = re.match(rf"TIME {playing_deck} -(\d+):(\d+)", ln)
        if m:
            return int(m.group(1)) * 60 + int(m.group(2))
    return None


def try_precise_air(uid, max_wait=200):
    """
    Wait for the current song's outro, then fire PLAY UID over the HTTP API
    so the break airs exactly at the segue. Returns True if fired.
    """
    end = time.time() + max_wait
    while time.time() < end:
        remain = get_remaining_seconds()
        if remain is not None and remain <= 6:
            try:
                with urllib.request.urlopen(
                    f"http://localhost:81/?c=PLAY%20UID%20{uid}", timeout=5
                ) as resp:
                    body = resp.read().decode(errors="replace").strip()
                # PlayoutONE returns -255 even on SUCCESS -- verified 2026-08-02
                # by watching a break hit the air right after a -255 reply. Do
                # not treat a negative body as a failure; confirm on port 7000.
                time.sleep(3)
                s = socket.socket()
                s.settimeout(3)
                try:
                    s.connect(("127.0.0.1", 7000))
                    time.sleep(0.8)
                    now = s.recv(3000).decode(errors="replace")
                finally:
                    s.close()
                aired = any(
                    ln.startswith("CURRENT") and "fever" in ln.lower()
                    for ln in now.splitlines()
                )
                log(f"PLAY UID replied {body!r}; on air = {aired}")
                return aired
            except OSError as e:
                log(f"PLAY UID failed: {e}")
                return False
        time.sleep(1 if (remain is not None and remain < 20) else 5)
    log("no segue within wait window")
    return False


def main():
    if len(sys.argv) > 1 and sys.argv[1].strip():
        text = sys.argv[1].strip()
    else:
        import json
        import urllib.request
        req = urllib.request.Request(
            "http://localhost:8787/api/dj/announce",
            data=b'{"generate": true}',
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = json.loads(resp.read())["text"]
    log(f"text: {text}")

    uid = UID_POOL[datetime.now().hour % len(UID_POOL)]
    filename = f"{uid} Fever Hourly Break.mp3"
    local_tmp = os.path.join(os.environ.get("TEMP", "."), filename)

    # 2. TTS
    r = subprocess.run(
        [sys.executable, "-m", "edge_tts", "--voice", VOICE, "--rate=+8%",
         "--text", text, "--write-media", local_tmp],
        capture_output=True, timeout=120,
    )
    if r.returncode != 0 or not os.path.exists(local_tmp):
        log(f"TTS failed: {r.stderr.decode(errors='replace')[:200]}")
        return 0  # graceful: text commentary already went out

    # 3. Drop into the import folder
    try:
        dest = os.path.join(IMPORT_DIR, filename)
        with open(local_tmp, "rb") as src, open(dest, "wb") as dst:
            dst.write(src.read())
    except OSError as e:
        log(f"import share unreachable, skipping voice break: {e}")
        return 0
    log(f"dropped {filename}")

    # 4. Wait for ingestion (placeholder rows have Type 0)
    conn = get_db()
    cur = conn.cursor()
    for _ in range(20):  # up to ~3.5 min
        cur.execute("SELECT Type, Title FROM Audio WHERE UID=?", (uid,))
        row = cur.fetchone()
        if row and row[0] == 17 and "Placeholder" not in (row[1] or ""):
            break
        time.sleep(10)
    else:
        log("import did not complete in time; will air next hour instead")
        conn.close()
        return 0

    # 5a. If the air bridge is driving playback, hand the break to it. The
    # bridge only starts audio during confirmed silence, so letting it place
    # the break avoids racing it -- and avoids the failure seen on 2026-08-02
    # 16:17, where this script's segue window expired and its slot-swap
    # fallback then found no playhead (the bridge does not set Status rows).
    if bridge_running():
        try:
            with open(PENDING_BREAK, "w", encoding="utf-8") as f:
                f.write(uid)
            log(f"air bridge is running -- handed break {uid} to it")
            conn.close()
            return 0
        except OSError as e:
            log(f"could not hand off to bridge ({e}); falling back")

    # 5b. Otherwise air it precisely at the next segue via PLAY UID
    if try_precise_air(uid):
        conn.close()
        return 0

    # 5b. Fallback: swap into an upcoming unloaded song slot in the log
    cur.execute("SELECT TOP 1 GIndex FROM Playlists WHERE Status IN (1,2) ORDER BY GIndex DESC")
    row = cur.fetchone()
    if not row:
        log("no playhead; skipping swap")
        conn.close()
        return 0
    # The hourly time-sync jumps over deck items near hour boundaries (observed
    # twice on-air), so avoid the first few items of any log hour — pick the
    # first song slot at least 4 items into its hour.
    cur.execute(
        "SELECT TOP 8 p.GIndex, a.Title, a.Artist FROM Playlists p "
        "JOIN Audio a ON p.uid = a.uid "
        "WHERE p.GIndex > ? AND p.Status = 0 AND a.Type = 16 ORDER BY p.GIndex ASC",
        (row[0],),
    )
    candidates = cur.fetchall()
    slot = None
    for c in candidates:
        item_index = int(round(float(c[0]) * 10000)) % 10000
        if item_index >= 4:
            slot = c
            break
    if slot is None and candidates:
        slot = candidates[-1]
    if not slot:
        log("no upcoming song slot; skipping swap")
        conn.close()
        return 0
    cur.execute("UPDATE Playlists SET uid=? WHERE GIndex=? AND Status=0", (uid, slot[0]))
    conn.commit()
    if cur.rowcount:
        log(f"ON DECK at {slot[0]} (bumped {slot[1]} - {slot[2]})")
    else:
        log("slot loaded before swap landed; will air next hour")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

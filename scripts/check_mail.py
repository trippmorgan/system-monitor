#!/usr/bin/env python3
"""Minimal IMAP inbox smoke check.

Credentials are intentionally read from environment variables so secrets are not
stored in this repository.
"""

import email
import imaplib
import os
import sys
from email.header import decode_header

HOST = os.environ.get("SYSTEM_MONITOR_IMAP_HOST", "imap.gmail.com")
USER = os.environ.get("SYSTEM_MONITOR_IMAP_USER")
PASS = os.environ.get("SYSTEM_MONITOR_IMAP_PASS")
LIMIT = int(os.environ.get("SYSTEM_MONITOR_MAIL_LIMIT", "5"))

if not USER or not PASS:
    print(
        "Missing SYSTEM_MONITOR_IMAP_USER or SYSTEM_MONITOR_IMAP_PASS; "
        "not checking mail.",
        file=sys.stderr,
    )
    sys.exit(2)

mail = imaplib.IMAP4_SSL(HOST)
try:
    mail.login(USER, PASS)
    mail.select("inbox")

    status, messages = mail.search(None, "ALL")
    if status != "OK":
        raise RuntimeError(f"IMAP search failed: {status}")

    email_ids = messages[0].split()
    print(f"Total emails: {len(email_ids)}")
    for last_id in email_ids[-LIMIT:]:
        status, msg_data = mail.fetch(last_id, "(RFC822)")
        if status != "OK":
            continue
        for response_part in msg_data:
            if isinstance(response_part, tuple):
                msg = email.message_from_bytes(response_part[1])
                subject, encoding = decode_header(msg.get("Subject", ""))[0]
                if isinstance(subject, bytes):
                    subject = subject.decode(encoding or "utf-8", errors="replace")
                print(f"[{last_id.decode()}] From: {msg.get('From', '')} | Subject: {subject}")
finally:
    try:
        mail.logout()
    except Exception:
        pass

#!/usr/bin/env python3
# Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
"""Observe Codex hooks without returning decisions or retaining conversation content."""
import datetime
import fcntl
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import uuid

STATES = {
    "SessionStart": "waiting", "UserPromptSubmit": "working",
    "PreToolUse": "working", "PostToolUse": "working",
    "PermissionRequest": "waiting", "Stop": "completed", "Interrupt": "waiting",
}


def write_status(payload, destination):
    event = payload.get("hook_event_name")
    if event not in STATES and event != "SessionEnd":
        return
    session_id = str(uuid.UUID(payload["session_id"]))
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = destination.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("Bridge directory must be owned by you with permissions 0700")
    # Lock serializes concurrent callbacks. No follow of user-supplied symlinks.
    lock = os.open(destination / (session_id + ".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        target = destination / (session_id + ".json")
        if event == "SessionEnd":
            target.unlink(missing_ok=True)
            return
        project = Path(str(payload.get("cwd", ""))).name
        project = "".join(c for c in project if c.isprintable())[:80] or "Codex session"
        record = {
            "schema": 1, "session_id": session_id, "project": project,
            "state": STATES[event], "event": event,
            "turn_id": str(payload.get("turn_id", ""))[:80] or None,
            "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        }
        fd, temp = tempfile.mkstemp(prefix=".status-", dir=destination)
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(record, stream)
            os.replace(temp, target)
        finally:
            Path(temp).unlink(missing_ok=True)
    finally:
        os.close(lock)


if __name__ == "__main__":
    try:
        # Bounded input; never persist prompts, tool input/output or auth fields.
        raw = sys.stdin.buffer.read(4 * 1024 * 1024 + 1)
        if len(raw) <= 4 * 1024 * 1024:
            payload = json.loads(raw)
            destination = Path(os.environ.get("BORING_NOTCH_AGENT_DIR", Path.home() / ".codex/notch-agent-status"))
            write_status(payload, destination)
    except Exception:
        # Monitoring errors must never block an agent or expose payloads.
        pass
    print("{}")

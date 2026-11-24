#!/usr/bin/env python3
"""
DAUVERSE REMOTE DESKTOP V1 — Official Claude Code Hook Adapter
Reads Claude Code hook JSON from stdin (Stop / SubagentStop / Notification),
computes RFC 2104 HMAC-SHA256 matching src/dauverse/ai_bridge.rs, and sends
the signed event to the local DAUVERSE AI Event Bridge loopback endpoint.
Strictly read-only with respect to AI credentials: never reads API keys, cookies, or OAuth tokens.
"""

import datetime
import hashlib
import hmac
import json
import os
import socket
import sys
import urllib.request
import uuid


def sign_envelope(event: dict, secret_key: bytes, issued_at_ms: int, nonce: str) -> dict:
    canonical = (
        f"DAUVERSE_AI_EVENT_V1|{event['event_id']}|{event['timestamp']}|"
        f"{event['source']}|{event['device_id']}|{event['project_id']}|"
        f"{event['task_id']}|\"{event['event_type']}\"|\"{event['status']}\""
        f"|{issued_at_ms}|{nonce}"
    ).encode("utf-8")
    sig_hex = hmac.new(secret_key, canonical, hashlib.sha256).hexdigest()
    return {
        "event": event,
        "issued_at_ms": issued_at_ms,
        "nonce": nonce,
        "signature_hex": sig_hex,
    }


def main() -> int:
    raw_stdin = sys.stdin.read().strip()
    payload = json.loads(raw_stdin) if raw_stdin else {}

    hook_name = str(payload.get("hook_event_name", "Stop"))
    session_id = str(payload.get("session_id", "claude-session"))
    cwd = str(payload.get("cwd", os.getcwd()))
    project_id = os.path.basename(cwd.rstrip("/\\")) or "workspace"

    if hook_name == "Notification":
        msg = str(payload.get("message", "Claude Code notification"))
        lower = msg.lower()
        if "permission" in lower or "approve" in lower or "allow" in lower:
            ev_type = "APPROVAL_REQUIRED"
            status = "WAITING_APPROVAL"
            severity = "HIGH"
        else:
            ev_type = "WAITING_USER_INPUT"
            status = "WAITING_INPUT"
            severity = "WARNING"
        summary = msg[:280]
    else:
        ev_type = "COMMAND_COMPLETED"
        status = "COMPLETED"
        severity = "SUCCESS"
        summary = f"Claude Code completed turn ({hook_name}) in {project_id}"

    now = datetime.datetime.now(datetime.timezone.utc)
    issued_ms = int(now.timestamp() * 1000)
    event = {
        "event_id": str(uuid.uuid4()),
        "timestamp": now.isoformat().replace("+00:00", "Z"),
        "source": "claude_code",
        "device_id": socket.gethostname(),
        "project_id": project_id,
        "task_id": session_id,
        "task_name": f"Claude Code ({project_id})",
        "event_type": ev_type,
        "status": status,
        "severity": severity,
        "progress": None,
        "summary": summary,
        "artifact_reference": None,
        "confidence": 1.0,
        "provenance": {
            "adapter_type": "OFFICIAL_HOOK",
            "evidence_verified": True,
            "exit_code": 0,
            "evidence_badge": f"Hook: {hook_name}",
        },
    }

    secret = os.environ.get("DAUVERSE_EVENT_HMAC_KEY", "").encode("utf-8")
    if len(secret) < 16:
        sys.stderr.write("DAUVERSE hook skipped: DAUVERSE_EVENT_HMAC_KEY not set (>=16 chars required).\n")
        return 0

    envelope = sign_envelope(event, secret, issued_ms, uuid.uuid4().hex)
    endpoint = os.environ.get("DAUVERSE_EVENT_ENDPOINT", "http://127.0.0.1:21188/v1/events")
    body = json.dumps(envelope).encode("utf-8")

    req = urllib.request.Request(
        endpoint,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            _ = resp.read()
    except Exception:
        spool = os.environ.get("DAUVERSE_OFFLINE_SPOOL")
        if spool:
            with open(spool, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(event) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

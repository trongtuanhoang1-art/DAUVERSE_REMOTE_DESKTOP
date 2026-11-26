#!/usr/bin/env python3
"""
DAUVERSE REMOTE DESKTOP V1 — Official Codex CLI Notify Hook Adapter
Usage in ~/.codex/config.toml:
  notify = ["python3", "E:/DAUVERSE_REMOTE_DESKTOP/scripts/hooks/codex_notify_hook.py"]
"""

import datetime
import hashlib
import hmac
import json
import math
import os
import re
import socket
import struct
import sys
import urllib.request
import uuid


def quantize_and_encode_f32(val: float, min_v: float, max_v: float, field_name: str) -> tuple[float, str]:
    if isinstance(val, bool) or not isinstance(val, (int, float)):
        raise ValueError(f"EVENT_REJECT_NON_NUMERIC_{field_name.upper()}")
    f64 = float(val)
    if not math.isfinite(f64):
        raise ValueError(f"EVENT_REJECT_NON_FINITE_{field_name.upper()}")
    raw_be = struct.pack(">f", f64)
    f32_val = struct.unpack(">f", raw_be)[0]
    bits = struct.unpack(">I", raw_be)[0]
    if not math.isfinite(f32_val):
        raise ValueError(f"EVENT_REJECT_NON_FINITE_{field_name.upper()}")
    if bits == 0x80000000:
        raise ValueError(f"EVENT_REJECT_NEGATIVE_ZERO_{field_name.upper()}")
    if f32_val < min_v or f32_val > max_v:
        raise ValueError(f"EVENT_REJECT_OUT_OF_RANGE_{field_name.upper()}")
    return f32_val, f"f32:{bits:08x}"


def canonical_signing_bytes_v3(event: dict, issued_at_ms: int, nonce: str) -> bytes:
    prov = event["provenance"]
    progress = event.get("progress")
    if progress is None:
        progress_tag = None
    else:
        f32_p, progress_tag = quantize_and_encode_f32(progress, 0.0, 100.0, "progress")
        event["progress"] = f32_p
    f32_c, confidence_tag = quantize_and_encode_f32(event["confidence"], 0.0, 1.0, "confidence")
    event["confidence"] = f32_c
    arr = [
        "DAUVERSE_AI_EVENT_V3",
        3,
        int(issued_at_ms),
        nonce,
        event["event_id"],
        event["timestamp"],
        event["source"],
        event["device_id"],
        event["project_id"],
        event["task_id"],
        event["task_name"],
        event["event_type"],
        event["status"],
        event["severity"],
        progress_tag,
        event["summary"],
        event["artifact_reference"],
        confidence_tag,
        [
            prov["adapter_type"],
            bool(prov["evidence_verified"]),
            prov["exit_code"],
            prov["evidence_badge"],
        ],
    ]
    return json.dumps(arr, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")


def sign_envelope(event: dict, secret_key: bytes, issued_at_ms: int, nonce: str) -> dict:
    canonical = canonical_signing_bytes_v3(event, issued_at_ms, nonce)
    sig_hex = hmac.new(secret_key, canonical, hashlib.sha256).hexdigest()
    return {
        "schema_version": 3,
        "event": event,
        "issued_at_ms": int(issued_at_ms),
        "nonce": nonce,
        "signature_hex": sig_hex,
    }


def extract_verified_test_badge(msg: str):
    m = re.search(r"\b(\d+/\d+\s+tests\s+PASS)\b", msg, re.IGNORECASE)
    return m.group(1) if m else None


def main() -> int:
    raw = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read().strip()
    payload = json.loads(raw) if raw else {}

    turn_type = str(payload.get("type", "agent-turn-complete"))
    thread_id = str(payload.get("thread-id", "codex-thread"))
    cwd = str(payload.get("cwd", os.getcwd()))
    project_id = os.path.basename(cwd.rstrip("/\\")) or "workspace"
    last_msg = str(payload.get("last-assistant-message", ""))

    badge = extract_verified_test_badge(last_msg)
    if badge:
        ev_type = "QA_PASSED"
    elif turn_type == "agent-turn-complete":
        ev_type = "COMMAND_COMPLETED"
    else:
        ev_type = "UNKNOWN_STATE"

    now = datetime.datetime.now(datetime.timezone.utc)
    issued_ms = int(now.timestamp() * 1000)
    event = {
        "event_id": str(uuid.uuid4()),
        "timestamp": now.isoformat().replace("+00:00", "Z"),
        "source": "codex_cli",
        "device_id": socket.gethostname(),
        "project_id": project_id,
        "task_id": thread_id,
        "task_name": f"Codex ({project_id})",
        "event_type": ev_type,
        "status": "COMPLETED" if ev_type in ("QA_PASSED", "COMMAND_COMPLETED") else "UNKNOWN",
        "severity": "SUCCESS" if ev_type in ("QA_PASSED", "COMMAND_COMPLETED") else "INFO",
        "progress": None,
        "summary": (last_msg.splitlines()[0][:240] if last_msg else f"Codex {turn_type}"),
        "artifact_reference": None,
        "confidence": 1.0 if turn_type == "agent-turn-complete" else 0.5,
        "provenance": {
            "adapter_type": "OFFICIAL_HOOK",
            "evidence_verified": turn_type == "agent-turn-complete",
            "exit_code": 0,
            "evidence_badge": badge,
        },
    }

    secret = os.environ.get("DAUVERSE_EVENT_HMAC_KEY", "").encode("utf-8")
    if len(secret) < 16:
        return 0

    envelope = sign_envelope(event, secret, issued_ms, uuid.uuid4().hex)
    endpoint = os.environ.get("DAUVERSE_EVENT_ENDPOINT", "http://127.0.0.1:21188/v1/events")
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(envelope, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            _ = resp.read()
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""
End-to-End Verification Suite:
1. Verifies Claude Code & Codex CLI official hook adapters generate valid RFC 2104 HMAC-SHA256
   signed envelopes matching src/dauverse/ai_bridge.rs canonical_signing_bytes.
2. Performs repository-wide pre-commit secret hygiene scan (Section 06).
"""

import hashlib
import hmac
import http.server
import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TEST_HMAC_SECRET = "dauverse_test_hmac_secret_32bytes_2026"


def verify_canonical_hmac(envelope: dict, secret: bytes) -> bool:
    ev = envelope["event"]
    canonical = (
        f"DAUVERSE_AI_EVENT_V1|{ev['event_id']}|{ev['timestamp']}|"
        f"{ev['source']}|{ev['device_id']}|{ev['project_id']}|"
        f"{ev['task_id']}|\"{ev['event_type']}\"|\"{ev['status']}\""
        f"|{envelope['issued_at_ms']}|{envelope['nonce']}"
    ).encode("utf-8")
    expected = hmac.new(secret, canonical, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, envelope["signature_hex"])


def run_hook_e2e_test() -> dict:
    received: list[dict] = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8")
            received.append(json.loads(body))
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')

        def log_message(self, format, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    env = os.environ.copy()
    env["DAUVERSE_EVENT_HMAC_KEY"] = TEST_HMAC_SECRET
    env["DAUVERSE_EVENT_ENDPOINT"] = f"http://127.0.0.1:{port}/v1/events"

    # 1. Test Claude Code hook
    claude_stdin = json.dumps({
        "hook_event_name": "Stop",
        "session_id": "claude-sess-001",
        "cwd": "/workspace/DAUVERSE-FT004",
    })
    res1 = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts/hooks/claude_code_hook.py")],
        input=claude_stdin,
        text=True,
        env=env,
        capture_output=True,
        check=True,
    )

    # 2. Test Codex CLI notify hook
    codex_arg = json.dumps({
        "type": "agent-turn-complete",
        "thread-id": "codex-qa-001",
        "cwd": "/workspace/DAUVERSE_REMOTE_DESKTOP",
        "last-assistant-message": "QA verification complete: 128/128 tests PASS",
    })
    res2 = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts/hooks/codex_notify_hook.py"), codex_arg],
        text=True,
        env=env,
        capture_output=True,
        check=True,
    )

    server.shutdown()
    assert len(received) == 2, f"Expected 2 signed hook events, got {len(received)}"
    for item in received:
        assert verify_canonical_hmac(item, TEST_HMAC_SECRET.encode("utf-8")), "HMAC mismatch!"

    assert received[0]["event"]["source"] == "claude_code"
    assert received[0]["event"]["status"] == "COMPLETED"
    assert received[1]["event"]["source"] == "codex_cli"
    assert received[1]["event"]["event_type"] == "QA_PASSED"
    assert received[1]["event"]["provenance"]["evidence_badge"] == "128/128 tests PASS"

    return {
        "hook_e2e_status": "REAL_VERIFIED",
        "events_verified": len(received),
        "claude_exit": res1.returncode,
        "codex_exit": res2.returncode,
    }


def run_secret_scan() -> dict:
    secret_patterns = [
        (r"sk-ant-api\d{2}-[A-Za-z0-9_\-]{20,}", "Anthropic API Key"),
        (r"sk-proj-[A-Za-z0-9_\-]{20,}", "OpenAI Project Key"),
        (r"ghp_[A-Za-z0-9]{36}", "GitHub Classic PAT"),
        (r"github_pat_[A-Za-z0-9_]{40,}", "GitHub Fine-Grained PAT"),
        (r"AIza[0-9A-Za-z\-_]{35}", "Google API Key"),
        (r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----", "Private Key PEM"),
    ]
    tracked = subprocess.check_output(
        ["git", "ls-files"], cwd=REPO_ROOT, text=True
    ).splitlines()
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard"], cwd=REPO_ROOT, text=True
    ).splitlines()

    findings = []
    scanned_count = 0
    for rel in set(tracked + untracked):
        p = REPO_ROOT / rel
        if not p.is_file() or p.stat().st_size > 2_000_000:
            continue
        if p.suffix.lower() in {".png", ".ico", ".so", ".dll", ".exe", ".zip", ".ttf"}:
            continue
        try:
            content = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        scanned_count += 1
        for pat, desc in secret_patterns:
            if re.search(pat, content):
                findings.append({"file": rel, "pattern": desc})

    assert len(findings) == 0, f"SECRET LEAK DETECTED: {findings}"
    return {
        "secret_scan_status": "PASS_ZERO_SECRETS",
        "files_scanned": scanned_count,
        "findings": findings,
    }


def main() -> None:
    hook_res = run_hook_e2e_test()
    sec_res = run_secret_scan()
    report = {
        "suite": "E2E_HOOKS_AND_SECRET_HYGIENE",
        "hooks": hook_res,
        "secret_scan": sec_res,
    }
    out_path = REPO_ROOT / "ARTIFACTS/evidence/ai_bridge_and_secret_scan.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

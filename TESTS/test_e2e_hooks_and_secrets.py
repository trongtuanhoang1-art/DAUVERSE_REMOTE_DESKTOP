#!/usr/bin/env python3
"""
DAUVERSE REMOTE DESKTOP V1 — End-to-End Live Rust `.so` Hook Verification & Secret Hygiene Scanner
1. Loads the compiled `target/release/liblibrustdesk.so` via ctypes FFI, initializes `DauverseRuntime`
   (which auto-starts the real Rust `127.0.0.1` HTTP AI Event Bridge + NotificationCenter sink),
   executes `scripts/hooks/claude_code_hook.py` and `scripts/hooks/codex_notify_hook.py` against
   that real Rust HTTP server, and asserts via C-ABI FFI that:
   - Both signed events are verified and ingested by Rust `AiEventBridge`,
   - Both publish real notifications into Rust `NotificationCenter`,
   - A forged signature POST to the Rust HTTP server is rejected (`HTTP 401`) and increments `rejected_security_count`.
2. Scans all tracked/untracked source files for accidentally leaked credentials/tokens.
"""

import ctypes
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def invoke_rust_ffi(lib: ctypes.CDLL, cmd: str, payload: dict | None = None) -> dict:
    cmd_bytes = cmd.encode("utf-8")
    payload_bytes = json.dumps(payload or {}).encode("utf-8")
    raw_ptr = lib.dauverse_invoke(cmd_bytes, payload_bytes)
    if not raw_ptr:
        raise RuntimeError("NULL_FFI_POINTER")
    try:
        json_str = ctypes.cast(raw_ptr, ctypes.c_char_p).value.decode("utf-8")
        return json.loads(json_str)
    finally:
        lib.dauverse_free_str(raw_ptr)


def run_live_rust_hook_e2e_test() -> dict:
    so_path = REPO_ROOT / "target" / "release" / "liblibrustdesk.so"
    if not so_path.is_file():
        raise FileNotFoundError(f"Compiled release library not found at {so_path}")

    secret = "dauverse-e2e-live-rust-secret-key-2026-verified"
    tmp_dir = tempfile.mkdtemp(prefix="dauverse_e2e_rust_")
    os.environ["DAUVERSE_DATA_DIR"] = tmp_dir
    os.environ["DAUVERSE_EVENT_HMAC_KEY"] = secret
    os.environ["DAUVERSE_EVENT_BRIDGE_PORT"] = "0"

    import shutil
    try:
        lib = ctypes.CDLL(str(so_path))
        lib.dauverse_invoke.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        lib.dauverse_invoke.restype = ctypes.c_void_p
        lib.dauverse_free_str.argtypes = [ctypes.c_void_p]
        lib.dauverse_free_str.restype = None

        snap = invoke_rust_ffi(lib, "dashboard_snapshot")
        assert snap.get("ok") is True, f"FFI snapshot failed: {snap}"
        data = snap["data"]
        endpoint = data["bridge_endpoint"]
        port = int(data["bridge_port"])
        assert port > 0 and endpoint.startswith("http://127.0.0.1:"), f"Rust HTTP gateway not bound: {endpoint}"

        env = os.environ.copy()
        env["DAUVERSE_EVENT_HMAC_KEY"] = secret
        env["DAUVERSE_EVENT_ENDPOINT"] = endpoint
        env["DAUVERSE_EVENT_BRIDGE_URL"] = endpoint
        env["DAUVERSE_DEVICE_ID"] = "HOME-RTX3060"
        env["DAUVERSE_PROJECT_ID"] = "DAUVERSE-REMOTE-V1"

        # 1. Execute Claude Code official hook against live Rust HTTP server
        claude_payload = json.dumps({
            "hook_event_name": "Stop",
            "session_id": "claude-live-rust-01",
            "message": "Completed Rust + Flutter remediation cleanly",
        })
        p1 = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts/hooks/claude_code_hook.py")],
            input=claude_payload.encode("utf-8"),
            env=env,
            capture_output=True,
            check=True,
        )

        # 2. Execute Codex CLI notify hook against live Rust HTTP server
        codex_arg = json.dumps({
            "type": "agent-turn-complete",
            "turn-id": "codex-live-rust-02",
            "last-assistant-message": "All 16 security negative tests verified PASS",
        })
        p2 = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts/hooks/codex_notify_hook.py"), codex_arg],
            env=env,
            capture_output=True,
            check=True,
        )

        # 3. Attempt forged HMAC POST directly against live Rust HTTP server -> must return HTTP 401
        forged_body = json.dumps({
            "event": {
                "event_id": "forged-evt-999",
                "timestamp": "2026-11-24T18:00:00Z",
                "source": "attacker",
                "device_id": "ROGUE",
                "project_id": "NONE",
                "task_id": "t1",
                "task_name": "Spoof",
                "event_type": "TASK_COMPLETED",
                "status": "COMPLETED",
                "severity": "SUCCESS",
                "progress": 100.0,
                "summary": "forged",
                "artifact_reference": None,
                "confidence": 1.0,
                "provenance": {
                    "adapter_type": "OFFICIAL_HOOK",
                    "evidence_verified": True,
                    "exit_code": 0,
                    "evidence_badge": "FAKE",
                },
            },
            "issued_at_ms": 1795543200000,
            "nonce": "deadbeef01020304",
            "signature_hex": "00" * 32,
        }).encode("utf-8")
        req = urllib.request.Request(
            endpoint,
            data=forged_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        forged_http_code = None
        try:
            urllib.request.urlopen(req, timeout=2.0)
        except urllib.error.HTTPError as e:
            forged_http_code = e.code
        assert forged_http_code == 401, f"Expected HTTP 401 on forged HMAC, got {forged_http_code}"

        # 4. Verify live Rust state via C-ABI FFI & capture smoke + benchmark evidence
        after_resp = invoke_rust_ffi(lib, "dashboard_snapshot")
        after = after_resp["data"]
        bench_resp = invoke_rust_ffi(lib, "run_benchmark")
        assert bench_resp.get("ok") is True, f"Benchmark FFI failed: {bench_resp}"
        assert str(bench_resp["data"].get("benchmark_scope", "")).startswith("LOCAL_PIPELINE_MICROBENCHMARK_ONLY")

        out_dir = REPO_ROOT / "ARTIFACTS" / "evidence"
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "release_ffi_smoke_test.json").write_text(
            json.dumps(after_resp, indent=2), encoding="utf-8"
        )
        (out_dir / "benchmark_results.json").write_text(
            json.dumps(bench_resp["data"], indent=2), encoding="utf-8"
        )

        live_tasks = after["ai_summary"]["live_tasks"]
        unread = after["notifications"]["unread_count"]
        rejected = after["ai_summary"]["rejected_security_count"]
        sources = {t["source"] for t in live_tasks}

        assert "claude_code" in sources and "codex_cli" in sources, f"Missing sources in Rust live_tasks: {sources}"
        assert unread >= 2, f"Expected >=2 unread notifications in Rust NotificationCenter, got {unread}"
        assert rejected >= 1, f"Expected >=1 rejected forged event in Rust AiEventBridge, got {rejected}"

        return {
            "hook_e2e_status": "REAL_VERIFIED_AGAINST_LIVE_RUST_SO",
            "rust_bridge_port": port,
            "events_verified_in_rust": len(live_tasks),
            "notifications_published_in_rust": unread,
            "forged_http_rejected_status": forged_http_code,
            "claude_exit": p1.returncode,
            "codex_exit": p2.returncode,
        }
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


SECRET_PATTERNS = [
    ("OpenAI / Anthropic Secret Key", re.compile(r"sk-(?:proj-|ant-)[A-Za-z0-9_\-]{20,}")),
    ("GitHub Personal Access Token", re.compile(r"(?:ghp_|github_pat_)[A-Za-z0-9_]{25,}")),
    ("Google API Key", re.compile(r"AIza[0-9A-Za-z\-_]{35}")),
    ("Private Key PEM Block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("Slack Bot Token", re.compile(r"xox[baprs]-[0-9A-Za-z\-]{20,}")),
]

SKIP_DIRS = {
    ".git",
    "target",
    "build",
    ".dart_tool",
    "ephemeral",
    "ARTIFACTS",
}


KNOWN_UPSTREAM_TEST_FIXTURES = {
    "libs/hbb_common/tests/data/websocket-key.pem",
}


def run_secret_hygiene_scan() -> dict:
    findings = []
    upstream_fixtures_noted = []
    scanned_files = 0
    for root, dirs, files in os.walk(REPO_ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fname in files:
            fpath = Path(root) / fname
            rel_str = str(fpath.relative_to(REPO_ROOT)).replace("\\", "/")
            if fpath.name == "test_e2e_hooks_and_secrets.py":
                continue
            if fpath.suffix.lower() in {".png", ".ico", ".jpg", ".so", ".dll", ".exe", ".ttf", ".otf", ".z"}:
                continue
            try:
                text = fpath.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            scanned_files += 1
            for label, pat in SECRET_PATTERNS:
                if pat.search(text):
                    if rel_str in KNOWN_UPSTREAM_TEST_FIXTURES:
                        upstream_fixtures_noted.append({"file": rel_str, "rule": label})
                    else:
                        findings.append({"file": rel_str, "rule": label})
    assert len(findings) == 0, f"Secret hygiene scan failed: {findings}"
    return {
        "secret_scan_status": "PASS_ZERO_SECRETS",
        "files_scanned": scanned_files,
        "findings": findings,
        "known_upstream_test_fixtures": upstream_fixtures_noted,
    }


if __name__ == "__main__":
    hook_res = run_live_rust_hook_e2e_test()
    sec_res = run_secret_hygiene_scan()
    summary = {
        "suite": "E2E_LIVE_RUST_HOOKS_AND_SECRET_HYGIENE",
        "hooks": hook_res,
        "secret_scan": sec_res,
    }
    out_dir = REPO_ROOT / "ARTIFACTS" / "evidence"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "ai_bridge_and_secret_scan.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))

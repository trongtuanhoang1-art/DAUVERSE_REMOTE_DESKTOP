#!/usr/bin/env python3
"""
DAUVERSE REMOTE DESKTOP V1 (RC2) — Multi-Process Live Rust `.so` E2E Security Matrix & Secret Hygiene Scanner
1. Spawns three sequential isolated OS processes loading `target/release/liblibrustdesk.so` via ctypes C-ABI FFI:
   - Phase 1: Initializes runtime, seals Step-Up PIN (`0600`), persists user settings (`F07`), runs official
     `claude_code_hook.py` & `codex_notify_hook.py` against live loopback HTTP AI Event Bridge, and records
     a signed `DAUVERSE_AI_EVENT_V2` envelope (`evt-linux-persist-001`).
   - Phase 2 (fresh OS process on same `DAUVERSE_DATA_DIR`): Verifies durable settings/notifications reopen (`F07`),
     cross-restart replay rejection (`F09`), 10-field HMAC v2 tamper rejection + schema v1 rejection + untrusted
     source adapter rejection (`F01`), Step-Up PIN unauthenticated overwrite denial + authenticated rotation +
     grant token + 5-strike lockout (`F05`), headless truthfulness (`F04`), honest `None` disconnected FPS (`F10`),
     spoofed publisher signature rejection on unsigned package (`F12`), zero-socket dry-run Wake-on-LAN (`F13`),
     and confined no-follow receive SHA-256 + truncation + symlink rejection (`F14`, `F16`).
   - Phase 3 (fresh OS process with corrupted `step_up_pin.vault`): Verifies `SECURITY_VAULT_CORRUPTED_FAIL_CLOSED`
     without silent PIN reset (`F05`, `F07`).
2. Scans all repository files for accidentally leaked credentials/tokens.
"""

import ctypes
import hashlib
import hmac
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
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


def sign_v2(secret: str, event_obj: dict, issued_at_ms: int, nonce: str) -> str:
    prov = event_obj["provenance"]
    prog = event_obj.get("progress")
    prog_str = None if prog is None else f"{float(prog):.4f}"
    conf_str = f"{float(event_obj['confidence']):.4f}"
    payload = [
        "DAUVERSE_AI_EVENT_V2",
        2,
        int(issued_at_ms),
        str(nonce),
        event_obj["event_id"],
        event_obj["timestamp"],
        event_obj["source"],
        event_obj["device_id"],
        event_obj["project_id"],
        event_obj["task_id"],
        event_obj["task_name"],
        event_obj["event_type"],
        event_obj["status"],
        event_obj["severity"],
        prog_str,
        event_obj["summary"],
        event_obj.get("artifact_reference"),
        conf_str,
        [
            prov["adapter_type"],
            bool(prov["evidence_verified"]),
            prov.get("exit_code"),
            prov.get("evidence_badge"),
        ],
    ]
    canonical = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hmac.new(secret.encode("utf-8"), canonical, hashlib.sha256).hexdigest()


def post_json(url: str, obj: dict) -> tuple[int, dict]:
    req = urllib.request.Request(
        url,
        data=json.dumps(obj).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        return e.code, (json.loads(raw) if raw.strip().startswith("{") else {"raw": raw})


def _load_so() -> ctypes.CDLL:
    candidates = []
    if os.environ.get("DAUVERSE_SO_PATH"):
        candidates.append(Path(os.environ["DAUVERSE_SO_PATH"]))
    candidates.append(REPO_ROOT / "target" / "release" / "liblibrustdesk.so")
    candidates.append(REPO_ROOT / "target" / "debug" / "liblibrustdesk.so")
    so_path = next((p for p in candidates if p.is_file()), None)
    if so_path is None:
        raise FileNotFoundError(f"Compiled shared library not found in {[str(c) for c in candidates]}")
    lib = ctypes.CDLL(str(so_path))
    lib.dauverse_invoke.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.dauverse_invoke.restype = ctypes.c_void_p
    lib.dauverse_free_str.argtypes = [ctypes.c_void_p]
    lib.dauverse_free_str.restype = None
    return lib


def _worker_phase(phase: str, data_dir: Path, secret: str) -> dict:
    os.environ["DAUVERSE_DATA_DIR"] = str(data_dir)
    os.environ["DAUVERSE_EVENT_HMAC_KEY"] = secret
    os.environ["DAUVERSE_EVENT_BRIDGE_PORT"] = "0"

    if phase == "phase3_corrupt":
        corrupt_dir = data_dir / "isolated_corrupt_vault"
        corrupt_dir.mkdir(parents=True, exist_ok=True)
        (corrupt_dir / "step_up_pin.vault").write_bytes(b"CORRUPTED_VAULT_BYTES")
        os.environ["DAUVERSE_DATA_DIR"] = str(corrupt_dir)

    lib = _load_so()

    if phase == "phase1":
        snap = invoke_rust_ffi(lib, "dashboard_snapshot")
        assert snap.get("ok") is True, f"FFI snapshot failed: {snap}"
        data = snap["data"]
        endpoint = data["bridge_endpoint"]
        port = int(data["bridge_port"])
        assert port > 0 and endpoint.startswith("http://127.0.0.1:"), f"Bridge not bound: {endpoint}"

        pin_res = invoke_rust_ffi(lib, "set_step_up_pin", {"pin": "LinuxVault#2026"})
        assert pin_res.get("ok") is True, f"Initial PIN enrollment failed: {pin_res}"
        vault_file = data_dir / "step_up_pin.vault"
        mode = stat.S_IMODE(vault_file.stat().st_mode)
        assert mode == 0o600, f"Expected 0600 on step_up_pin.vault, got {oct(mode)}"
        assert b"LinuxVault#2026" not in vault_file.read_bytes()

        assert invoke_rust_ffi(lib, "set_performance_mode", {"mode": "HIGH_QUALITY"})["ok"] is True
        assert invoke_rust_ffi(
            lib,
            "set_clipboard_policy",
            {"enabled": True, "allow_text_unicode": True, "allow_images": True, "allow_files": False},
        )["ok"] is True
        assert invoke_rust_ffi(lib, "transfer_set_policy", {"bandwidth_limit_kbps": 4096})["ok"] is True

        env = os.environ.copy()
        env["DAUVERSE_EVENT_HMAC_KEY"] = secret
        env["DAUVERSE_EVENT_ENDPOINT"] = endpoint
        env["DAUVERSE_EVENT_BRIDGE_URL"] = endpoint
        env["DAUVERSE_DEVICE_ID"] = "HOME-RTX3060"
        env["DAUVERSE_PROJECT_ID"] = "DAUVERSE-REMOTE-V1"

        p1 = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts/hooks/claude_code_hook.py")],
            input=json.dumps({
                "hook_event_name": "Stop",
                "session_id": "claude-live-rc2-01",
                "message": "Completed RC2 full-payload HMAC v2 verification",
            }).encode("utf-8"),
            env=env,
            capture_output=True,
            check=True,
        )
        p2 = subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "scripts/hooks/codex_notify_hook.py"),
                json.dumps({
                    "type": "agent-turn-complete",
                    "turn-id": "codex-live-rc2-02",
                    "last-assistant-message": "All 16 findings verified in live FFI",
                }),
            ],
            env=env,
            capture_output=True,
            check=True,
        )

        now_ms = int(time.time() * 1000)
        persist_evt = {
            "event_id": "evt-linux-persist-001",
            "timestamp": "2026-11-25T15:00:00Z",
            "source": "codex_cli",
            "device_id": "HOME-RTX3060",
            "project_id": "DAUVERSE-REMOTE-V1",
            "task_id": "persist-task-1",
            "task_name": "Durable Replay Sentinel",
            "event_type": "TASK_COMPLETED",
            "status": "COMPLETED",
            "severity": "SUCCESS",
            "progress": 100.0,
            "summary": "Accepted before process restart",
            "artifact_reference": "ARTIFACTS/evidence/rc2_security_negative_matrix.json",
            "confidence": 1.0,
            "provenance": {
                "adapter_type": "OFFICIAL_HOOK",
                "evidence_verified": True,
                "exit_code": 0,
                "evidence_badge": "HOOK_EXIT_0",
            },
        }
        persist_env = {
            "schema_version": 2,
            "event": persist_evt,
            "issued_at_ms": now_ms,
            "nonce": "linuxpersist0001",
            "signature_hex": sign_v2(secret, persist_evt, now_ms, "linuxpersist0001"),
        }
        c_code, c_body = post_json(endpoint, persist_env)
        assert c_code == 200, f"Expected 200 on persist_env, got {c_code}: {c_body}"
        (data_dir / "saved_persist_envelope.json").write_text(json.dumps(persist_env), encoding="utf-8")

        return {
            "phase1": "PASS",
            "bridge_port": port,
            "claude_exit": p1.returncode,
            "codex_exit": p2.returncode,
            "vault_mode_octal": oct(mode),
        }

    if phase == "phase2":
        snap_resp = invoke_rust_ffi(lib, "dashboard_snapshot")
        assert snap_resp.get("ok") is True, f"Phase 2 snapshot failed: {snap_resp}"
        d = snap_resp["data"]
        endpoint = d["bridge_endpoint"]

        # F07: Settings & notification journal persisted across process exit/reopen
        assert d["performance"]["active_mode"] == "HIGH_QUALITY", f"F07 settings lost: {d['performance']}"
        assert d["clipboard"]["policy"]["allow_files"] is False, f"F07 clipboard lost: {d['clipboard']}"
        assert d["transfer_queue"]["bandwidth_limit_kbps"] == 4096, f"F07 bandwidth lost: {d['transfer_queue']}"
        assert d["notifications"]["unread_count"] >= 3, f"F07 notifications lost: {d['notifications']}"

        # F05: Step-Up PIN reopen, unauthenticated overwrite refusal, authenticated rotation, grant token, 5-strike lockout
        assert invoke_rust_ffi(
            lib, "verify_step_up_pin", {"pin": "LinuxVault#2026", "scope": "POWER_CONTROL"}
        )["ok"] is True
        overwrite_try = invoke_rust_ffi(lib, "set_step_up_pin", {"pin": "Unauthorized#999"})
        assert overwrite_try["ok"] is False and "SECURITY_DENY_CURRENT_PIN_REQUIRED" in overwrite_try.get("error", "")
        wrong_rot = invoke_rust_ffi(
            lib,
            "change_step_up_pin",
            {"current_pin": "Wrong#0000", "new_pin": "Rotated#2027"},
        )
        assert wrong_rot["ok"] is False
        good_rot = invoke_rust_ffi(
            lib,
            "change_step_up_pin",
            {"current_pin": "LinuxVault#2026", "new_pin": "Rotated#2027"},
        )
        assert good_rot["ok"] is True
        grant_res = invoke_rust_ffi(
            lib, "verify_step_up_pin", {"pin": "Rotated#2027", "scope": "SHUTDOWN"}
        )
        assert grant_res["ok"] is True and grant_res["data"].get("token_id"), f"Missing token_id: {grant_res}"
        tok_res = invoke_rust_ffi(
            lib,
            "verify_step_up_token",
            {
                "token_id": grant_res["data"]["token_id"],
                "scope": "SHUTDOWN",
            },
        )
        assert tok_res["ok"] is True, f"Grant token verification failed: {tok_res}"

        # F09: Cross-restart replay rejected via durable bridge_replay_journal.json
        saved_env = json.loads((data_dir / "saved_persist_envelope.json").read_text(encoding="utf-8"))
        replay_code, _ = post_json(endpoint, saved_env)
        assert replay_code == 401, f"F09 cross-restart replay not rejected: {replay_code}"

        # F01: 10-field tamper matrix + schema v1 + untrusted source claiming OFFICIAL_HOOK
        now_ms = int(time.time() * 1000)
        base_evt = {
            "event_id": "evt-f01-e2e",
            "timestamp": "2026-11-25T15:01:00Z",
            "source": "claude_code",
            "device_id": "HOME-RTX3060",
            "project_id": "DAUVERSE-REMOTE-V1",
            "task_id": "f01-e2e",
            "task_name": "Original Task",
            "event_type": "TASK_COMPLETED",
            "status": "COMPLETED",
            "severity": "SUCCESS",
            "progress": 100.0,
            "summary": "Original verified summary",
            "artifact_reference": "orig.tar.gz",
            "confidence": 1.0,
            "provenance": {
                "adapter_type": "OFFICIAL_HOOK",
                "evidence_verified": True,
                "exit_code": 0,
                "evidence_badge": "EXIT_0",
            },
        }
        valid_sig = sign_v2(secret, base_evt, now_ms, "f01e2enonce00001")
        mutations = [
            ("task_name", lambda e: e.update({"task_name": "Tampered"})),
            ("summary", lambda e: e.update({"summary": "Tampered summary"})),
            ("severity", lambda e: e.update({"severity": "CRITICAL"})),
            ("progress", lambda e: e.update({"progress": 5.0})),
            ("artifact_reference", lambda e: e.update({"artifact_reference": "evil.bin"})),
            ("confidence", lambda e: e.update({"confidence": 0.1})),
            ("provenance.adapter_type", lambda e: e["provenance"].update({"adapter_type": "APPROVED_WRAPPER_ADAPTER"})),
            ("provenance.evidence_verified", lambda e: e["provenance"].update({"evidence_verified": False})),
            ("provenance.exit_code", lambda e: e["provenance"].update({"exit_code": 2})),
            ("provenance.evidence_badge", lambda e: e["provenance"].update({"evidence_badge": "FAKE"})),
        ]
        rejected_fields = []
        for fname, mut_fn in mutations:
            cloned = json.loads(json.dumps(base_evt))
            mut_fn(cloned)
            m_code, _ = post_json(
                endpoint,
                {
                    "schema_version": 2,
                    "event": cloned,
                    "issued_at_ms": now_ms,
                    "nonce": "f01e2enonce00001",
                    "signature_hex": valid_sig,
                },
            )
            assert m_code == 401, f"F01 mutation '{fname}' accepted! HTTP {m_code}"
            rejected_fields.append(fname)

        v1_code, _ = post_json(
            endpoint,
            {
                "schema_version": 1,
                "event": base_evt,
                "issued_at_ms": now_ms,
                "nonce": "v1e2enonce000001",
                "signature_hex": valid_sig,
            },
        )
        assert v1_code == 401, f"Schema v1 was not rejected: {v1_code}"

        untrusted_evt = json.loads(json.dumps(base_evt))
        untrusted_evt["event_id"] = "evt-untrusted-desktop"
        untrusted_evt["source"] = "claude_desktop"
        untrusted_code, _ = post_json(
            endpoint,
            {
                "schema_version": 2,
                "event": untrusted_evt,
                "issued_at_ms": now_ms,
                "nonce": "untrustede2e0001",
                "signature_hex": sign_v2(secret, untrusted_evt, now_ms, "untrustede2e0001"),
            },
        )
        assert untrusted_code == 401, f"Untrusted source claiming OFFICIAL_HOOK was not rejected: {untrusted_code}"

        # F04: Headless truthfulness
        hl_act = invoke_rust_ffi(lib, "headless_activate", {})
        assert hl_act["ok"] is False, f"F04 headless_activate should fail: {hl_act}"
        hl_state = invoke_rust_ffi(lib, "dashboard_snapshot")["data"]["headless"]
        assert hl_state["virtual_display_active"] is False
        wdk_res = invoke_rust_ffi(
            lib,
            "headless_request_driver",
            {"whql_signed": False, "self_signed_root": True, "boss_approved": True, "step_up_pin": "Rotated#2027"},
        )
        assert wdk_res["ok"] is False, f"WDKTestCert was not rejected: {wdk_res}"

        # F10: Disconnected measured_fps is None (never target_fps)
        perf = invoke_rust_ffi(lib, "dashboard_snapshot")["data"]["performance"]
        assert perf.get("measured_fps") is None and "fps" not in perf, f"F10 synthetic fps leaked: {perf}"
        assert perf["configured_target_fps"] > 0

        # F12: Unsigned package claiming VERIFIED_TRUSTED_PUBLISHER is downgraded to UNSIGNED_BUILD & blocked from auto-update
        fake_pkg = data_dir / "unsigned_update.bin"
        fake_pkg.write_bytes(b"UNSIGNED_PAYLOAD")
        upd = invoke_rust_ffi(
            lib,
            "verify_update_package",
            {
                "artifact_path": str(fake_pkg),
                "descriptor": {
                    "version": "1.0.1",
                    "download_url": "https://example.invalid/update.exe",
                    "expected_sha256": hashlib.sha256(b"UNSIGNED_PAYLOAD").hexdigest(),
                    "signature_status": "VERIFIED_TRUSTED_PUBLISHER",
                    "release_notes_vi": "RC2 test descriptor",
                },
            },
        )
        assert upd["ok"] is True and upd["data"]["safe_for_auto_update"] is False, f"F12 failed: {upd}"
        assert upd["data"]["signature_status"] in ("UNSIGNED_BUILD", "UNVERIFIED_PUBLISHER"), f"F12 status: {upd}"

        # F13: Dry-run Wake-on-LAN sends zero network traffic
        wol = invoke_rust_ffi(
            lib,
            "smart_power_action",
            {
                "operation": "WAKE_ON_LAN",
                "dry_run": True,
                "step_up_pin": "Rotated#2027",
                "mac": "AA:BB:CC:DD:EE:FF",
                "target": "127.0.0.1:9",
            },
        )
        assert wol["ok"] is True and wol["data"]["executed"] is False, f"F13 dry-run failed: {wol}"

        # F14 & F16: Confined receive SHA-256 + size + symlink escape defense
        rx_root = data_dir / "rx_confined"
        rx_root.mkdir(parents=True, exist_ok=True)
        good_file = rx_root / "dataset_chunk.bin"
        good_bytes = b"VERIFIED_RECEIVE_CHUNK\n" * 32
        good_file.write_bytes(good_bytes)

        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 801,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "files": ["dataset_chunk.bin"],
                "total_bytes": len(good_bytes),
            },
        )["ok"] is True
        fin_ok = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 801})
        assert fin_ok["ok"] is True and fin_ok["data"].get("computed_sha256"), f"F16 valid finalize failed: {fin_ok}"

        trunc_file = rx_root / "truncated.bin"
        trunc_file.write_bytes(b"123")
        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 802,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "files": ["truncated.bin"],
                "total_bytes": 512,
            },
        )["ok"] is True
        fin_trunc = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 802})
        assert fin_trunc["ok"] is False, f"F16 truncated file was not rejected: {fin_trunc}"

        outside_secret = data_dir / "outside_target.txt"
        outside_secret.write_bytes(b"TOP_SECRET")
        sym_escape = rx_root / "symlink_escape.txt"
        sym_escape.symlink_to(outside_secret)
        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 803,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "files": ["symlink_escape.txt"],
                "total_bytes": 10,
            },
        )["ok"] is True
        fin_sym = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 803})
        assert fin_sym["ok"] is False, f"F14 symlink escape was not rejected: {fin_sym}"

        # F05: 5 wrong PIN attempts lock out step-up verification even when 6th attempt uses valid PIN
        for _ in range(5):
            assert invoke_rust_ffi(
                lib, "verify_step_up_pin", {"pin": "Wrong#0000", "scope": "POWER_CONTROL"}
            )["ok"] is False
        locked = invoke_rust_ffi(
            lib, "verify_step_up_pin", {"pin": "Rotated#2027", "scope": "POWER_CONTROL"}
        )
        assert locked["ok"] is False and "LOCKED" in locked.get("error", "").upper(), f"F05 lockout failed: {locked}"

        after_resp = invoke_rust_ffi(lib, "dashboard_snapshot")
        bench_resp = invoke_rust_ffi(lib, "run_benchmark")
        assert bench_resp.get("ok") is True
        assert str(bench_resp["data"].get("benchmark_scope", "")).startswith("LOCAL_PIPELINE_MICROBENCHMARK_ONLY")

        out_dir = REPO_ROOT / "ARTIFACTS" / "evidence"
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "release_ffi_smoke_test.json").write_text(json.dumps(after_resp, indent=2), encoding="utf-8")
        (out_dir / "benchmark_results.json").write_text(json.dumps(bench_resp["data"], indent=2), encoding="utf-8")

        return {
            "phase2": "PASS",
            "settings_reopen_verified": True,
            "cross_restart_replay_rejected_http": replay_code,
            "f01_mutated_fields_rejected": rejected_fields,
            "schema_v1_rejected_http": v1_code,
            "untrusted_source_rejected_http": untrusted_code,
            "step_up_pin_overwrite_blocked": True,
            "step_up_pin_rotation_and_lockout_verified": True,
            "headless_denied_stays_inactive": True,
            "disconnected_measured_fps_is_none": True,
            "spoofed_unsigned_auto_update_blocked": True,
            "wol_dry_run_zero_side_effect": True,
            "receive_sha256_truncation_and_symlink_defended": True,
        }

    if phase == "phase3_corrupt":
        sec = invoke_rust_ffi(lib, "security_summary")["data"]["summary"]
        assert sec["vault_healthy"] is False, f"Expected vault_healthy False on corrupt vault: {sec}"
        set_try = invoke_rust_ffi(lib, "set_step_up_pin", {"pin": "ResetBypass#2026"})
        ver_try = invoke_rust_ffi(
            lib, "verify_step_up_pin", {"pin": "Rotated#2027", "scope": "POWER_CONTROL"}
        )
        assert set_try["ok"] is False and "FAIL_CLOSED" in set_try.get("error", ""), f"set_try: {set_try}"
        assert ver_try["ok"] is False and "FAIL_CLOSED" in ver_try.get("error", ""), f"ver_try: {ver_try}"
        return {"phase3_corrupt_vault_fail_closed": "PASS"}

    raise ValueError(f"Unknown phase: {phase}")


def run_live_rust_hook_e2e_test() -> dict:
    secret = "dauverse-e2e-live-rust-secret-key-2026-verified"
    tmp_dir = Path(tempfile.mkdtemp(prefix="dauverse_e2e_rc2_"))
    try:
        results = {}
        for phase in ("phase1", "phase2", "phase3_corrupt"):
            proc = subprocess.run(
                [sys.executable, str(Path(__file__).resolve()), "--worker-phase", phase, str(tmp_dir), secret],
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode != 0:
                raise RuntimeError(
                    f"Worker phase '{phase}' failed (exit {proc.returncode}):\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
                )
            results[phase] = json.loads(proc.stdout.strip().splitlines()[-1])

        matrix_summary = {
            "hook_e2e_status": "REAL_VERIFIED_MULTI_PROCESS_AGAINST_LIVE_RUST_SO",
            "phases": results,
        }
        out_dir = REPO_ROOT / "ARTIFACTS" / "evidence"
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "rc2_security_negative_matrix.json").write_text(
            json.dumps(matrix_summary, indent=2), encoding="utf-8"
        )
        return matrix_summary
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
            if fpath.suffix.lower() in {".png", ".ico", ".jpg", ".so", ".dll", ".exe", ".ttf", ".otf", ".z", ".zip", ".bundle"}:
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
    if len(sys.argv) == 5 and sys.argv[1] == "--worker-phase":
        res = _worker_phase(sys.argv[2], Path(sys.argv[3]), sys.argv[4])
        print(json.dumps(res))
        sys.exit(0)

    hook_res = run_live_rust_hook_e2e_test()
    sec_res = run_secret_hygiene_scan()
    summary = {
        "suite": "E2E_LIVE_RUST_RC2_MULTI_PROCESS_MATRIX_AND_SECRET_HYGIENE",
        "hooks_and_security_matrix": hook_res,
        "secret_scan": sec_res,
    }
    out_dir = REPO_ROOT / "ARTIFACTS" / "evidence"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "ai_bridge_and_secret_scan.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))

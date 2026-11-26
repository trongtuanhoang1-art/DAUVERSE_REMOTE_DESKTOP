#!/usr/bin/env python3
"""
DAUVERSE REMOTE DESKTOP V1 (RC3) — Multi-Process Live Rust `.so` E2E Security Matrix & Secret Hygiene Scanner
1. Spawns four sequential isolated OS processes loading `target/release/liblibrustdesk.so` via ctypes C-ABI FFI:
   - Phase 1: Initializes runtime, seals Step-Up PIN (`0600`), persists user settings (`F07`), runs official
     `claude_code_hook.py`, `codex_notify_hook.py`, and `dauverse_job_wrapper.ps1` against live loopback HTTP
     AI Event Bridge (`DAUVERSE_AI_EVENT_V3`), and records a signed envelope (`evt-linux-persist-001`).
   - Phase 2 (fresh OS process on same `DAUVERSE_DATA_DIR`): Verifies durable settings/notifications reopen (`F07`),
     cross-restart replay rejection (`F09`), lossless `f32:<8hex>` HMAC v3 tamper rejection including IEEE-754
     adjacent neighbor (`0x42c80000` vs `0x42c80001`), schema v1/v2 downgrade rejection, unknown field / missing
     `schema_version` / invalid UTF-8 / truncated `Content-Length` HTTP `400` rejection (`F01`), Step-Up PIN
     overwrite denial + rotation + grant token + 5-strike lockout (`F05`), headless truthfulness (`F04`), honest
     `None` disconnected FPS (`F10`), spoofed publisher downgrade (`F12`), zero-socket dry-run Wake-on-LAN (`F13`),
     per-file `file_specs` SHA-256 + missing-digest + `AAAA->BBBB` + `[4,6]` vs `[2,8]` + symlink rejection
     (`F14`, `F16`), and exact microsecond HMAC benchmark scaling (`N01`).
   - Phase 3 (fresh OS process with corrupted `step_up_pin.vault`): Verifies `SECURITY_VAULT_CORRUPTED_FAIL_CLOSED`
     without silent PIN reset (`F05`, `F07`).
   - Phase 4 (fresh OS process with corrupted `bridge_replay_journal.json`): Verifies fail-closed HTTP `503`
     `EVENT_REJECT_REPLAY_JOURNAL_CORRUPTED_FAIL_CLOSED` (`F09`).
2. Scans all repository files for accidentally leaked credentials/tokens.
"""

import ctypes
import hashlib
import hmac
import json
import math
import os
import re
import shutil
import socket
import stat
import struct
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


def canonical_f32_tag(value: float, lo: float, hi: float) -> str:
    packed = struct.pack(">f", float(value))
    f32_val = struct.unpack(">f", packed)[0]
    bits = struct.unpack(">I", packed)[0]
    if not math.isfinite(f32_val) or f32_val < lo or f32_val > hi:
        raise ValueError(f"Out-of-range f32: {value}")
    if bits == 0x80000000:
        raise ValueError("EVENT_REJECT_NEGATIVE_ZERO_FLOAT")
    return f"f32:{bits:08x}"


def sign_v3(secret: str, event_obj: dict, issued_at_ms: int, nonce: str) -> str:
    prov = event_obj["provenance"]
    prog = event_obj.get("progress")
    prog_tag = None if prog is None else canonical_f32_tag(prog, 0.0, 100.0)
    conf_tag = canonical_f32_tag(event_obj["confidence"], 0.0, 1.0)
    payload = [
        "DAUVERSE_AI_EVENT_V3",
        3,
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
        prog_tag,
        event_obj["summary"],
        event_obj.get("artifact_reference"),
        conf_tag,
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
        data=json.dumps(obj, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        return e.code, (json.loads(raw) if raw.strip().startswith("{") else {"raw": raw})


def send_raw_http(port: int, raw_bytes: bytes) -> str:
    with socket.create_connection(("127.0.0.1", port), timeout=3.0) as sock:
        sock.sendall(raw_bytes)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks).decode("utf-8", errors="replace")


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
    elif phase == "phase4_corrupt_replay":
        corrupt_rj = data_dir / "isolated_corrupt_replay"
        corrupt_rj.mkdir(parents=True, exist_ok=True)
        (corrupt_rj / "bridge_replay_journal.json").write_bytes(b"{corrupt-replay-journal")
        os.environ["DAUVERSE_DATA_DIR"] = str(corrupt_rj)

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
                "session_id": "claude-live-rc3-01",
                "message": "Completed RC3 lossless f32 HMAC v3 verification",
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
                    "turn-id": "codex-live-rc3-02",
                    "last-assistant-message": "All RC3 findings verified in live FFI",
                }),
            ],
            env=env,
            capture_output=True,
            check=True,
        )

        pwsh_bin = shutil.which("pwsh") or "/home/antigravity/.local/pwsh/pwsh"
        pwsh_wrapper_tested = False
        if Path(pwsh_bin).is_file():
            p3 = subprocess.run(
                [
                    pwsh_bin,
                    "-NoProfile",
                    "-File",
                    str(REPO_ROOT / "scripts/hooks/dauverse_job_wrapper.ps1"),
                    "-ProjectId",
                    "DAUVERSE-REMOTE-V1",
                    "-TaskName",
                    "PS Wrapper V3 Check",
                    "-JobKind",
                    "QA",
                    "-CommandToRun",
                    "Write-Output 'rc3-wrapper-ok'",
                ],
                env=env,
                capture_output=True,
                check=True,
            )
            assert p3.returncode == 0
            snap_after_ps = invoke_rust_ffi(lib, "dashboard_snapshot")
            ps_tasks = [
                ev for ev in snap_after_ps["data"]["ai_summary"]["recent_events"]
                if ev.get("source") == "powershell_job" and ev.get("task_name") == "PS Wrapper V3 Check"
            ]
            assert len(ps_tasks) == 1, f"Expected PowerShell V3 event accepted by Rust bridge, got {snap_after_ps['data']['ai_summary']['recent_events']}"
            pwsh_wrapper_tested = True

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
            "summary": "Hoàn tất kiểm thử Tiếng Việt 🚀",
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
            "schema_version": 3,
            "event": persist_evt,
            "issued_at_ms": now_ms,
            "nonce": "linuxpersist0001",
            "signature_hex": sign_v3(secret, persist_evt, now_ms, "linuxpersist0001"),
        }
        c_code, c_body = post_json(endpoint, persist_env)
        assert c_code == 200, f"Expected 200 on persist_env, got {c_code}: {c_body}"
        (data_dir / "saved_persist_envelope.json").write_text(
            json.dumps(persist_env, ensure_ascii=False), encoding="utf-8"
        )

        return {
            "phase1": "PASS",
            "bridge_port": port,
            "claude_exit": p1.returncode,
            "codex_exit": p2.returncode,
            "pwsh_wrapper_tested": pwsh_wrapper_tested,
            "vault_mode_octal": oct(mode),
        }

    if phase == "phase2":
        snap_resp = invoke_rust_ffi(lib, "dashboard_snapshot")
        assert snap_resp.get("ok") is True, f"Phase 2 snapshot failed: {snap_resp}"
        d = snap_resp["data"]
        endpoint = d["bridge_endpoint"]
        port = int(d["bridge_port"])

        assert d["performance"]["active_mode"] == "HIGH_QUALITY", f"F07 settings lost: {d['performance']}"
        assert d["clipboard"]["policy"]["allow_files"] is False, f"F07 clipboard lost: {d['clipboard']}"
        assert d["transfer_queue"]["bandwidth_limit_kbps"] == 4096, f"F07 bandwidth lost: {d['transfer_queue']}"
        assert d["notifications"]["unread_count"] >= 4, f"F07 notifications lost: {d['notifications']}"

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

        saved_env = json.loads((data_dir / "saved_persist_envelope.json").read_text(encoding="utf-8"))
        replay_code, _ = post_json(endpoint, saved_env)
        assert replay_code == 401, f"F09 cross-restart replay not rejected: {replay_code}"

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
        valid_sig = sign_v3(secret, base_evt, now_ms, "f01e2enonce00001")
        neighbor_f32 = struct.unpack(">f", bytes.fromhex("42c80001"))[0]
        conf_neighbor_f32 = struct.unpack(">f", bytes.fromhex("3f7fffff"))[0]
        mutations = [
            ("task_name", lambda e: e.update({"task_name": "Tampered"})),
            ("summary", lambda e: e.update({"summary": "Tampered summary"})),
            ("severity", lambda e: e.update({"severity": "CRITICAL"})),
            ("progress", lambda e: e.update({"progress": 5.0})),
            ("progress_f32_neighbor_42c80001", lambda e: e.update({"progress": neighbor_f32})),
            ("confidence_f32_neighbor_3f7fffff", lambda e: e.update({"confidence": conf_neighbor_f32})),
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
                    "schema_version": 3,
                    "event": cloned,
                    "issued_at_ms": now_ms,
                    "nonce": "f01e2enonce00001",
                    "signature_hex": valid_sig,
                },
            )
            assert m_code == 401, f"F01 mutation '{fname}' accepted! HTTP {m_code}"
            rejected_fields.append(fname)

        for old_ver in (1, 2):
            old_code, _ = post_json(
                endpoint,
                {
                    "schema_version": old_ver,
                    "event": base_evt,
                    "issued_at_ms": now_ms,
                    "nonce": f"oldvere2e000000{old_ver}",
                    "signature_hex": valid_sig,
                },
            )
            assert old_code == 401, f"Schema v{old_ver} was not rejected: {old_code}"

        missing_ver_code, _ = post_json(
            endpoint,
            {
                "event": base_evt,
                "issued_at_ms": now_ms,
                "nonce": "missingvere2e001",
                "signature_hex": valid_sig,
            },
        )
        assert missing_ver_code == 400, f"Missing schema_version must return 400, got {missing_ver_code}"

        unknown_field_code, _ = post_json(
            endpoint,
            {
                "schema_version": 3,
                "event": base_evt,
                "issued_at_ms": now_ms,
                "nonce": "unknownfielde2e1",
                "signature_hex": valid_sig,
                "smuggled_extra": "forbidden",
            },
        )
        assert unknown_field_code == 400, f"Unknown field must return 400, got {unknown_field_code}"

        neg_zero_evt = json.loads(json.dumps(base_evt))
        neg_zero_evt["event_id"] = "evt-neg-zero-wire"
        neg_zero_evt["progress"] = 0.0
        pos_zero_sig = sign_v3(secret, neg_zero_evt, now_ms, "negzerowire00001")
        neg_zero_wire_json = json.dumps(
            {
                "schema_version": 3,
                "event": neg_zero_evt,
                "issued_at_ms": now_ms,
                "nonce": "negzerowire00001",
                "signature_hex": pos_zero_sig,
            }
        ).replace('"progress": 0.0', '"progress": -0.0')
        neg_zero_bytes = neg_zero_wire_json.encode("utf-8")
        neg_zero_http_resp = send_raw_http(
            port,
            f"POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: {len(neg_zero_bytes)}\r\n\r\n".encode("ascii")
            + neg_zero_bytes,
        )
        assert neg_zero_http_resp.startswith("HTTP/1.1 401"), f"Negative zero -0.0 wire payload must return 401: {neg_zero_http_resp}"

        bad_utf8_resp = send_raw_http(
            port,
            b"POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 4\r\n\r\n\xff\xfe\xfd\xfc",
        )
        assert bad_utf8_resp.startswith("HTTP/1.1 400"), f"Invalid UTF-8 body must return 400: {bad_utf8_resp}"

        trunc_http_resp = send_raw_http(
            port,
            b"POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 200\r\n\r\n{\"short\":1}",
        )
        assert trunc_http_resp.startswith("HTTP/1.1 400"), f"Truncated body must return 400: {trunc_http_resp}"

        untrusted_evt = json.loads(json.dumps(base_evt))
        untrusted_evt["event_id"] = "evt-untrusted-desktop"
        untrusted_evt["source"] = "claude_desktop"
        untrusted_code, _ = post_json(
            endpoint,
            {
                "schema_version": 3,
                "event": untrusted_evt,
                "issued_at_ms": now_ms,
                "nonce": "untrustede2e0001",
                "signature_hex": sign_v3(secret, untrusted_evt, now_ms, "untrustede2e0001"),
            },
        )
        assert untrusted_code == 401, f"Untrusted source claiming OFFICIAL_HOOK was not rejected: {untrusted_code}"

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

        perf = invoke_rust_ffi(lib, "dashboard_snapshot")["data"]["performance"]
        assert perf.get("measured_fps") is None and "fps" not in perf, f"F10 synthetic fps leaked: {perf}"
        assert perf["configured_target_fps"] > 0

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
                    "release_notes_vi": "RC3 test descriptor",
                },
            },
        )
        assert upd["ok"] is True and upd["data"]["safe_for_auto_update"] is False, f"F12 failed: {upd}"
        assert upd["data"]["signature_status"] in ("UNSIGNED_BUILD", "UNVERIFIED_PUBLISHER"), f"F12 status: {upd}"

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

        # F14 & F16: Per-file sender SHA-256 + byte size + missing digest + compensating length + symlink defense
        rx_root = data_dir / "rx_confined"
        rx_root.mkdir(parents=True, exist_ok=True)
        f_a = rx_root / "a.bin"
        f_b = rx_root / "b.bin"
        f_a.write_bytes(b"AAAA")
        f_b.write_bytes(b"CCCCCC")

        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 801,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "file_specs": [
                    {
                        "relative_path": "a.bin",
                        "expected_bytes": 4,
                        "expected_sha256": hashlib.sha256(b"AAAA").hexdigest(),
                    },
                    {
                        "relative_path": "b.bin",
                        "expected_bytes": 6,
                        "expected_sha256": hashlib.sha256(b"CCCCCC").hexdigest(),
                    },
                ],
                "total_bytes": 10,
            },
        )["ok"] is True
        fin_ok = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 801})
        assert fin_ok["ok"] is True and fin_ok["data"]["integrity_state"] == "SENDER_SHA256_VERIFIED", f"F16 valid finalize failed: {fin_ok}"
        assert fin_ok["data"].get("verified_sha256")

        # F16 Negative A: Missing sender SHA-256 (legacy `files` only) MUST fail closed
        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 802,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "files": ["a.bin"],
                "total_bytes": 4,
            },
        )["ok"] is True
        fin_missing_sha = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 802})
        assert fin_missing_sha["ok"] is False and "MISSING_SENDER_SHA256" in fin_missing_sha.get("error", ""), f"F16 missing sha accepted: {fin_missing_sha}"

        # F16 Negative B: Same-size content mutation (AAAA -> BBBB) MUST fail closed
        f_a.write_bytes(b"BBBB")
        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 803,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "file_specs": [
                    {
                        "relative_path": "a.bin",
                        "expected_bytes": 4,
                        "expected_sha256": hashlib.sha256(b"AAAA").hexdigest(),
                    }
                ],
                "total_bytes": 4,
            },
        )["ok"] is True
        fin_mut = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 803})
        assert fin_mut["ok"] is False and "SHA256_MISMATCH" in fin_mut.get("error", ""), f"F16 content mutation accepted: {fin_mut}"

        # F16 Negative C: Compensating multi-file lengths ([2, 8] == 10 vs [4, 6] == 10) MUST fail closed
        (rx_root / "c1.bin").write_bytes(b"12")
        (rx_root / "c2.bin").write_bytes(b"12345678")
        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 804,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "file_specs": [
                    {
                        "relative_path": "c1.bin",
                        "expected_bytes": 4,
                        "expected_sha256": hashlib.sha256(b"1234").hexdigest(),
                    },
                    {
                        "relative_path": "c2.bin",
                        "expected_bytes": 6,
                        "expected_sha256": hashlib.sha256(b"123456").hexdigest(),
                    },
                ],
                "total_bytes": 10,
            },
        )["ok"] is True
        fin_comp = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 804})
        assert fin_comp["ok"] is False and "FILE_BYTE_SIZE_MISMATCH" in fin_comp.get("error", ""), f"F16 compensating size accepted: {fin_comp}"

        # F14 Negative: Symlink escape rejected
        outside_secret = data_dir / "outside_target.txt"
        outside_secret.write_bytes(b"TOP_SECRET")
        sym_escape = rx_root / "symlink_escape.txt"
        sym_escape.symlink_to(outside_secret)
        assert invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 805,
                "conn_id": 1,
                "dest_dir": str(rx_root),
                "file_specs": [
                    {
                        "relative_path": "symlink_escape.txt",
                        "expected_bytes": 10,
                        "expected_sha256": hashlib.sha256(b"TOP_SECRET").hexdigest(),
                    }
                ],
                "total_bytes": 10,
            },
        )["ok"] is True
        fin_sym = invoke_rust_ffi(lib, "transfer_finalize_receive", {"engine_job_id": 805})
        assert fin_sym["ok"] is False, f"F14 symlink escape was not rejected: {fin_sym}"

        # FT010-B05 Live C-ABI E2E: Shared conn_id=0 rejection + concurrent same engine_job_id (1) across Peer A (corrupt) and Peer B (valid)
        conn0_reject = invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 1,
                "conn_id": 0,
                "dest_dir": str(rx_root),
                "files": ["a.bin"],
                "total_bytes": 4,
            },
        )
        assert conn0_reject["ok"] is False and "INTEGRITY_INVALID_IDENTITY" in conn0_reject.get("error", ""), (
            f"FT010-B05 conn_id=0 was not rejected: {conn0_reject}"
        )

        peer_a_dir = data_dir / "rx_peer_a_conn10"
        peer_b_dir = data_dir / "rx_peer_b_conn11"
        peer_a_dir.mkdir(parents=True, exist_ok=True)
        peer_b_dir.mkdir(parents=True, exist_ok=True)
        (peer_a_dir / "shared.bin").write_bytes(b"CORRUPT_10")
        (peer_b_dir / "shared.bin").write_bytes(b"VALID_B_11")

        track_a = invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 1,
                "conn_id": 10,
                "dest_dir": str(peer_a_dir),
                "file_specs": [
                    {
                        "relative_path": "shared.bin",
                        "expected_bytes": 10,
                        "expected_sha256": hashlib.sha256(b"EXPECTED_A").hexdigest(),
                    }
                ],
                "total_bytes": 10,
            },
        )
        assert track_a["ok"] is True, f"FT010-B05 track_a failed: {track_a}"

        track_b = invoke_rust_ffi(
            lib,
            "transfer_track_receive",
            {
                "engine_job_id": 1,
                "conn_id": 11,
                "dest_dir": str(peer_b_dir),
                "file_specs": [
                    {
                        "relative_path": "shared.bin",
                        "expected_bytes": 10,
                        "expected_sha256": hashlib.sha256(b"VALID_B_11").hexdigest(),
                    }
                ],
                "total_bytes": 10,
            },
        )
        assert track_b["ok"] is True, f"FT010-B05 track_b failed: {track_b}"

        fin_peer_a = invoke_rust_ffi(
            lib, "transfer_finalize_receive", {"engine_job_id": 1, "conn_id": 10}
        )
        assert fin_peer_a["ok"] is False and "INTEGRITY_SHA256_MISMATCH" in fin_peer_a.get("error", ""), (
            f"FT010-B05 corrupt peer A passed after peer B reused engine_job_id 1: {fin_peer_a}"
        )

        fin_peer_b = invoke_rust_ffi(
            lib, "transfer_finalize_receive", {"engine_job_id": 1, "conn_id": 11}
        )
        assert (
            fin_peer_b["ok"] is True
            and fin_peer_b["data"]["integrity_state"] == "SENDER_SHA256_VERIFIED"
            and fin_peer_b["data"]["dest_root_dir"] == str(peer_b_dir)
        ), f"FT010-B05 valid peer B failed: {fin_peer_b}"

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
        bench_data = bench_resp["data"]
        assert str(bench_data.get("benchmark_scope", "")).startswith("LOCAL_PIPELINE_MICROBENCHMARK_ONLY")
        assert bench_data["hmac_iterations"] == 200
        assert abs(bench_data["hmac_event_sign_us"] * 200.0 - bench_data["hmac_total_elapsed_us"]) <= 0.15, f"N01 scaling mismatch: {bench_data}"

        out_dir = REPO_ROOT / "ARTIFACTS" / "evidence"
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "release_ffi_smoke_test.json").write_text(json.dumps(after_resp, indent=2), encoding="utf-8")
        (out_dir / "benchmark_results.json").write_text(json.dumps(bench_data, indent=2), encoding="utf-8")

        return {
            "phase2": "PASS",
            "settings_reopen_verified": True,
            "cross_restart_replay_rejected_http": replay_code,
            "f01_mutated_fields_rejected": rejected_fields,
            "schema_v1_v2_downgrade_rejected": True,
            "missing_schema_and_unknown_field_rejected_http_400": True,
            "invalid_utf8_and_truncated_body_rejected_http_400": True,
            "untrusted_source_rejected_http": untrusted_code,
            "step_up_pin_overwrite_blocked": True,
            "step_up_pin_rotation_and_lockout_verified": True,
            "headless_denied_stays_inactive": True,
            "disconnected_measured_fps_is_none": True,
            "spoofed_unsigned_auto_update_blocked": True,
            "wol_dry_run_zero_side_effect": True,
            "f16_per_file_sha256_and_negative_suite_verified": True,
            "n01_hmac_microsecond_scale_verified": True,
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

    if phase == "phase4_corrupt_replay":
        snap = invoke_rust_ffi(lib, "dashboard_snapshot")["data"]
        assert snap["storage_healthy"] is False, f"Expected storage_healthy False on corrupt replay journal: {snap}"
        assert snap["ai_summary"]["replay_journal_healthy"] is False
        endpoint = snap["bridge_endpoint"]
        now_ms = int(time.time() * 1000)
        evt = {
            "event_id": "evt-corrupt-rj-probe",
            "timestamp": "2026-11-25T15:05:00Z",
            "source": "codex_cli",
            "device_id": "HOME-RTX3060",
            "project_id": "DAUVERSE-REMOTE-V1",
            "task_id": "rj-probe",
            "task_name": "Replay Fail Closed Probe",
            "event_type": "TASK_COMPLETED",
            "status": "COMPLETED",
            "severity": "SUCCESS",
            "progress": 100.0,
            "summary": "Must be rejected 503 when replay journal is corrupt",
            "artifact_reference": None,
            "confidence": 1.0,
            "provenance": {
                "adapter_type": "OFFICIAL_HOOK",
                "evidence_verified": True,
                "exit_code": 0,
                "evidence_badge": "EXIT_0",
            },
        }
        code, body = post_json(
            endpoint,
            {
                "schema_version": 3,
                "event": evt,
                "issued_at_ms": now_ms,
                "nonce": "corruptrjnonce01",
                "signature_hex": sign_v3(secret, evt, now_ms, "corruptrjnonce01"),
            },
        )
        assert code == 503 and "CORRUPTED_FAIL_CLOSED" in json.dumps(body), f"Expected 503 fail-closed, got {code}: {body}"
        return {"phase4_corrupt_replay_journal_fail_closed_http": code}

    raise ValueError(f"Unknown phase: {phase}")


def run_live_rust_hook_e2e_test() -> dict:
    secret = "dauverse-e2e-live-rust-secret-key-2026-verified"
    tmp_dir = Path(tempfile.mkdtemp(prefix="dauverse_e2e_rc3_"))
    try:
        results = {}
        for phase in ("phase1", "phase2", "phase3_corrupt", "phase4_corrupt_replay"):
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
        "suite": "E2E_LIVE_RUST_RC3_MULTI_PROCESS_MATRIX_AND_SECRET_HYGIENE",
        "hooks_and_security_matrix": hook_res,
        "secret_scan": sec_res,
    }
    out_dir = REPO_ROOT / "ARTIFACTS" / "evidence"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "ai_bridge_and_secret_scan.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))

# INDEPENDENT QA HANDOFF SPECIFICATION — CODEX QA & EXTERNAL NEON REVIEWER
## DAUVERSE REMOTE DESKTOP V1.0 (`DREMOTE-V1-RC1-NEXT-002`)

- **Target Independent Reviewers:** `CODEX` (Final Independent QA) & Separate `NEON HIGH/EXTRA` Session (per `MODEL_ROUTING_UNSUPPORTED` in-VM subagent disclosure)
- **Primary Developer & Remediator:** `ANTIGRAVITY REMOTE AGENT` (`Carbon High`)
- **Final Approver:** `BOSS`
- **Development Branch:** `develop/dauverse-remote-v1`
- **Preserved Immutable RC1 Tag:** `rc1-baseline-35027150` (`35027150fcc497ade9145fcb4ea5cbc625035630`)

---

## 1. QA Independence & Read-Only Rules

1. Independent reviewers (`Neon` / `Codex`) operate **strictly read-only** against the remediated branch (`develop/dauverse-remote-v1`), QA archive (`DAUVERSE_REMOTE_DESKTOP_V1_RC1_REMEDIATED_QA.zip`), and Git bundle (`DAUVERSE_REMOTE_DESKTOP_V1_RC1_REMEDIATED.bundle`).
2. Developer self-test logs in `ARTIFACTS/evidence/` are reproducible verification outputs and **do not** substitute for independent `Codex` QA sign-off.
3. Antigravity **never** declares `Production Approved`.

---

## 2. Reproducible Verification Commands (Zero Exit-Code Masking)

### A. Verify SHA-256 Manifest, JSON Schemas & AGPL-3.0 License Parity
```bash
set -euo pipefail
sha256sum -c ARTIFACTS/SHA256_MANIFEST.txt
python3 -m json.tool UPSTREAM_MANIFEST.json > /dev/null
python3 -m json.tool SBOM.spdx.json > /dev/null
diff -u LICENCE LICENSE
```

### B. Verify Rust Core, Engine Hooks & Negative Security Suite (`21/21` + Upstream Crates)
```bash
set -euo pipefail
export PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cargo test --locked --features linux-pkg-config --lib dauverse:: -- --nocapture
cargo test --locked -p base -p enigo -p clipboard --features clipboard/unix-file-copy-paste
```

### C. Verify Live Compiled `liblibrustdesk.so` Loopback `:21188` AI Bridge, Forged-HMAC `HTTP 401` & Secret Scan
```bash
set -euo pipefail
export PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cargo build --locked --features flutter,linux-pkg-config --lib --release
python3 TESTS/test_e2e_hooks_and_secrets.py
```

### D. Verify Full Flutter Suite (`187 PASS, 0 FAIL, 1 Web-Only Skip`)
```bash
set -euo pipefail
(cd flutter && flutter test --reporter expanded)
```

### E. Verify Windows Native Release Build (On Authorized Windows 10/11 Runner or GitHub Actions `windows-2022`)
```powershell
.\scripts\windows\build_windows_release.ps1 -WorkspaceRoot "E:\DAUVERSE_REMOTE_DESKTOP"
```

---

## 3. Mandatory Audit Checkpoints for `Codex` Independent QA

1. **Real Engine Integration (`flutter/lib/dauverse/` + `src/clipboard.rs` + `src/ui_cm_interface.rs`):**
   - Confirm Quick Connect & My Devices invoke `connect(ctx, peerId)` and File Transfer invokes `connect(ctx, peerId, isFileTransfer: true)` (`RemotePage` / `FileManagerPage`).
   - Confirm `clipboard_guard` is enforced inside `src/clipboard.rs` (`read_clipboard_message` & `do_update_clipboard_`) and `transfer_guard::validate_and_resolve_destination` is enforced inside `src/ui_cm_interface.rs` (`ipc::FS::NewWrite`).
   - Confirm zero hardcoded fake Peer IDs (`892 441 109`), fake `14 ms` telemetry, fake file queue items, or fake seeded AI tasks exist.
2. **Benchmark Honesty (`src/dauverse/performance.rs` & `FEATURE_ACCEPTANCE_MATRIX.md`):**
   - Confirm `benchmark_scope == "LOCAL_PIPELINE_MICROBENCHMARK_ONLY"` and neither loopback RTT nor dirty-frame scan is claimed as end-to-end 2-PC Remote Desktop latency.
3. **AI Bridge & Notification Security (`src/dauverse/ai_bridge.rs` & `notifications.rs`):**
   - Confirm `127.0.0.1:21188` enforces constant-time HMAC-SHA256 (`HTTP 401` on forged signature), `±300s` replay window, exit-code-only `ProcessExited(0)` -> `Unknown` (never fake `Completed`), and `attempt_ai_approval_via_notification` unconditionally returns `Err`.
4. **Driver Signature & Smart Plug Compliance (`Sections 6 & 7`):**
   - Confirm `RustDeskIddDriver v0.4` (`WDKTestCert` SHA-1) is hard-blocked in `src/dauverse/headless.rs`, WHQL `usbmmidd_v2` has Amyuni attribution in `THIRD_PARTY_NOTICES` and requires explicit Boss approval, and `DisabledSmartPlugAdapter` remains active for `Hunonic SK02` (`BLOCKED`, zero undocumented API or credential extraction).
5. **Windows DPAPI, NSIS & CI Hardening (`Sections 5 & 7`):**
   - Confirm `Cargo.toml` includes `winapi` features `"dpapi"` and `"winbase"`, `dauverse_setup.nsi` enforces `DRIVE_FIXED` and `"RustDesk"` SCM alignment without auto-installing service/driver, and `.github/workflows/dauverse-windows-build.yml` uses SHA-pinned actions with `permissions: contents: read` and `workflow_dispatch` only.

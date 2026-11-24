# INDEPENDENT QA HANDOFF SPECIFICATION — CODEX QA
## DAUVERSE REMOTE DESKTOP V1.0 (`DREMOTE-V1-MASTER-001`)

**Target Reviewer:** `CODEX` (Independent Read-Only QA)  
**Primary Developer:** `ANTIGRAVITY REMOTE AGENT`  
**Final Approver:** `BOSS`  
**Development Branch:** `develop/dauverse-remote-v1`

---

## 1. QA Independence & Read-Only Rules (Section 31)

1. Codex QA operates **strictly read-only** against the release candidate branch (`develop/dauverse-remote-v1`), QA archive (`DAUVERSE_REMOTE_DESKTOP_V1_RC1_QA.zip`), and evidence bundle (`ARTIFACTS/`).
2. Developer self-test logs in `ARTIFACTS/evidence/` are provided as reproducible baseline evidence and **do not** substitute for Codex's independent verification.
3. Antigravity does **not** self-certify Independent QA `PASS`; final sign-off rests exclusively with Codex QA review followed by Boss approval.

---

## 2. Reproducible Verification Commands for Codex QA

### A. Verify Integrity & Compliance Artifacts
```bash
sha256sum -c ARTIFACTS/SHA256_MANIFEST.txt
python3 -m json.tool UPSTREAM_MANIFEST.json > /dev/null
python3 -m json.tool SBOM.spdx.json > /dev/null
diff -u LICENCE LICENSE
```

### B. Verify Rust Core, Loopback Gateways, Benchmarks & 16-Category Negative Security Suite
```bash
export PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cargo test --locked --features linux-pkg-config --lib dauverse:: -- --nocapture
cargo test --locked -p base -p enigo -p clipboard --features clipboard/unix-file-copy-paste
```

### C. Verify Flutter 16-Screen Executive UI, Localization (VI/EN) & Dark/Light Modes
```bash
cd flutter
flutter test test/dauverse_ui_test.dart
```

### D. Verify Windows Native Packaging (On Authorized Windows 10/11 Runner)
```powershell
.\scripts\windows\build_windows_release.ps1 -WorkspaceRoot "E:\DAUVERSE_REMOTE_DESKTOP"
```

---

## 3. Mandatory Security & Truthfulness Audit Points for Codex

1. **No Fake AI Completion (`src/dauverse/ai_bridge.rs`):** Confirm `AiEventType::ProcessExited` with `exit_code == Some(0)` and `evidence_verified == false` normalizes to `AiTaskStatus::Unknown`, never `Completed`, and clears unverified `progress` / `evidence_badge`.
2. **Event Anti-Spoofing & Anti-Replay (`src/dauverse/ai_bridge.rs`):** Confirm `ingest_signed_envelope` enforces constant-time HMAC-SHA256 (`constant_time_eq`), `±300s` clock window, and replay cache rejection.
3. **No Notification Auto-Approval (`src/dauverse/notifications.rs`):** Confirm `attempt_ai_approval_via_notification` unconditionally returns `Err("SECURITY_POLICY_VIOLATION...")`.
4. **Path Traversal, Symlink & Reparse Defense (`src/dauverse/transfer_guard.rs`):** Confirm `validate_and_resolve_destination` rejects `..`, UNC/drive paths, Windows reserved names (`CON`, `NUL`, `COM1..9`), symlinks, and `#[cfg(windows)]` `FILE_ATTRIBUTE_REPARSE_POINT`.
5. **Smart Power Safety Interlocks (`src/dauverse/smart_power.rs`):** Confirm `SmartPlugPowerOff` is hard-blocked when `host_state` is `Online`, `NetworkUnreachable`, or `Unknown`, and `DisabledSmartPlugAdapter` reports `BLOCKED` honestly.
6. **Device Shield & Audit Chain (`src/dauverse/security.rs`):** Confirm allowlist enforcement, brute-force lockout, TLS channel-binding anti-hijack check, DPAPI `CryptProtectData` on Windows, and `verify_audit_chain()`.
7. **Secret Hygiene:** Confirm zero secrets, tokens, or personal data exist anywhere in Git commits or tracked files.

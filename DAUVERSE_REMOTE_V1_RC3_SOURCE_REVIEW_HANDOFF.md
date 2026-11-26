# DAUVERSE REMOTE DESKTOP V1 — RC3 SOURCE REVIEW HANDOFF

- **Task ID:** `DREMOTE-V1-REMEDIATION-007` (`RC3 CONSOLIDATED REMEDIATION — SOURCE FIRST`)
- **Developer:** `ANTIGRAVITY CLOUD`
- **Independent Reviewer:** `CODEX`
- **Strategy Gate:** `SOURCE FIRST — INDEPENDENT REVIEW BEFORE WINDOWS BUILD`
- **Windows CI / Native Build Triggered for RC3:** `NONE (0 runs — strictly gated on Codex Source Review + Boss Approval)`
- **Production Status:** `LOCKED`
- **Final Handoff Status:** `READY_FOR_CODEX_SOURCE_REVIEW`

---

## 1. Baseline & Candidate Provenance

| Field | Value |
|---|---|
| **Repository** | `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP` |
| **Development Branch** | `develop/dauverse-remote-v1` (pushed without `--force`; `main`/`master` untouched; zero tags/releases created) |
| **RC2 Baseline Commit** | `0e1e3e87185159a481360b2c2b28f3dee541328f` |
| **RC2 Baseline Windows CI Run** | `45720572543` (artifacts preserved untouched at `/home/antigravity/RC2_FINAL_HANDOFF_45720572543/`) |
| **Upstream Submodule (`libs/hbb_common`)** | `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb` (untouched; zero submodule drift) |
| **Lockfiles (`Cargo.lock`, `flutter/pubspec.lock`)** | Untouched (`0` lines changed; zero new external crates or Dart packages added) |
| **Codex RC1 QA Report (`QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md`)** | `f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913` (**VERIFIED EXACT**) |
| **Codex RC2 Re-QA Report (`QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md`)** | `c23d36e7d83b2fb1402238d8a8501b9de899fcd94b2774155b6a602fd77fb954` (**VERIFIED EXACT**) |
| **RC3 Source Candidate Commit** | Head commit of `develop/dauverse-remote-v1` (`git rev-parse HEAD`; exact commit SHA-1 and bundle/diff digests are also recorded in external `RC3_COMMIT_PROVENANCE.json` and `SOURCE_SHA256_MANIFEST.txt` inside `DAUVERSE_REMOTE_DESKTOP_V1_RC3_SOURCE_REVIEW_PACKAGE.zip`, since a tracked file inside a Git commit cannot self-embed that commit's SHA-1) |

---

## 2. Full Diff Overview & Mandatory Regression-Surface Report

### 2.1 Diff Scope (`0e1e3e87185159a481360b2c2b28f3dee541328f..HEAD`)
The verbatim binary-safe patch is packaged at `RC2_TO_RC3_FULL.diff` inside `DAUVERSE_REMOTE_DESKTOP_V1_RC3_SOURCE_REVIEW_PACKAGE.zip` and reproducible directly via:
```bash
git diff --binary 0e1e3e87185159a481360b2c2b28f3dee541328f..HEAD
```

Modified / added files across the consolidated RC3 candidate:
- **Rust DAUVERSE Modules (`src/dauverse/`):** `ai_bridge.rs`, `crypto_util.rs`, `ffi.rs`, `mod.rs`, `notifications.rs`, `performance.rs`, `security.rs`, `service_ctrl.rs`, `transfer_guard.rs`
- **Rust File-Transfer Plumbing (`libs/base/`, `src/`):** `libs/base/protos/message.proto`, `libs/base/src/fs.rs`, `libs/base/src/fs/download.rs`, `libs/base/src/fs/download_tests.rs`, `src/ipc.rs`, `src/server/connection.rs`, `src/ui_cm_interface.rs`, `src/client/io_loop.rs`
- **Flutter UI Bridge & Widget Tests (`flutter/`):** `flutter/lib/dauverse/bridge/dauverse_bridge.dart`, `flutter/test/dauverse_ui_test.dart`
- **Hooks, Installer Helper, Rollback & Windows RC Verification (`scripts/`, `installer/`, `.github/`):** `scripts/hooks/claude_code_hook.py`, `scripts/hooks/codex_notify_hook.py`, `scripts/hooks/dauverse_job_wrapper.ps1`, `installer/nsis/dauverse_setup_helper.ps1`, `scripts/windows/build_windows_release.ps1`, `scripts/windows/rollback_windows_release.ps1`, `scripts/windows/verify_and_package_windows_rc.ps1`, `scripts/windows/package_complete_rc2_qa_archive.ps1`, `.github/workflows/dauverse-windows-build.yml`
- **QA Reports, Matrices, Tests & Regenerated Linux Evidence:** `QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md`, `DAUVERSE_REMOTE_V1_RC3_SOURCE_REVIEW_HANDOFF.md`, `FEATURE_ACCEPTANCE_MATRIX.md`, `FINDINGS_REMEDIATION_MATRIX.md`, `TESTS/test_e2e_hooks_and_secrets.py`, `TESTS/test_rc3_powershell_validators.py`, `ARTIFACTS/evidence/*`, `SHA256_MANIFEST.txt`, `ARTIFACTS/SHA256_MANIFEST.txt`

### 2.2 Mandatory Regression-Surface Report (`AGENTS.md`)
Every modified existing file outside `src/dauverse/` was audited for necessity and legacy-path preservation:

1. **`libs/base/protos/message.proto` (`FileEntry.sha256`):** Additive protobuf string field (`string sha256 = 6;`). Wire-compatible with protobuf3 defaults (`""` when absent on non-generic internal structs); strictly required by `F16` so sender-computed per-file SHA-256 digests travel inside `SendFiles` / `FileDirectory`.
2. **`libs/base/src/fs.rs` & `libs/base/src/fs/download.rs`:**
   - `TransferJob::new_read` computes `(sha256, exact_size)` only when `r#type == JobType::Generic && !is_android_doc` (leaving printer jobs, memory cursors, and Android document URIs untouched).
   - `TransferJob::read` tracks streaming SHA-256 across chunks (or verifies full-file SHA-256 on non-zero resume offset) when `!entry.sha256.is_empty()` and returns `Err` before `FileTransferDone` if sender bytes mutate mid-stream.
   - `TransferJob::modify_time` and `TransferJob::finish_download` verify `.download` staging byte length + SHA-256 before `std::fs::rename` whenever `!entry.sha256.is_empty()`.
   - `validate_no_symlink_components`, `capture_confined_transfer_root`, `verify_windows_raw_handle_confined`, and `create_download_file_no_follow` enforce NTFS junction (`FILE_ATTRIBUTE_REPARSE_POINT`) and pre-captured canonical transfer-root handle confinement (`F14`).
3. **`src/ipc.rs` (`ipc::FS::NewWrite`):** Carries `(String, u64, u64, String)` (`name, size, modified_time, sha256`) from `src/server/connection.rs` to `src/ui_cm_interface.rs`. Internal IPC enum between server connection and CM process in the same binary version; unavoidable for `F16` upload verification.
4. **`src/server/connection.rs`:** Forwards `f.sha256.clone()` into `ipc::FS::NewWrite` and wraps synchronous `TransferJob::new_read` in `tokio::task::spawn_blocking` inside `async fn` per `AGENTS.md` Tokio rules so multi-GB file hashing cannot stall async session I/O.
5. **`src/ui_cm_interface.rs` & `src/client/io_loop.rs`:**
   - Wrap synchronous `TransferJob::new_read` in `tokio::task::spawn_blocking`.
   - Register per-file `(relative_path, expected_bytes, expected_sha256)` via `resolve_transfer_manifest_root_and_specs` on non-empty generic transfers, rejecting missing/malformed sender digests before any `.download` file is created or renamed.
   - Preserve empty-directory transfers (`job.files().is_empty() && total_size == 0`) with symlink/reparse root checks, and preserve user-skipped uploads (`job.job_skipped()`) without raising false tamper errors.
6. **`flutter/lib/dauverse/bridge/dauverse_bridge.dart`:** Isolates `_testHarnessMode` / `_forceUnboundForTest` behind `const bool.fromEnvironment('dart.vm.product')` + `assert(...)`. Production AOT behavior when `librustdesk.dll` is bound is unchanged; unbound production FFI remains strictly fail-closed.

---

## 3. Consolidated Findings Disposition Matrix (`F01`–`F16` + `N01` + `A01`–`A04`)

> Historical severities from Codex Reports (`6 P1`, `9 P2` + new `N01 P2`, `1 P3`) and acceptance criteria are preserved without downgrade. Items requiring a native Windows runner, 2-PC LAN/WAN + RTX 3060 lab, physical monitorless hardware, code-signing certificate, or real smart-plug approval are explicitly labeled `BLOCKED` / `NOT_TESTED` / `SIMULATED`.

| ID | Sev | RC2 Re-QA Verdict | RC3 Source Remediation Status | Windows / Hardware / Lab Verification Status | Primary Code & Test Locations |
|---|---|---|---|---|---|
| **F01** | **P1** | `OPEN / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for 3-process Windows Sandbox rerun | `src/dauverse/ai_bridge.rs`, `scripts/hooks/claude_code_hook.py`, `scripts/hooks/codex_notify_hook.py`, `scripts/hooks/dauverse_job_wrapper.ps1`, `TESTS/test_e2e_hooks_and_secrets.py`, `TESTS/test_rc3_powershell_validators.py` |
| **F02** | **P1** | `PARTIAL / OPEN` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for native PE/DLL negative injection; `BLOCKED (TWO_HOST_LAB_REQUIRED)` for 2-PC GUI session | `scripts/windows/verify_and_package_windows_rc.ps1`, `TESTS/test_rc3_powershell_validators.py` |
| **F03** | **P1** | `SOURCE FIX VERIFIED / native BLOCKED` | `SOURCE_PRESERVED_AND_VERIFIED` | `BLOCKED (LAB_REQUIRED)` for live running external RustDesk Windows service coexistence | `installer/nsis/dauverse_setup.nsi`, `installer/nsis/dauverse_setup_helper.ps1`, `scripts/windows/rollback_windows_release.ps1`, `src/dauverse/service_ctrl.rs` |
| **F04** | **P1** | `PARTIAL / native BLOCKED` | `SOURCE_PRESERVED_AND_VERIFIED` | `BLOCKED (HARDWARE_AND_BOSS_APPROVAL_GATED)` for physical monitorless IDD activation | `src/dauverse/headless.rs`, `scripts/windows/build_windows_release.ps1` |
| **F05** | **P1** | `SOURCE FIX VERIFIED / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for Windows DPAPI ACL/persistence fault rerun | `src/dauverse/security.rs`, `src/dauverse/crypto_util.rs` |
| **F06** | **P1** | `DEFAULT FAIL-CLOSED / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for native Windows Flutter + `librustdesk.dll` UI integration | `flutter/lib/dauverse/bridge/dauverse_bridge.dart`, `flutter/test/dauverse_ui_test.dart` |
| **F07** | **P2** | `OPEN / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for Windows `%APPDATA%` fault-injection rerun | `src/dauverse/security.rs`, `src/dauverse/notifications.rs`, `src/dauverse/mod.rs` |
| **F08** | **P2** | `OPEN / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for live Windows SCM stop + `HKCU Run` revoke verification | `src/dauverse/service_ctrl.rs`, `src/dauverse/ffi.rs`, `src/dauverse/security.rs` |
| **F09** | **P2** | `OPEN / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for Windows Sandbox corrupted-journal restart check | `src/dauverse/ai_bridge.rs`, `TESTS/test_e2e_hooks_and_secrets.py` (`phase4_corrupt_replay`) |
| **F10** | **P2** | `SCHEMA FIX VERIFIED / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (TWO_HOST_RTX3060_LAB_REQUIRED)` for live 60 FPS / LAN `<35 ms` / NVENC telemetry | `src/dauverse/performance.rs`, `ARTIFACTS/evidence/benchmark_results.json` |
| **F11** | **P2** | `OPEN / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for native PE binary upgrade-then-rollback rerun | `installer/nsis/dauverse_setup_helper.ps1`, `scripts/windows/rollback_windows_release.ps1`, `scripts/windows/verify_and_package_windows_rc.ps1`, `TESTS/test_rc3_powershell_validators.py` |
| **F12** | **P2** | `SOURCE POLICY VERIFIED / PARTIAL` | `SOURCE_PRESERVED_AND_VERIFIED` | `BLOCKED (SIGNING_CERT_UNAVAILABLE)` for Authenticode-signed production artifacts | `src/dauverse/update_center.rs`, `scripts/windows/build_windows_release.ps1` |
| **F13** | **P2** | `SOURCE FIX VERIFIED / NOT_TESTED` | `SOURCE_PRESERVED_AND_VERIFIED` (`SIMULATED` dry-run; `DisabledSmartPlugAdapter`) | `NOT_TESTED (GOVERNANCE_LOCKED)` for real WoL magic packet & Hunonic SK02 relay | `src/dauverse/smart_power.rs` |
| **F14** | **P2** | `OPEN RISK / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for live Windows NTFS `mklink /J`, ADS `:`, and UNC execution | `src/dauverse/crypto_util.rs`, `libs/base/src/fs.rs`, `libs/base/src/fs/download.rs`, `libs/base/src/fs/download_tests.rs` |
| **F15** | **P3** | `SUBSTANTIALLY VERIFIED / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for pinned NSIS `v3.11` & PS 5.1 Windows CI execution | `scripts/windows/build_windows_release.ps1`, `.github/workflows/dauverse-windows-build.yml`, `scripts/windows/package_complete_rc2_qa_archive.ps1`, `TESTS/test_rc3_powershell_validators.py` |
| **F16** | **P2** | `OPEN / PARTIAL` | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED / TWO_HOST_LAB_REQUIRED)` for live 2-peer Windows upload/download | `libs/base/protos/message.proto`, `libs/base/src/fs.rs`, `libs/base/src/fs/download.rs`, `src/ipc.rs`, `src/server/connection.rs`, `src/ui_cm_interface.rs`, `src/client/io_loop.rs`, `src/dauverse/transfer_guard.rs`, `src/dauverse/ffi.rs` |
| **N01** | **P2** | `NEW / OPEN` (`÷10` unit bug) | `SOURCE_REMEDIATED (DEV_LINUX_VERIFIED)` | `BLOCKED (WINDOWS_BUILD_GATED)` for Windows host microbenchmark regeneration | `src/dauverse/performance.rs`, `ARTIFACTS/evidence/benchmark_results.json`, `TESTS/test_e2e_hooks_and_secrets.py` |
| **A01–A04** | **Audit** | Matrix overclaiming & PS 5.1 drift | `REMEDIATED` | Clean-room `git bundle verify` + `git fsck --full --strict` + PS AST parse verified | `FEATURE_ACCEPTANCE_MATRIX.md`, `FINDINGS_REMEDIATION_MATRIX.md`, `DAUVERSE_REMOTE_V1_RC3_SOURCE_REVIEW_HANDOFF.md` |

---

## 4. Root Cause Analysis

### Architectural Root Causes Identified Across RC2
Rather than patching symptoms individually, root-cause analysis identified four shared architectural anti-patterns across RC2 and eliminated them systematically:

1. **Lossy / One-Way Boundary Projections (`F01`, `F11`, `F02`, `F16`):**
   - `F01` rounded `f32` values into `(val * 10000.0).round() as i64` buckets, collapsing distinct IEEE-754 `f32` values (`100.0` = `0x42c80000` vs `100.00001` = `0x42c80001`, `NaN`, `-0.0`) into identical HMAC preimages, while allowing unknown JSON fields and defaulted `schema_version`.
   - `F11` and `F02` validated `manifest -> disk` without checking `disk -> manifest`, allowing unlisted files in a backup or release directory to evade manifest verification and be copied wholesale via `Copy-Item -Recurse` into `$InstallDir`.
   - `F16` recorded file names and aggregate `total_bytes` without sender-computed per-file SHA-256 digests, allowing `finalize_and_verify` / `verify_and_finalize_engine_receive` to mark jobs `Completed` when `expected_sha256` was `None`, and allowing compensating multi-file lengths (`[4, 6]` vs `[2, 8]`) or same-size byte mutations (`AAAA` -> `BBBB`) to pass.
2. **Error-Swallowing Fallbacks Turning Faults into Empty State (`F09`, `F07`, `F05`):**
   - `ai_bridge.rs` (`if let Ok(raw) = fs::read_to_string(path)`), `security.rs`, and `notifications.rs` conflated `ErrorKind::NotFound` (legitimate first boot) with permission/stat/I/O/corruption errors, starting with an empty replay cache or ignoring `persist_security_state()` failures during PIN lockout/verification.
3. **String-Prefix vs. OS Handle/Segment Confinement (`F14`):**
   - `crypto_util.rs` and `libs/base/src/fs.rs` used string `starts_with` without trailing separator boundaries (`E:\QA\allowed_evil` matched `E:\QA\allowed`), misparsed Windows verbatim drive prefixes (`\\?\E:\...` vs `\\`), ignored `GetFinalPathNameByHandleW` `len == 0` / `>1024` buffer growth, missed `FILE_ATTRIBUTE_REPARSE_POINT` on NTFS directory junctions (`mklink /J`), and canonicalized `p.parent()` *after* `open()` (tautological under parent-junction races).
4. **In-Memory Intent vs. Verified OS State & Unit Scaling (`F08`, `F06`, `N01`):**
   - `F08` (`revoke_all_access_immediately`) mutated in-memory flags and config options without stopping owned Windows SCM `RustDesk`, deleting `HKCU Run`, revoking active `DeviceShield` sessions, or failing closed when SCM/registry state remained active or inaccessible.
   - `F06` gated widget-test mock state only by a runtime bool rather than compile-time `dart.vm.product` + `assert(...)`.
   - `N01` computed `(sign_us * 100.0).round() / 1000.0` (`0.1x` scaling) instead of `(sign_us * 1000.0).round() / 1000.0` (`1.0x` microseconds).

---

## 5. Actual Implementation by Remediation Area

### A. HMAC Canonicalization — `DAUVERSE_AI_EVENT_V3` (`F01`)
- **`src/dauverse/ai_bridge.rs`:**
  - Bumped active protocol to `AI_EVENT_SCHEMA_V3 = 3` with domain tag `"DAUVERSE_AI_EVENT_V3"`; `schema_version` `1` and `2` are hard-rejected (`EVENT_REJECT_UNSUPPORTED_SCHEMA_VERSION`).
  - Replaced `i64` float bucketing with `canonical_f32_hex_tag(val, min, max, field)` encoding exact big-endian IEEE-754 binary32 bits (`format!("f32:{:08x}", val.to_bits())`) after rejecting `!val.is_finite()`, negative zero (`val.to_bits() == 0x8000_0000`), and out-of-range values (`progress` in `[0.0, 100.0]`, `confidence` in `[0.0, 1.0]`).
  - Added `#[serde(deny_unknown_fields)]` on `SignedAiEventEnvelope`, `AiEvent`, `EventProvenance`, and `ReplayRecord`, and removed `#[serde(default = ...)]` from `schema_version` so missing `schema_version` or extra smuggled fields fail deserialization (`HTTP 400`).
  - Hardened loopback HTTP server (`handle_http_connection`) to validate exact `Content-Length` byte count (rejecting truncated bodies with `HTTP 400 EVENT_REJECT_TRUNCATED_HTTP_BODY`) and strict UTF-8 (`std::str::from_utf8` -> `HTTP 400 EVENT_REJECT_INVALID_UTF8`) instead of `from_utf8_lossy`.
- **`scripts/hooks/claude_code_hook.py`, `scripts/hooks/codex_notify_hook.py`, `scripts/hooks/dauverse_job_wrapper.ps1`:**
  - Upgraded all three official emitters to `schema_version = 3` (`DAUVERSE_AI_EVENT_V3`) using `struct.pack(">f", ...)` in Python and reversed `[BitConverter]::GetBytes([single]$Val)` + `UTF8Encoding($false, $true)` strict encoder in PowerShell, plus cross-platform shell & `$DeviceId` resolution in `dauverse_job_wrapper.ps1`.

### B. Durable Replay Protection & Fail-Closed Persistence (`F09`, `F07`, `F05`)
- **`src/dauverse/ai_bridge.rs` (`load_replay_journal_strict`):**
  - Checks `check_no_symlink_or_reparse_component(path)` and parent directory readability first; starts with an empty replay cache **only** when `symlink_metadata(path)` returns `ErrorKind::NotFound`.
  - Any stat error, `open_no_follow_regular_file` error, invalid UTF-8, malformed JSON line, unknown field, weak nonce, or duplicate `(event_id | nonce)` latches `journal_corrupted_fail_closed = true` with diagnostic detail in `journal_error_detail` and rejects all subsequent events with `EVENT_REJECT_REPLAY_JOURNAL_CORRUPTED_FAIL_CLOSED` (`HTTP 503` on loopback HTTP gateway).
- **`src/dauverse/security.rs`, `src/dauverse/notifications.rs`, `src/dauverse/mod.rs`:**
  - Distinguished `ErrorKind::NotFound` from permission/stat/read/parse failures across `security_audit_chain.jsonl`, `security_state.json`, `step_up_pin.vault`, and `offline_notifications.json`.
  - Propagated `persist_security_state()` errors in `verify_step_up_passcode_at` (on **both** failed-attempt/lockout and successful verification paths), `pair_trusted_device` (rolling back in-memory push on disk failure), and `revoke_device`, latching `state_corrupted_fail_closed = true` (`SECURITY_STATE_PERSIST_FAILED_FAIL_CLOSED`).
  - Aggregated `storage_healthy` and `storage_error` across replay journal, notification journal, user settings, and security persistence in `DauverseRuntime::dashboard_snapshot`.

### C. Rollback & Release Manifest Bidirectional Closure (`F11`, `F02`)
- **`installer/nsis/dauverse_setup_helper.ps1`, `scripts/windows/rollback_windows_release.ps1`, `scripts/windows/verify_and_package_windows_rc.ps1`:**
  - `CreateVerifiedBackup` refuses reparse points/symlinks inside `$FullInstallDir` before copying.
  - `Assert-BackupManifestIntegrity` and `Assert-ManifestFileValid` enforce full **bidirectional** `manifest <-> disk` closure: every manifest entry must exist as a regular non-reparse file matching SHA-256 (with no `..`, `:`, rooted paths, duplicates, trailing dots, or trailing spaces), **every file on disk** (excluding the manifest self-file) must appear in the manifest (`$Seen.Count -eq $CountedDiskFiles`), and every subdirectory is checked for `ReparsePoint` attributes.
  - Replaced whole-directory `Copy-Item -Recurse` in `rollback_windows_release.ps1` with manifest-driven `Get-VerifiedManifestRelativeFiles` copy into a clean `$InstallDir`, followed by post-restore bidirectional verification.
  - Hardened `Assert-OriginalBuildLogValid` with 9 ordered native build stage markers; moved `Start-Transcript` to `$TempVerifyLog` before writing final `SHA256_MANIFEST.txt`; upgraded Stage `[0/7]` to 12 negative selftests and Stage `[6/7]` to verify distinct pre/post `DAUVERSE_REMOTE.exe` PE SHA-256s plus unlisted-backup-extra rejection.

### D. Windows Path Confinement (`F14`)
- **`src/dauverse/crypto_util.rs`:**
  - `check_no_symlink_or_reparse_component` distinguishes `ErrorKind::NotFound` from stat errors (fail-closed on `PermissionDenied` / I/O errors).
  - Implemented pure cross-platform `parse_windows_normalized_path` + `verify_windows_final_path_confined` enforcing drive/UNC share comparison, strict segment-boundary prefix checks (`E:\QA\allowed_evil` rejected against `E:\QA\allowed`), `\\?\X:\` and `\\?\UNC\` normalization, `\\.\` / `\??\` device rejection, and NTFS ADS `:` rejection.
  - Implemented dynamic-retry fail-closed `query_windows_final_handle_path` (`len == 0` -> `Err`, dynamic buffer growth up to `65536` UTF-16 code units, strict `String::from_utf16`) wired into `write_atomic_bytes` and `sha256_file_confined_no_follow`.
- **`libs/base/src/fs.rs`, `libs/base/src/fs/download.rs`, `libs/base/src/fs/download_tests.rs`:**
  - Added `(meta.file_attributes() & 0x0400) != 0` (`FILE_ATTRIBUTE_REPARSE_POINT`) to `validate_no_symlink_components` so NTFS directory junctions (`mklink /J`) are rejected alongside symlinks.
  - Added `capture_confined_transfer_root` (capturing canonical transfer root **before** `open()`) + `verify_windows_raw_handle_confined` across `TransferJob::write`, `start_download_file`, and `resume_download` to defeat parent-junction TOCTOU races.
  - Removed `#[cfg_attr(windows, ignore)]` from `path_traversal_e2e_write_rejects_symlink_escape` and `download_refuses_symlink_destination_directory` using unprivileged `cmd /C mklink /J` junction fallback on Windows.

### E. Sender–Receiver Per-File Integrity (`F16`)
- **`libs/base/protos/message.proto`, `libs/base/src/fs.rs`, `libs/base/src/fs/download.rs`, `src/ipc.rs`, `src/server/connection.rs`, `src/ui_cm_interface.rs`, `src/client/io_loop.rs`, `src/dauverse/transfer_guard.rs`, `src/dauverse/ffi.rs`:**
  - Sender computes `(sha256, exact_size)` per file in `TransferJob::new_read` (inside `spawn_blocking`) and verifies streaming SHA-256 during `TransferJob::read`, aborting with `Err` before `FileTransferDone` if a source file mutates mid-transfer.
  - Receiver checks `.download` staging SHA-256 and exact byte size before `std::fs::rename` in both `modify_time` (server upload) and `finish_download` (client download).
  - `resolve_transfer_manifest_root_and_specs` requires a valid 64-char hex `sha256` on every incoming `FileEntry` **before** any `.download` staging file is opened or renamed, handles both single-file (`entry.name.is_empty()`) and multi-file folder geometry, and rejects unnormalized `\` on Unix.
  - `TransferIntegrityGuard::finalize_and_verify` and `TransferQueueManager::verify_and_finalize_engine_receive` **never** mark `Completed` without a valid 64-char hex sender SHA-256 per file (`INTEGRITY_MISSING_SENDER_SHA256`), unconditionally reject `.download`/`.digest` leftovers, verify per-file `expected_bytes` + constant-time SHA-256 via `sha256_file_confined_no_follow`, and preserve empty-directory (`files.is_empty() && total_size == 0`) and skipped-upload (`job.job_skipped()`) semantics.

### F. Persistence, Service Revoke OS Truth & Compile-Time Mock Isolation (`F08`, `F03`, `F06`)
- **`src/dauverse/service_ctrl.rs` & `src/dauverse/ffi.rs`:**
  - `ServiceController::status()` derives `unattended_access_enabled` truthfully from persisted `Config::get_option("approve-mode")` and queries owned Windows SCM `RustDesk` state directly via `windows_service` (`Stopped` / `Running` / `DegradedRecovering` for pending or paused states), while strictly preserving `F03` (`owned == Some(false)` external RustDesk services are never stopped or modified).
  - `revoke_all_access_immediately() -> Result<ServiceStartupState, String>` resets `approve-mode = "click"`, rotates temporary password, deletes `HKCU\...\Run\DauverseRemoteDesktop`, stops **owned** (`owned == Some(true)`) SCM `RustDesk` if `!= Stopped` with bounded polling, revokes active `DeviceShield` sessions/tokens in `ffi.rs`, re-queries OS truth, and returns `Err` (`ok: false` in FFI) if any SCM/registry query, delete, stop, or post-verification check fails.
- **`flutter/lib/dauverse/bridge/dauverse_bridge.dart` & `flutter/test/dauverse_ui_test.dart`:**
  - Guarded `setTestHarnessMode`, `setForceUnboundForTest`, `isNativeBound`, and `call()` behind `static const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product')` + `assert(...)` so Dart AOT release builds dead-code-eliminate mock state and throw `UnsupportedError` if invoked.

### G. Performance Benchmark Unit Fix (`N01`) & Reproducibility / PS 5.1 (`F15`)
- **`src/dauverse/performance.rs`:**
  - Replaced `(sign_us * 100.0).round() / 1000.0` with `PerformanceEngine::compute_per_iteration_us(total_elapsed_us, 200)` (`round_3dp(total_elapsed_us / 200.0)`), added `hmac_iterations: 200` and `hmac_total_elapsed_us`, and regenerated `ARTIFACTS/evidence/benchmark_results.json` (`hmac_event_sign_us = 1.75`, `hmac_iterations = 200`, `hmac_total_elapsed_us = 350.042`).
- **`scripts/windows/build_windows_release.ps1`, `.github/workflows/dauverse-windows-build.yml`, `scripts/windows/package_complete_rc2_qa_archive.ps1`:**
  - Replaced all 5 PowerShell 7 `??` null-coalescing operators in `build_windows_release.ps1` with PowerShell 5.1 `if (...) { ... } else { ... }` expressions (0 PS7-only tokens across all 6 `.ps1` scripts).
  - Enforced exact `makensis.exe /VERSION == v3.11` (checking `$LASTEXITCODE` + post-install version verification in `.github/workflows/dauverse-windows-build.yml` and CI provenance assertion in `verify_and_package_windows_rc.ps1`).
  - Added SHA-256 verification gates for both Codex QA reports and `DAUVERSE_REMOTE_V1_RC3_SOURCE_REVIEW_HANDOFF.md`.

---

## 6. Test-First Remediation & Regression Suite Evidence

### 6.1 Pre-Fix FAIL Proof on Unmodified RC2 (`0e1e3e87185159a481360b2c2b28f3dee541328f`)
Before editing production code, targeted reproduction harnesses were executed directly against unmodified RC2 (`0e1e3e871`) and confirmed to **FAIL** on all targeted RC2 bugs:
1. **Rust Pre-Fix Reproduction (`EXIT_CODE_ON_UNMODIFIED_RC2=101`, `0 passed; 4 failed`):**
   - `repro_f01`: Distinct IEEE-754 `f32` values `100.0` (`0x42c80000`) and `f32::from_bits(0x42c8_0001)` (`100.00001`) produced identical HMAC signatures; smuggled unknown JSON fields were accepted.
   - `repro_f09`: Unreadable/corrupted replay journal directory started cleanly with `0` replay entries and accepted replayed events (`Ok`).
   - `repro_f16`: `finalize_and_verify` marked transfer `Completed` with `expected_sha256: None`, and `verify_and_finalize_engine_receive` accepted mutated file bytes (`AAAA` -> `BBBB`) and compensating file sizes (`[4, 6]` -> `[2, 8]`).
   - `repro_n01`: `12.34 µs` per-iteration elapsed time was misreported as `1.234 µs` (`÷10` error).
2. **PowerShell Pre-Fix Reproduction:**
   - `F11`: Unlisted rogue file `rogue_injected_payload.dll` inside `app.rollback_backup` passed `Assert-BackupManifestIntegrity` and was copied into `InstallDir` during rollback.
   - `F02`: Unlisted extra file in `release` passed `Assert-ManifestFileValid`, and a padded synthetic build log containing only the final banner passed `Assert-OriginalBuildLogValid`.
   - `F15`: `build_windows_release.ps1` contained 5 `QuestionQuestion` (`??`) tokens incompatible with Windows PowerShell 5.1.

### 6.2 Post-Fix PASS Verification on RC3 Source Candidate
All executable verification suites on the Linux cloud environment passed (`0` failures, `0` ignored tests):

| Suite | Command | Result | Evidence Artifact |
|---|---|---|---|
| **`base` Filesystem, Download & Confinement Tests** | `cargo test --locked -p base --lib` | **PASS (`26 passed; 0 failed; 0 ignored`)** | `ARTIFACTS/evidence/rc2_base_fs_tests.log` |
| **`dauverse::` Security, Bridge, Transfer, Service & Benchmark Unit Tests** | `cargo test --locked --features linux-pkg-config --lib dauverse::` | **PASS (`29 passed; 0 failed; 0 ignored`)** | `ARTIFACTS/evidence/dauverse_unit_security_tests.log` |
| **Flutter UI & Unbound Fail-Closed Tests** | `flutter test --no-pub test/dauverse_ui_test.dart` | **PASS (`5 passed; 0 failed`)** | `ARTIFACTS/evidence/flutter_dauverse_ui_tests.log` |
| **Flutter Compile-Time `dart.vm.product=true` Guard Probe** | `flutter test --no-pub --dart-define=dart.vm.product=true <probe>` | **PASS (`isReleaseBuild == true`, `setTestHarnessMode` & `setForceUnboundForTest` throw `UnsupportedError`)** | Verified in CI-equivalent VM define probe |
| **PowerShell AST & Validator Negative/Positive Harness** | `python3 TESTS/test_rc3_powershell_validators.py` | **PASS (`6` `.ps1` files `0` PS7 tokens; `F01`, `F02`, `F11` checks all `true`)** | `TESTS/test_rc3_powershell_validators.py` |
| **4-Process Live Release `.so` FFI, Hook, Replay & Secret Hygiene Matrix** | `python3 TESTS/test_e2e_hooks_and_secrets.py` (against freshly compiled `target/release/liblibrustdesk.so`) | **PASS (`phase1`, `phase2`, `phase3_corrupt`, `phase4_corrupt_replay -> HTTP 503`, `PASS_ZERO_SECRETS` across `1194` files)** | `ARTIFACTS/evidence/{ai_bridge_and_secret_scan.json,rc2_security_negative_matrix.json,release_ffi_smoke_test.json,benchmark_results.json}` |

---

## 7. Negative Security Test Evidence Summary

| Finding | Negative / Adversarial Inputs Executed & Verified Rejected |
|---|---|
| **F01 (HMAC V3)** | IEEE-754 1-ULP neighbors (`0x42c80001` vs `0x42c80000`, `0x3f7fffff` vs `0x3f800000`), `NaN`, `+Infinity`, `-Infinity`, negative zero `-0.0` (unit + raw HTTP wire `HTTP 401`), out-of-range `progress`/`confidence`, missing `schema_version` (`HTTP 400`), schema `v1`/`v2` downgrade (`HTTP 401`), unknown smuggled JSON fields (`HTTP 400`), invalid UTF-8 bytes `\xff\xfe\xfd\xfc` (`HTTP 400`), truncated `Content-Length` HTTP body (`HTTP 400`), untrusted `claude_desktop` claiming `OFFICIAL_HOOK` (`HTTP 401`), Unicode NFD vs NFC string difference, and mutations across all 12 event/provenance fields. |
| **F09 / F07 / F05 (Persistence & Replay)** | Cross-restart nonce/event_id replay (`HTTP 401`), corrupted UTF-8 / malformed JSONL replay journal (`phase4_corrupt_replay` -> `HTTP 503 EVENT_REJECT_REPLAY_JOURNAL_CORRUPTED_FAIL_CLOSED`), directory-in-place-of-journal stat/open fault, corrupted `bridge_hmac.vault` (`phase3_corrupt` -> `storage_healthy == false`), read-only directory fault during `verify_step_up_passcode_at` (both lockout/failure and success paths fail closed with `SECURITY_STATE_PERSIST_FAILED_FAIL_CLOSED`), unauthenticated PIN overwrite (`SECURITY_DENY_CURRENT_PIN_REQUIRED`), and 5-attempt PIN lockout. |
| **F11 / F02 (Manifest Closure)** | Unlisted rogue file `rogue_extra.dll` in `.rollback_backup` rejected before restore; unlisted extra file in `release` rejected; directory junction/symlink inside backup or release rejected; missing file, bad SHA-256, duplicate entry, trailing-space/dot segment, missing build log, tiny placeholder build log, padded synthetic build log missing ordered compiler markers, skipped-tests marker, and early-exit `0`/`1`/`2` GUI checks all rejected. |
| **F14 (Path Confinement)** | Sibling-prefix escape (`E:\QA\allowed_evil\secret.txt` vs `E:\QA\allowed`), UNC share mismatch, NTFS ADS (`report.txt:hidden`, `::$DATA`), raw device paths (`\\.\PhysicalDrive0`, `\??\...`), symlink/junction escape on upload, download, `write_atomic_bytes`, `sha256_file_confined_no_follow`, and post-validate symlink swap before finalize. |
| **F16 (File Integrity)** | Missing/empty sender `FileEntry.sha256` rejected pre-write (`INTEGRITY_REJECT_MISSING_SENDER_SHA256`) and post-receive (`INTEGRITY_MISSING_SENDER_SHA256`), same-size byte tamper (`AAAA` -> `BBBB`), compensating multi-file size tamper (`[4, 6]` -> `[2, 8]`), mid-transfer sender file mutation aborted during `TransferJob::read`, `.download` staging tamper blocked before rename in `modify_time` and `finish_download`, residual `.download`/`.digest` files rejected, and unnormalized `\` on Unix rejected. |
| **F08 / F06 / F12 / N01** | Owned SCM service still `Running` or `DegradedRecovering` after revoke -> `Err`, SCM `AccessDenied` -> `Err`, `HKCU Run` still present -> `Err`, external `owned == Some(false)` RustDesk service left untouched (`Ok`), `dart.vm.product=true` `setTestHarnessMode(true)` -> `UnsupportedError`, spoofed `SignatureVerification::ValidAuthenticodeAndPublisher` with unsigned binary -> blocked, and `N01` `hmac_event_sign_us * 200` verified within rounding tolerance of `hmac_total_elapsed_us`. |

---

## 8. Internal Cross-Review Summary (Section 6 Disclosure)

- **Reviewer Context & Honest Model Identity Disclosure:** Internal cross-review was performed in an isolated read-only subagent context (`research` subagent, conversation ID `2504251b2c9f9155c4f462b4f71871cf`) configured with `Model: inherit` (same platform model as the parent session; **no external Neon model routing was available in this environment, no model identity was spoofed, and zero extra cost was incurred**). Internal cross-review does **not** replace Codex Independent QA.
- **Findings Raised by Internal Cross-Review & Resolved Before Handoff:**
  1. `HIGH-01` (`F14` in `libs/base/src/fs.rs` & `download.rs`): Fixed post-open handle confinement tautology under parent-junction TOCTOU races by capturing canonical transfer root *before* `open()` (`capture_confined_transfer_root`) and using strict `String::from_utf16` + device-prefix rejection across `write`, `start_download_file`, and `resume_download`.
  2. `HIGH-02` (`F16` in `transfer_guard.rs`, `ui_cm_interface.rs`, `io_loop.rs`): Required valid 64-hex `FileEntry.sha256` in `resolve_transfer_manifest_root_and_specs` *before* any `.download` write/rename, preserved empty-directory transfers (`files.is_empty() && total_size == 0`) with symlink checks, and handled `job.job_skipped()` on uploads without false tamper errors.
  3. `HIGH-03` (`dauverse_job_wrapper.ps1` & `test_e2e_hooks_and_secrets.py`): Resolved portable PowerShell executable & `$DeviceId` fallback, aligned CLI flags, added HTTP `-0.0` wire negative test, rebuilt `target/release/liblibrustdesk.so`, and regenerated all `ARTIFACTS/evidence/*` outputs.
  4. `MEDIUM-01` (`F08` in `service_ctrl.rs`): Queried owned Windows SCM service state directly via `windows_service` (distinguishing `Stopped`, `Running`, pending/paused `DegradedRecovering`, and SCM/HKCU query errors) and required `after_service_state == ServiceRunState::Stopped` after revoke.
  5. `MEDIUM-02` (`F15` in `dauverse-windows-build.yml` & `verify_and_package_windows_rc.ps1`): Added `$LASTEXITCODE` + post-install `makensis.exe /VERSION == v3.11` verification and CI provenance assertion.
  6. `MEDIUM-03` (`AGENTS.md` Tokio rules in `io_loop.rs` & `connection.rs`): Wrapped synchronous full-file SHA-256 `TransferJob::new_read` calls in `tokio::task::spawn_blocking`.
  7. `LOW-01` & `LOW-02`: Added trailing-space segment + `$Seen.Count -eq $CountedDiskFiles` checks in PowerShell manifest validators, rejected unnormalized `\` on Unix in `transfer_guard.rs`, removed `unused_mut` warnings, and switched peer/loop-reachable warnings/errors to `hbb_common::throttled_log!`.

---

## 9. Remaining Risks & Gate-Controlled Verification Boundaries

1. **Windows Native Build & Windows Sandbox Execution (`BLOCKED — SOURCE FIRST GATE`):** Per Boss Directive Section 1 & Section 7, **zero** Windows CI workflows or native Windows builds were executed for RC3 prior to Codex Source Review. Native Windows compilation of the new `#[cfg(windows)]` / `#[cfg(target_os = "windows")]` blocks (`GetFinalPathNameByHandleW`, `windows_service` SCM status query/stop, `mklink /J` tests, NSIS `v3.11` packaging, and 7-stage Windows Sandbox verification) will execute only **after** Codex Source Review passes and Boss approves a Windows RC3 build.
2. **Two-Host Windows LAN/WAN + RTX 3060 NVENC Validation (`BLOCKED — LAB REQUIRED`):** End-to-end 2-PC remote desktop session control, 1080p60/1440p60 `<35 ms` LAN latency, NVENC hardware encoder counters, and live 2-peer Windows upload/download (`F02`, `F10`, `F16`) cannot be measured in a single-VM cloud environment.
3. **Live Running External RustDesk Windows Service Coexistence (`BLOCKED — LAB REQUIRED`, `F03`):** Ownership guards in NSIS, PowerShell, and `service_ctrl.rs` are verified at source/unit level, and disposable CI tests simulated external folders/registry keys, but coexistence against a pre-installed actively running official RustDesk Windows service requires a dedicated Windows lab VM.
4. **Physical Monitorless Headless IDD Activation (`BLOCKED — HARDWARE & BOSS APPROVAL GATED`, `F04`), Authenticode Signing (`BLOCKED — CERT UNAVAILABLE`, `F12`), and Real Smart Power / WoL (`NOT_TESTED — GOVERNANCE LOCKED`, `F13`):** Preserved fail-closed (`DisabledSmartPlugAdapter` retained for `Hunonic SK02`; `DAUVERSE AI` untouched; `Production LOCKED`).
5. **Known Multi-File Partial-Skip Fail-Closed Limit (`F16`):** If a user transfers a multi-file folder (`files.len() > 1`) where an older file already exists at destination and clicks manual "Skip" on that individual file during overwrite confirmation, `verify_and_finalize_engine_receive` intentionally fails closed rather than marking the batch `SENDER_SHA256_VERIFIED` when on-disk bytes differ from the sender's manifest digest. Single-file skip (`job.job_skipped()`) is handled cleanly as `Cancelled / skipped`.

---

## 10. Independent Review Instructions for Codex

### Step 1 — Verify Bundle & Repository Integrity (Clean-Room)
```bash
unzip -q DAUVERSE_REMOTE_DESKTOP_V1_RC3_SOURCE_REVIEW_PACKAGE.zip -d /tmp/rc3_review
cd /tmp/rc3_review/RC3_SOURCE_REVIEW_PACKAGE
sha256sum -c SOURCE_SHA256_MANIFEST.txt

mkdir /tmp/rc3_bare_verify && cd /tmp/rc3_bare_verify
git init --bare
git bundle verify /tmp/rc3_review/RC3_SOURCE_REVIEW_PACKAGE/DAUVERSE_REMOTE_DESKTOP_V1_RC3_SOURCE.bundle
git fetch /tmp/rc3_review/RC3_SOURCE_REVIEW_PACKAGE/DAUVERSE_REMOTE_DESKTOP_V1_RC3_SOURCE.bundle 'refs/*:refs/*'
git fsck --full --strict
```

### Step 2 — Verify Preserved Codex QA Reports & Inspect Full RC2 -> RC3 Diff
```bash
# Checkout RC3 candidate from bundle (or inspect develop/dauverse-remote-v1 directly):
git clone /tmp/rc3_review/RC3_SOURCE_REVIEW_PACKAGE/DAUVERSE_REMOTE_DESKTOP_V1_RC3_SOURCE.bundle /tmp/rc3_src -b develop/dauverse-remote-v1
cd /tmp/rc3_src

# Verify exact SHA-256 of both Codex QA reports and tracked manifests:
sha256sum QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md
# Expected:
# f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913  QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md
# c23d36e7d83b2fb1402238d8a8501b9de899fcd94b2774155b6a602fd77fb954  QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md

sha256sum -c SHA256_MANIFEST.txt
sha256sum -c ARTIFACTS/SHA256_MANIFEST.txt

# Inspect complete diff from RC2 baseline (0e1e3e87185159a481360b2c2b28f3dee541328f):
git diff 0e1e3e87185159a481360b2c2b28f3dee541328f..HEAD
```

### Step 3 — Execute Automated Regression & Negative Security Suites
```bash
# 1. Workspace base crate unit & confinement tests (26 tests):
cargo test --locked -p base --lib

# 2. DAUVERSE Rust unit & negative security tests (29 tests):
cargo test --locked --features linux-pkg-config --lib dauverse::

# 3. PowerShell 5.1 AST compatibility + F01/F02/F11 negative & positive validator suite:
python3 TESTS/test_rc3_powershell_validators.py

# 4. Build release shared library and run 4-process live FFI / Hook / Replay / F16 / N01 E2E matrix:
cargo build --locked --features linux-pkg-config --release --lib
python3 TESTS/test_e2e_hooks_and_secrets.py

# 5. Flutter UI & F06 fail-closed widget tests:
cd flutter && flutter test --no-pub test/dauverse_ui_test.dart
```

---

## 11. Source & Evidence SHA-256 Manifest (RC3 Candidate Files)

*(Full repository manifest is maintained in `SHA256_MANIFEST.txt` and `ARTIFACTS/SHA256_MANIFEST.txt`, verifiable via `sha256sum -c SHA256_MANIFEST.txt`.)*

```text
f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913  QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md
c23d36e7d83b2fb1402238d8a8501b9de899fcd94b2774155b6a602fd77fb954  QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md
16a18d11690b305995c2b01ea1a4c1f7316e133ae7b407e5ed2a3387ff56ac92  .github/workflows/dauverse-windows-build.yml
b92da4e3b329eaf206e516357c5a8ae352c061d32d33297938199cf3d4dcd1a3  FEATURE_ACCEPTANCE_MATRIX.md
575bf958c0ae26d131334cd7a7ef2cf4c2a72373c5623cfe5fc99a76e4ee0687  FINDINGS_REMEDIATION_MATRIX.md
b48890ef7d57f722c8a275ddd4c40ad5d0821dcdeb16970a3c25efaf7f3b25bf  TESTS/test_e2e_hooks_and_secrets.py
d0a87ba6a60a569f3301e2c21f574370df0498a29b57528624bd153ef6cceab3  TESTS/test_rc3_powershell_validators.py
d9c624844a706dadb8a841f9e29f4a796ff6dc4b37ae53c55a64529dd3e45b6b  flutter/lib/dauverse/bridge/dauverse_bridge.dart
3583c4026e7337093d14470cd4f392bc8e13c9a9d8eeaeb4354dab8ef6f700f7  flutter/test/dauverse_ui_test.dart
cdf87aa71dfffd271f1a1940726cb34e316d19d8ccac0fb6970c8407e5fc8858  installer/nsis/dauverse_setup_helper.ps1
f9b41502add3ea326e9e15bf3e0f6fc9cb0c6e75bc3aa258f63e6d1c7a689173  libs/base/protos/message.proto
e4ae637193a66e28281b55c5d1aef7c94f143d1eb20d89043a04d2f203fe3f85  libs/base/src/fs.rs
70f404eaad01a7d0079aa1818b0d5f4a32f8c8ca7c2afe343ead24133b6bea05  libs/base/src/fs/download.rs
370088cdb3f6e8686905e12d39b96c480ec3f1bc6fb9a0d31ebc74b627f545e1  libs/base/src/fs/download_tests.rs
64388cc97a6c892befef7d592cbbabdf0d879c2d70595c70b035216be1dcc5ec  scripts/hooks/claude_code_hook.py
ec7fb295e994eb1a41e406fbf583deb22dd83522ae4519062677eac4b916b7ad  scripts/hooks/codex_notify_hook.py
21f15265d34c07c16389aa3ac3204588ec6277436938fda38dcfda1c25270f34  scripts/hooks/dauverse_job_wrapper.ps1
75da12c46d79d95289e9254e87ab7926e646420d16c76a5d97b101b83b094bd3  scripts/windows/build_windows_release.ps1
73fe0aa33453fe34d631aa4fd866b9459093067baeb3d4068983e6a1e4538864  scripts/windows/package_complete_rc2_qa_archive.ps1
6469bbfa6aa875fa9010dbca8707cc21a1e2071389e0ee67d049ab40e0473eca  scripts/windows/rollback_windows_release.ps1
edb204934ef052006ef6ea2a0a3393e7b93c23c77d0394b5ed587e23efdf6285  scripts/windows/verify_and_package_windows_rc.ps1
d418318956acf7fc5b3d1c1e096b7cfdc96b8d60894f4680999a59660416f7b5  src/client/io_loop.rs
65be4987ef65fbdb20f59b0390c752b8bce97fca4bd069d1b31be8143947be16  src/dauverse/ai_bridge.rs
46fa3e9e07b513c44797257646eed104d77a83ef2243f25eca7c176d4821a11b  src/dauverse/crypto_util.rs
f5b6ce05b55980176ecda67ed52ba471151c3dc30efd0043823078af2fda2ab4  src/dauverse/ffi.rs
cf57e90ca8a93370e95e5f3fa371d072c7d40d4652b1464290b2b14583fa06c0  src/dauverse/mod.rs
ed0b495b1b1053c6687d4902f025d69be44e55e7fcc40e183895d0bd15bba8c7  src/dauverse/notifications.rs
ea5f7d29ba79e7b054122e81825f4e9a0819e6d13f0fd1f1c604f24b7be8a23b  src/dauverse/performance.rs
407d677740269539e41c9fe8f4704cab8a714746c09e87811c51902e415154d3  src/dauverse/security.rs
b665be795b39d70728b8db010c5711c407c28911676109f3072ce605b3e1e247  src/dauverse/service_ctrl.rs
7730cddf75310ae2b66fef451184c13ab17ed3eefda9c657d46a75ea6e600e72  src/dauverse/transfer_guard.rs
1706bafa5c4f7d24829caa5e860acca0b6d3cce47598d7a0f13e14a97ed8d1c0  src/ipc.rs
ae4e19467e1c36235db7f5d32945380b4d38d71f81435319ff62aee75507c069  src/server/connection.rs
b7d3db96ae99bae93202f917bf4acfd601a928a18c6f298f740961e92e02d0d4  src/ui_cm_interface.rs
f21c16c1a08d287bd1bce69f1ecd1083ae69108e98b95ec51395ef9897e6de5a  ARTIFACTS/evidence/ai_bridge_and_secret_scan.json
cf679341fd025dc4c87633b103ff00fe23be85ffceb17f40d8f66a21bcd0643e  ARTIFACTS/evidence/benchmark_results.json
5249362a3154cca76f3910ae6fb1f8176a58a3c3a7ed45f92bb7094273463e6f  ARTIFACTS/evidence/dauverse_unit_security_tests.log
f43eb3bc3dc379d6571ed1969cc6431de3552a1dcf9db5d415c6203e55b9ec6f  ARTIFACTS/evidence/flutter_dauverse_ui_tests.log
49ed6d8b18aad5d856eb7d87510c7219caa20496255dd8a466bf9ea0662b11d0  ARTIFACTS/evidence/rc2_base_fs_tests.log
6f1767be35abd47ecafbbbd2e6a2095a590bf1f47b55cf5cee0852a065d20d6e  ARTIFACTS/evidence/rc2_security_negative_matrix.json
f5fd51aa3f903a7d1c58d35784556981780130370ab1cd25263390992c46a4b4  ARTIFACTS/evidence/release_ffi_smoke_test.json
```

# DAUVERSE REMOTE DESKTOP V1 — FINDINGS REMEDIATION MATRIX (WINDOWS RC2)

- **Task ID:** `DREMOTE-V1-REMEDIATION-005`
- **Source Independent QA Report:** `QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md` (SHA-256: `f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913`)
- **Pre-Remediation RC1 Baseline:** `309948002371aba1407532c9ba8d9d216a02e771` (`develop/dauverse-remote-v1`, Actions Run `45603088230`)
- **Severity Counts Preserved Unchanged:** `0 P0` • `6 P1` (`F01`–`F06`) • `9 P2` (`F07`–`F14`, `F16`) • `1 P3` (`F15`) • plus delivery/provenance observations `A01`–`A04`.
- **Governance & Status Legend:**
  - `REMEDIATED (PENDING INDEPENDENT RE-QA)`: Source fix implemented, verified by automated positive + negative regression tests and single-host disposable `windows-2022` CI evidence; awaits independent Codex Re-QA verification.
  - `PASS`: Specific executed automated/single-host check met its exact criterion.
  - `BLOCKED`: Requires two physical/VM Windows endpoints, authorized driver/service installation on a test GPU workstation, or vendor API unavailable by governance.
  - `NOT TESTED`: Exhaustive external procedure outside single-runner CI scope not independently executed.
  - `SIMULATED`: Test-only mock explicitly isolated from production runtime.
  - **Production Status:** **`LOCKED`** (Developer never self-certifies `Independent QA PASS` or `Production Approved`).

---

## 1. Summary Table (All 16 Findings: `F01`–`F16`)

| Finding ID | Severity | Area | Status |
|---|---|---|---|
| **F01** | **P1** | AI Event Bridge HMAC v2 Full-Payload Coverage & Source Adapter Trust | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F02** | **P1** | Fail-Closed Windows QA Harness, GUI Survival & Immutable Build Manifests | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F03** | **P1** | NSIS Installer, Uninstaller, Rollback & Runtime Service/Process Ownership | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F04** | **P1** | Headless Mode Truthfulness, Operational State Machine & WHQL Catalog Verification | `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(Physical monitorless GPU runtime: `BLOCKED`)* |
| **F05** | **P1** | Step-Up PIN Authenticated Rotation, Lockout, Expiring Grants & Vault Corruption | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F06** | **P1** | Flutter-to-Rust FFI Production Fail-Closed Enforcement | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F07** | **P2** | Durable `%LOCALAPPDATA%` Storage, Atomic Synced Writes & Restart Persistence | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F08** | **P2** | Authoritative Windows Service (`HKLM`) & Auto-Start (`HKCU Run`) Synchronization | `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(Host service start/reboot: `BLOCKED`)* |
| **F09** | **P2** | Time-Windowed Non-Evicting Replay Cache (`660s`) & Durable Replay Journal | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F10** | **P2** | Truthful Telemetry (`measured_fps = None` vs `configured_target_fps`) | `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(2-PC live session counters: `BLOCKED`)* |
| **F11** | **P2** | Pre-Validated `BACKUP_SHA256_MANIFEST.txt` & Transactional Rollback Recovery | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F12** | **P2** | Independent Artifact Signature Inspection & Auto-Update Hard-Block | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F13** | **P2** | Zero-Side-Effect Dry-Run Enforcement for Wake-on-LAN | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F14** | **P2** | Confined `O_NOFOLLOW` / `FILE_FLAG_OPEN_REPARSE_POINT` + `GetFinalPathNameByHandleW` File I/O | `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(Unproven risk hardened; lab NTFS junction race: `NOT TESTED`)* |
| **F15** | **P3** | Toolchain Version Pinning, Cache v2 & `BUILD_PROVENANCE.json` Closure | `REMEDIATED (PENDING INDEPENDENT RE-QA)` |
| **F16** | **P2** | Engine `ipc::FS::WriteDone` Confined SHA-256 & Byte-Count Receive Finalization | `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(2-PC live transfer: `BLOCKED`)* |

---

## 2. Detailed Finding-by-Finding Remediation Records

### F01 — HMAC Excludes Security-Relevant Event Fields
- **Finding ID:** `F01`
- **Severity:** `P1`
- **Root cause:** `canonical_signing_bytes` in RC1 authenticated a subset of core fields using pipe-delimited concatenation while omitting `task_name`, `summary`, `severity`, `progress`, `artifact_reference`, `confidence`, and `provenance.*` (`adapter_type`, `evidence_verified`, `exit_code`, `evidence_badge`), allowing post-signing mutation of omitted fields and provenance normalization (`UNKNOWN` -> `COMPLETED`).
- **Affected source:** `src/dauverse/ai_bridge.rs`, `scripts/hooks/claude_code_hook.py`, `scripts/hooks/codex_notify_hook.py`, `scripts/hooks/dauverse_job_wrapper.ps1`.
- **Implementation fix:** Introduced mandatory `schema_version == 2` (`AI_EVENT_SCHEMA_V2`) and `canonical_signing_bytes_checked` (`DAUVERSE_AI_EVENT_V2` compact UTF-8 JSON array) binding **every** `AiEvent` and `EventProvenance` field with unambiguous JSON escaping and deterministic 4-decimal float formatting (`"{:.4}"`) across Rust, Python, and PowerShell; rejected non-finite floats, legacy `schema_version < 2` (`EVENT_REJECT_UNSUPPORTED_SCHEMA_VERSION`), and untrusted/read-only sources claiming `OFFICIAL_HOOK` / `APPROVED_WRAPPER_ADAPTER` via `validate_source_adapter_policy`.
- **Regression test:** `dauverse::ai_bridge::tests::verify_and_ingest_accepts_valid_v2_and_blocks_false_completion` + live hook E2E (`claude_code_hook.py`, `codex_notify_hook.py`, `dauverse_job_wrapper.ps1`).
- **Negative test:** `dauverse::ai_bridge::tests::f01_mutating_any_event_or_provenance_field_invalidates_hmac_v2` (mutates 10 previously-unsigned fields, legacy `schema_version = 1`, and untrusted `claude_desktop` adapter claim) + `TESTS/test_e2e_hooks_and_secrets.py` + `verify_and_package_windows_rc.ps1` Phase 2 HTTP `401` matrix.
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/dauverse_unit_security_tests.log`, `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` (`phase2.f01_field_mutations_rejected = 10`).
- **Remaining risk:** Same-user local processes possessing read access to the user's `bridge_hmac.vault` / `DAUVERSE_EVENT_HMAC_KEY` share the local user trust boundary; loopback bridge does not authenticate separate OS users on multi-tenant terminal servers.
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F02 — Windows Harness Allows False Acceptance
- **Finding ID:** `F02`
- **Severity:** `P1`
- **Root cause:** RC1 `verify_and_package_windows_rc.ps1` accepted GUI early exit codes `0/1/2` without a surviving window, synthesized a 1-line `WINDOWS_NATIVE_BUILD.log` if absent, regenerated top-level `SHA256_MANIFEST.txt` before validating incoming manifest entries, checked `usbmmidd.cat` signer subject without asserting `Status == 'Valid'` + `Test-FileCatalog` membership, and used broad over-scoped `PASS` wording.
- **Affected source:** `scripts/windows/build_windows_release.ps1`, `scripts/windows/verify_and_package_windows_rc.ps1`.
- **Implementation fix:** Added Stage `[0/7]` `QA_HARNESS_NEGATIVE_SELFTEST.json` (10 negative sentinels verified to throw before RC checks); froze `INITIAL_BUILD_SHA256_MANIFEST.txt` in `build_windows_release.ps1` and validated it before any test; forbade synthetic build logs (`Assert-OriginalBuildLogValid`); marked `-SkipTests` builds `TESTS_SKIPPED_NOT_RC_ELIGIBLE.txt` (rejected by harness); asserted exact `--version == 1.5.3` and 5-second Win32 GUI process survival with loaded `librustdesk.dll` + `flutter_windows.dll` for both installed and portable binaries; validated `usbmmidd.cat` `Status == 'Valid'` + `Test-FileCatalog` on `x64\usbmmIdd.dll` and `usbmmIdd.inf`; scoped report claims strictly to single-host runner gates while keeping 2-PC/hardware items `BLOCKED`.
- **Regression test:** Stage `[1/7]`–`[7/7]` in `scripts/windows/verify_and_package_windows_rc.ps1`.
- **Negative test:** Stage `[0/7]` `Assert-Throws` suite (`missing_manifest_file`, `corrupted_manifest_digest`, `duplicate_manifest_entry`, `gui_early_exit_0/1/2_rejected`, `gui_missing_dll_rejected`, `missing_build_log_rejected`, `synthetic_placeholder_build_log_rejected`, `skipped_tests_marker_rejected`).
- **Evidence:** `EVIDENCE/QA_HARNESS_NEGATIVE_SELFTEST.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json`, `LOGS/WINDOWS_RC_VERIFICATION.log`, `RELEASE/INITIAL_BUILD_SHA256_MANIFEST.txt`.
- **Remaining risk:** Single-runner `windows-2022` Session `1`/`0` survival + DLL load proves native process/FFI/Flutter startup without crash, whereas interactive pixel rendering & DPI visual inspection remain `BLOCKED` until human/pilot guest review.
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F03 — Installer/Uninstaller Can Affect Unrelated RustDesk Service
- **Finding ID:** `F03`
- **Severity:** `P1`
- **Root cause:** `dauverse_setup.nsi` and `rollback_windows_release.ps1` stopped/deleted Windows Service `RustDesk` and killed processes by image name without verifying `HKLM\SYSTEM\CurrentControlSet\Services\RustDesk\ImagePath` or `Win32_Process.ExecutablePath` ownership under `$INSTDIR\`.
- **Affected source:** `installer/nsis/dauverse_setup.nsi`, `installer/nsis/dauverse_setup_helper.ps1`, `scripts/windows/rollback_windows_release.ps1`, `src/dauverse/service_ctrl.rs`, `scripts/windows/verify_and_package_windows_rc.ps1`.
- **Implementation fix:** Added `CHECK_RUSTDESK_SERVICE_OWNERSHIP` macro in `dauverse_setup.nsi`, `Test-ServiceOwnedByDir` in `rollback_windows_release.ps1`, and `is_service_image_path_owned_by_install_dir` in `src/dauverse/service_ctrl.rs`; scoped all process stops strictly to `ExecutablePath.StartsWith("$INSTDIR\")`; refused `SecService` / `configure_unattended(true)` collision when an external `RustDesk` service exists; preserved external `RustDesk` services and configs untouched across install, upgrade, rollback, and uninstall.
- **Regression test:** `dauverse::service_ctrl::tests::f03_f08_service_image_path_ownership_and_state_demotion` + Windows CI Stage `[2/7]` & `[6/7]`.
- **Negative test:** Pre-registered simulated external `RustDesk` service (`ExternalRustDeskCoexist\rustdesk.exe`) before `SETUP.exe /S`, verified `configure_unattended(true)` fails closed, and proved external `RustDesk` service + config survive `SETUP.exe /S`, `rollback_windows_release.ps1`, and `Uninstall.exe /S` byte-for-byte untouched.
- **Evidence:** `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` (`external_rustdesk_coexistence_preserved_on_install_rollback_uninstall = PASS`), `LOGS/GITHUB_ACTIONS_VERIFY_CONSOLE.log`.
- **Remaining risk:** Because upstream `src/platform/windows.rs` hardcodes SCM name `"RustDesk"`, DAUVERSE cannot simultaneously run its own background Windows Service on a host where an external RustDesk Windows Service is already installed (collision is safely refused; portable/interactive mode still works).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F04 — Headless Active State Without Native Activation
- **Finding ID:** `F04`
- **Severity:** `P1`
- **Root cause:** In RC1 `src/dauverse/headless.rs`, `activate_virtual_display` gated the Windows `plug_in_headless()` call on `should_activate && whql_driver_install_approved`, but then unconditionally assigned `self.state.virtual_display_active = should_activate`, reporting `Active` even when approval was `false` or on non-Windows/test builds.
- **Affected source:** `src/dauverse/headless.rs`, `src/dauverse/ffi.rs`, `flutter/lib/dauverse/screens/power_security_ops_screens.dart`.
- **Implementation fix:** Introduced explicit `HeadlessOperationalStatus` (`Configured`, `Available`, `Requested`, `BlockedApprovalRequired`, `BlockedDriverUnavailable`, `Active`, `Failed`), pinned byte-level SHA-256 verification of staged `usbmmidd_v2` files (`verify_staged_whql_driver_package`), Win32 `GetSystemMetrics(SM_CMONITORS)` display count probing, and strict invariant that `virtual_display_active` becomes `true` **only** after a real Windows `plug_in_headless()` call returns `Ok(_)`.
- **Regression test:** `dauverse::headless::tests::f04_headless_never_reports_active_without_approval_and_native_plug` + `dauverse::headless::tests::verify_staged_driver_rejects_missing_or_tampered_files`.
- **Negative test:** `headless_activate` without approval and `headless_request_driver("rustdesk_idd", true)` verified in Rust unit tests, Linux `.so` E2E, and Windows DLL FFI (`ok == false`, `virtual_display_active == false`, `operational_status == "BLOCKED_APPROVAL_REQUIRED"`).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json`.
- **Remaining risk:** Actual installation/activation of `usbmmidd_v2` on a monitorless physical GPU host remains intentionally **`BLOCKED`** until Boss grants pilot endpoint approval (no driver is installed on CI or Boss's host).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(Monitorless hardware activation: `BLOCKED`)*

### F05 — Step-Up PIN Replacement Lacks Existing-Owner Authentication
- **Finding ID:** `F05`
- **Severity:** `P1`
- **Root cause:** `set_step_up_passcode` overwrote an existing `step_up_pin.vault` without verifying the current PIN, lacked dedicated PIN brute-force rate limiting and expiring step-up tokens, and did not fail closed if `step_up_pin.vault` was corrupted on disk.
- **Affected source:** `src/dauverse/security.rs`, `src/dauverse/ffi.rs`, `src/dauverse/mod.rs`, `flutter/lib/dauverse/dauverse_shell.dart`, `flutter/lib/dauverse/screens/power_security_ops_screens.dart`.
- **Implementation fix:** Restricted `set_step_up_passcode` strictly to first-time enrollment (`SECURITY_DENY_CURRENT_PIN_REQUIRED` once enrolled); added `change_step_up_passcode_at(current_pin, new_pin, now_ms)` requiring current-PIN constant-time verification; added per-principal PIN lockout (`5` failures/`60s` -> `120s` lockout persisted in `security_state.json`), `300s` TTL `StepUpAuthGrant` tokens, and `vault_corrupted_fail_closed` detection (`SECURITY_VAULT_CORRUPTED_FAIL_CLOSED` with zero silent reset).
- **Regression test:** `dauverse::security::tests::f05_f07_pin_enrollment_requires_current_pin_for_change_locks_out_and_persists` + 3-process Windows DPAPI reopen & rotation test.
- **Negative test:** Unauthenticated `set_step_up_pin` overwrite refusal, wrong `current_pin` rotation refusal, 5-strike brute-force lockout even when 6th attempt uses valid PIN, expired token refusal, and corrupted `step_up_pin.vault` fail-closed refusal (`phase2` & `phase3_corrupt`).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` (`phase2.dpapi_reopen_verified = true`, `phase2.f05_lockout_verified = true`, `phase3_corrupt_vault_fail_closed = PASS`).
- **Remaining risk:** Manual PIN recovery when a user forgets their Step-Up PIN requires local OS user deletion of `step_up_pin.vault` + `security_state.json` under `%LOCALAPPDATA%\DAUVERSE\RemoteDesktopV1` while the app is stopped (documented; never silently reset by app).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F06 — Unbound FFI Fallback Can Report Successful Mutations
- **Finding ID:** `F06`
- **Severity:** `P1`
- **Root cause:** `DauverseNativeBridge.call` fell back to `_fallbackTestState` whenever `DynamicLibrary` failed to load in production, returning `{'ok': true, 'data': payload}` for generic commands, while `DauverseController` ignored `res['ok']` on mutations.
- **Affected source:** `flutter/lib/dauverse/bridge/dauverse_bridge.dart`, `flutter/lib/dauverse/dauverse_shell.dart`, `flutter/lib/dauverse/widgets/floating_toolbar.dart`, `flutter/lib/dauverse/screens/devices_and_session_screens.dart`, `flutter/lib/dauverse/screens/power_security_ops_screens.dart`, `flutter/test/dauverse_ui_test.dart`.
- **Implementation fix:** Made `DauverseNativeBridge` strictly **fail-closed (`ok: false`, `FFI_BACKEND_UNAVAILABLE_FAIL_CLOSED`)** unless `enableTestMockFallbackForTesting()` is explicitly invoked by `flutter/test/`; added `backendAvailable` / `backendError` checks on every controller mutation and a prominent red fail-closed banner in `DauverseShell` when FFI is unavailable.
- **Regression test:** `flutter/test/dauverse_ui_test.dart` (`All 16 DAUVERSE screens render cleanly...` with explicit test harness setup).
- **Negative test:** `flutter/test/dauverse_ui_test.dart`: `'F06 Negative Security Test: Production unbound FFI fails closed and blocks privileged mutations'` (verifies `ok == false` on `dashboard_snapshot`, `set_step_up_pin`, `power_action`, `revoke_all_access`, `headless_activate` and verifies red fail-closed banner renders).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/flutter_dauverse_ui_tests.log`, `LOGS/GITHUB_ACTIONS_BUILD_CONSOLE.log`.
- **Remaining risk:** None identified for unbound FFI fallback.
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F07 — Volatile Default `%TEMP%` Storage, Ignored Write Errors & In-Memory Settings
- **Finding ID:** `F07`
- **Severity:** `P2`
- **Root cause:** `DauverseRuntime::init_default` fell back to `std::env::temp_dir().join("dauverse_remote_v1")` when `DAUVERSE_DATA_DIR` was unset, selected journal/audit writes discarded I/O errors (`let _ = ...`), and trust allowlist / performance / clipboard / bandwidth settings lived only in RAM.
- **Affected source:** `src/dauverse/crypto_util.rs`, `src/dauverse/mod.rs`, `src/dauverse/security.rs`, `src/dauverse/notifications.rs`, `src/dauverse/session_tools.rs`, `src/dauverse/ffi.rs`.
- **Implementation fix:** Switched default storage to `default_durable_app_data_dir()` (`%LOCALAPPDATA%\DAUVERSE\RemoteDesktopV1` on Windows, `$XDG_DATA_HOME`/`~/.local/share/dauverse_remote_v1` on Unix); added `write_atomic_bytes` (`O_NOFOLLOW` temp + `write_all` + `sync_all` + `rename`); persisted `security_state.json`, `dauverse_settings_state.json`, `notifications_journal.json`, `session_tools_state.json`, `bridge_replay_journal.json`, and `security_audit_chain.jsonl` with explicit `Result` propagation and fail-closed corruption flags.
- **Regression test:** `dauverse::security::tests::f05_f07_...`, `dauverse::crypto_util::tests::atomic_write_and_confined_nofollow_rejects_symlink_swap`, and 2-process reopen verification in `TESTS/test_e2e_hooks_and_secrets.py` & `verify_and_package_windows_rc.ps1`.
- **Negative test:** Corrupted JSON/vault reopen test (`phase3_corrupt` -> fail-closed without silent reset) + symlink target rejection in `write_atomic_bytes`.
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json`.
- **Remaining risk:** Full OS reboot persistence and disk-full / ACL-denial fault injection on physical Windows workstation remain `BLOCKED` pending pilot guest execution.
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F08 — Service & Auto-Start Setters Lack Authoritative OS Synchronization
- **Finding ID:** `F08`
- **Severity:** `P2`
- **Root cause:** `set_auto_start` only mutated an in-memory bool, `configure_unattended` did not update `Config` `approve-mode` or refuse service collisions, and `refresh_windows_scm_status` promoted `"Running"` without demoting stopped/removed services.
- **Affected source:** `src/dauverse/service_ctrl.rs`, `src/dauverse/ffi.rs`, `flutter/lib/dauverse/screens/power_security_ops_screens.dart`.
- **Implementation fix:** Wired `set_auto_start` on Windows to write/delete `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\DauverseRemoteDesktop` via `winreg` and read back OS state; wired `configure_unattended` to check external service collision and persist `Config::set_option("approve-mode", ...)`; updated `refresh_os_state` to authoritatively promote AND demote `InstalledRunning`, `InstalledStopped`, and `NotInstalled`.
- **Regression test:** `dauverse::service_ctrl::tests::f03_f08_service_image_path_ownership_and_state_demotion` + Windows FFI `phase1` collision refusal test.
- **Negative test:** `configure_unattended(enabled=true)` refused when external `RustDesk` service exists (`phase1`).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/dauverse_unit_security_tests.log`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json`.
- **Remaining risk:** Live owned Windows Service registration/start and post-reboot unattended login remain `BLOCKED` by governance (no service started on host without Boss approval).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(Owned service start/reboot: `BLOCKED`)*

### F09 — Bounded 2,048 FIFO Replay Cache Evicts Within 5-Minute Validity Window
- **Finding ID:** `F09`
- **Severity:** `P2`
- **Root cause:** RC1 stored `(event_id, nonce)` entries in a 2,048-entry FIFO `VecDeque`, allowing 2,049 valid signed events within 5 minutes to evict entry #1 and permit replay within `MAX_CLOCK_SKEW_MS`.
- **Affected source:** `src/dauverse/ai_bridge.rs`.
- **Implementation fix:** Replaced FIFO eviction with time-windowed `ReplayGuardState` (`REPLAY_RETENTION_MS = 660_000` >= `2 * MAX_CLOCK_SKEW_MS`, pruning **only** expired entries, hard ceiling `MAX_ACTIVE_REPLAY_ENTRIES = 65_536` that fails closed with HTTP `429` `EVENT_REJECT_REPLAY_CACHE_SATURATED` instead of evicting unexpired keys) backed by durable `bridge_replay_journal.json`.
- **Regression test:** `dauverse::ai_bridge::tests::f09_replay_window_survives_over_2048_events_and_restarts`.
- **Negative test:** 2,100 legitimate events ingested at `t0` -> replay of event `#0` at `t0 + 1000ms` rejected + cross-process restart replay rejected (`HTTP 401`).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/dauverse_unit_security_tests.log`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` (`phase2.cross_restart_replay_http = 401`).
- **Remaining risk:** Sustained legitimate hook bursts exceeding `65,536` events within 11 minutes will receive fail-closed HTTP `429` until entries age past `660s`.
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F10 — Synthetic Target/Estimated FPS & Bitrate Reported as Live Telemetry
- **Finding ID:** `F10`
- **Severity:** `P2`
- **Root cause:** `PerformanceEngine::compute_telemetry` populated `fps` from `target_fps` and `bitrate_kbps` from a synthetic resolution formula whenever `connected == true`.
- **Affected source:** `src/dauverse/performance.rs`, `flutter/lib/dauverse/screens/dashboard_screen.dart`.
- **Implementation fix:** Replaced synthetic values with `measured_fps: Option<u32>` (`None` unless real transport counters are supplied via `compute_telemetry_with_measured`), `measured_bitrate_kbps: Option<u32>`, explicit `configured_target_fps`, `estimated_bitrate_cap_kbps`, and `telemetry_source_scope`; updated Dashboard KPI card to display `N/A (Cap X FPS)` when unmeasured.
- **Regression test:** `dauverse::performance::tests` + `flutter/test/dauverse_ui_test.dart`.
- **Negative test:** Verified `performance.fps == None` and `measured_fps == None` in live FFI (`TESTS/test_e2e_hooks_and_secrets.py` & `verify_and_package_windows_rc.ps1`).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/release_ffi_smoke_test.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json`.
- **Remaining risk:** End-to-end 2-PC frame/latency benchmarking across LAN/Internet remains `BLOCKED` pending a two-host pilot environment (Report §12).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(2-PC live benchmark: `BLOCKED`)*

### F11 — Rollback Quarantines Installation Before Validating Backup Integrity
- **Finding ID:** `F11`
- **Severity:** `P2`
- **Root cause:** `rollback_windows_release.ps1` moved `$InstallDir` to `$BrokenHold` and copied `$BackupDir` without verifying backup file hashes or PE headers beforehand and without restoring `$BrokenHold` if copy failed.
- **Affected source:** `installer/nsis/dauverse_setup.nsi`, `installer/nsis/dauverse_setup_helper.ps1`, `scripts/windows/rollback_windows_release.ps1`, `scripts/windows/verify_and_package_windows_rc.ps1`.
- **Implementation fix:** `dauverse_setup_helper.ps1` now writes `BACKUP_SHA256_MANIFEST.txt` covering every file in `.rollback_backup`; `rollback_windows_release.ps1` validates `BACKUP_SHA256_MANIFEST.txt` + `MZ`/`PE\0\0` headers **before** stopping services or moving `$InstallDir`, and wraps quarantine + copy + post-restore verification in a `try/catch` that automatically restores `$BrokenHold` on failure.
- **Regression test:** Distinct-sentinel (`PRE_UPGRADE_SENTINEL.json` vs `POST_UPGRADE_SENTINEL.json`) upgrade & rollback test in Stage `[5/7]` of `verify_and_package_windows_rc.ps1`.
- **Negative test:** Corrupted `PRE_UPGRADE_SENTINEL.json` in `.rollback_tampered_test` -> `rollback_windows_release.ps1` threw `ROLLBACK_VALIDATION_FAILED` while leaving active `$ExpectedInstallDir` untouched.
- **Evidence:** `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` (`distinct_sentinel_transactional_rollback_and_tamper_refusal = PASS`).
- **Remaining risk:** Cross-schema user profile downgrade migration across future major versions is `NOT TESTED` (V1.0 single schema).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F12 — Update Descriptor Signature Status Trusted From Caller Input
- **Finding ID:** `F12`
- **Severity:** `P2`
- **Root cause:** `verify_update_package` accepted caller-supplied `SignatureStatus::VerifiedTrustedPublisher` as ground truth after checking SHA-256 against caller-supplied `expected_sha256`.
- **Affected source:** `src/dauverse/update_center.rs`.
- **Implementation fix:** Added `inspect_artifact_publisher_signature` using confined no-follow SHA-256 (`sha256_file_confined_no_follow`), WinVerifyTrust / pinned publisher digest verification, and hard-override ignoring caller's `VerifiedTrustedPublisher` claim when no trusted publisher root/pin is configured (`effective_signature_status = Unsigned`, `safe_for_auto_update = false`).
- **Regression test:** `dauverse::update_center::tests`.
- **Negative test:** Unsigned artifact passed with `signature_status = "VERIFIED_TRUSTED_PUBLISHER"` -> downgraded to `UNSIGNED` with `safe_for_auto_update == false` in unit, Linux `.so`, and Windows DLL tests.
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json`.
- **Remaining risk:** Commercial Authenticode certificate is not purchased (`0 VNĐ` rule); auto-update remains permanently disabled (`UNSIGNED`).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F13 — Wake-on-LAN Sends UDP Packet Even During `dry_run_only`
- **Finding ID:** `F13`
- **Severity:** `P2`
- **Root cause:** `PowerOperation::WakeOnLan` in `src/dauverse/smart_power.rs` bound a UDP socket and broadcast a magic packet before checking `ctx.dry_run_only`.
- **Affected source:** `src/dauverse/smart_power.rs`.
- **Implementation fix:** Added `if ctx.dry_run_only` return (`executed: false`, `DRY_RUN_VALIDATED_NO_OS_SIDE_EFFECT`) at the start of `PowerOperation::WakeOnLan` after MAC format validation, before any socket bind or packet transmission.
- **Regression test:** `dauverse::smart_power::tests` (validates WoL dry-run returns `executed == false` with zero socket bind).
- **Negative test:** Dry-run `WAKE_ON_LAN` verified via FFI in Linux `.so` and Windows DLL without network transmission.
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json`.
- **Remaining risk:** Physical Wake-on-LAN wakeup of `ASUS PRIME H610M-K D4` requires two-host LAN test (`BLOCKED`).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F14 — Path Validation Precedes File Open (Reparse / Symlink Race Risk)
- **Finding ID:** `F14`
- **Severity:** `P2` *(Reported by Codex as unproven static TOCTOU risk — verified and hardened via confined handle checks)*
- **Root cause:** String/metadata path validation in `transfer_guard` preceded subsequent `File::create` / `rename` / hashing calls, leaving a theoretical TOCTOU window if a local attacker swapped a directory component with a symlink or NTFS junction.
- **Affected source:** `Cargo.toml`, `src/dauverse/crypto_util.rs`, `libs/base/src/fs.rs`, `src/dauverse/transfer_guard.rs`.
- **Implementation fix:** Added `open_no_follow_regular_file` and `sha256_file_confined_no_follow` using `O_NOFOLLOW` on Unix and `FILE_FLAG_OPEN_REPARSE_POINT` + `GetFinalPathNameByHandleW` prefix confinement on Windows (`winapi` `fileapi`), plus `create_download_file_no_follow` and pre-rename symlink/reparse verification in `libs/base/src/fs.rs`.
- **Regression test:** `dauverse::crypto_util::tests::atomic_write_and_confined_nofollow_rejects_symlink_swap` + `base::fs` unit tests.
- **Negative test:** Symlink escape inside `rx_confined/symlink_escape.txt` -> rejected during `transfer_finalize_receive` (`TESTS/test_e2e_hooks_and_secrets.py`).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/LINUX_PREFLIGHT/dauverse_unit_security_tests.log`.
- **Remaining risk:** Concurrent kernel-level NTFS oplock/junction race under adversarial local thread contention was `NOT TESTED` (requires dedicated lab race fuzzer; intermediate parent traversal on Windows still relies on component reparse checks + post-open `GetFinalPathNameByHandleW` confinement).
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(Concurrent NTFS junction race fuzzer: `NOT TESTED`)*

### F15 — Reproducibility Closure & Moving Toolchain Selection
- **Finding ID:** `F15`
- **Severity:** `P3`
- **Root cause:** `.github/workflows/dauverse-windows-build.yml` used floating `toolchain: stable`, unversioned `choco install nsis`, deprecated `Swatinem/rust-cache` Cache v1 SHA, shallow `fetch-depth: 1`, and emitted no structured `BUILD_PROVENANCE.json` mapping exact compiler/tool versions to output digests.
- **Affected source:** `.github/workflows/dauverse-windows-build.yml`, `scripts/windows/build_windows_release.ps1`, `scripts/windows/package_complete_rc2_qa_archive.ps1`.
- **Implementation fix:** Pinned `RUST_VERSION: "1.100.0"`, `FLUTTER_VERSION: "3.50.0"`, `LLVM_VERSION: "17.0.6"`, `VCPKG_COMMIT_ID: "9e593bb18ea69cc5095e012465dcd675a822ed0d"`, `nsis --version=3.10` fallback, `Swatinem/rust-cache@d1527c8f67ef9af357290475d4af4b0fab8f12e0` (`v2.9.3`), and `fetch-depth: 0`; emitted `BUILD_PROVENANCE.json` recording resolved `rustc -Vv`, `cargo -V`, `flutter --version --machine`, `clang --version`, `makensis /VERSION`, lockfile SHA-256s, and binary SHA-256s.
- **Regression test:** `verify_and_package_windows_rc.ps1` Stage `[1/7]` validates `BUILD_PROVENANCE.json` against `HEAD` and binary SHA-256 digests.
- **Negative test:** `BUILD_PROVENANCE.json` `rc_acceptance_eligible == false` / commit mismatch rejected by `verify_and_package_windows_rc.ps1`.
- **Evidence:** `RELEASE/BUILD_PROVENANCE.json`, `LOGS/GITHUB_ACTIONS_BUILD_CONSOLE.log`.
- **Remaining risk:** Bit-for-bit deterministic PE timestamps across separate MSVC linker invocations are not guaranteed by Windows MSVC/Flutter toolchains; provenance closure binds exact CI run -> resolved tool versions -> binary SHA-256s.
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)`

### F16 — File Receive Tracking Marks Completed Without Finalize Integrity Verification
- **Finding ID:** `F16`
- **Severity:** `P2`
- **Root cause:** `src/ui_cm_interface.rs` recorded `track_engine_receive_start` without expected file list/digests and marked `Completed` on `ipc::FS::WriteDone` before `remove_job` flushed/closed the file stream and without calling `finalize_and_verify` / computing actual received SHA-256 and byte counts.
- **Affected source:** `libs/base/src/fs.rs`, `src/ui_cm_interface.rs`, `src/dauverse/transfer_guard.rs`, `src/dauverse/ffi.rs`.
- **Implementation fix:** Added `TransferJob::flush_and_close_stream` in `libs/base/src/fs.rs` so `ipc::FS::WriteDone` flushes/syncs and closes the destination file handle **before** calling `verify_and_finalize_engine_receive`; tracked every file in batch jobs (`track_engine_receive_start_batch`), verified confined no-follow byte size + SHA-256 for every file on `WriteDone`, emitted `fs::new_error` and marked job `Failed` on missing/truncated/mismatched files, and labeled integrity mode truthfully (`SENDER_SHA256_VERIFIED` when sender digest supplied vs `LOCAL_SHA256_COMPUTED_SIZE_VERIFIED` when upstream wire protocol only carries byte size).
- **Regression test:** `dauverse::transfer_guard::tests::f16_batch_receive_verifies_every_file_size_and_sha256_and_fails_on_truncation` + `base::fs` tests.
- **Negative test:** Truncated file (`INTEGRITY_SIZE_MISMATCH`), wrong sender SHA-256 (`INTEGRITY_HASH_MISMATCH`), missing file, and symlink escape (`F14`) all fail finalization (`TESTS/test_e2e_hooks_and_secrets.py` & `verify_and_package_windows_rc.ps1`).
- **Evidence:** `EVIDENCE/LINUX_PREFLIGHT/rc2_security_negative_matrix.json`, `EVIDENCE/WINDOWS_RC_VERIFICATION_REPORT.json` (`phase2.f16_verified_mode = SENDER_SHA256_VERIFIED`).
- **Remaining risk:** Upstream RustDesk v1.5.3 wire protocol does not send per-file SHA-256 headers from standard unpatched peers; in that mode DAUVERSE enforces exact byte-length verification + confined local SHA-256 recording (`LOCAL_SHA256_COMPUTED_SIZE_VERIFIED`) over RustDesk's NaCl `secretbox` encrypted transport. Live 2-PC transfer remains `BLOCKED` pending two-host pilot.
- **Status:** `REMEDIATED (PENDING INDEPENDENT RE-QA)` *(2-PC live transfer: `BLOCKED`)*

---

## 3. Blocking Delivery & Provenance Observations (`A01`–`A04`)

| ID | Codex Observation | RC2 Remediation & Verification |
|---|---|---|
| **A01** | Final RC ZIP / `SETUP.exe` / `PORTABLE.exe` / manifest absent in reviewer's accessible delivery | Assembled and uploaded directly as downloadable GitHub Actions Artifact `DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA` (`DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip` + standalone `SETUP.exe`, `PORTABLE.exe`, `FINAL_HANDOFF_SHA256_MANIFEST.txt`). |
| **A02** | Incremental bundle failed `git bundle verify` in empty bare repo (`exit 1`); `usbmmidd_v2` license/member closure incomplete | Created full-history `BUNDLE/DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle` (`fetch-depth: 0`) verified inside a fresh empty `git init --bare` repo (`exit 0`); preserved `usbmmidd_v2/License.txt` (`44c73fc4...`) verbatim with `DRIVER_PROVENANCE_AND_LICENSE.json` and `THIRD_PARTY_NOTICES`. |
| **A03** | No authorized exact-RC guest / two-host execution | Single-host disposable `windows-2022` lifecycle & 3-process DPAPI/security matrix executed on exact RC2 bytes; two-host live session & physical GPU driver install remain honestly marked `BLOCKED` with step-by-step pilot protocol preserved in `QA/CODEX_REQA_WINDOWS_RC2_HANDOFF.md`. |
| **A04** | Complete source/submodules, DLLs, driver set, SBOM, original logs, and bidirectional manifest reconciliation needed | `package_complete_rc2_qa_archive.ps1` stages `RELEASE/`, `LOGS/`, `EVIDENCE/`, `QA/` (incl. untouched `f07b61ed...` report), `DOCS/`, `LICENSES/`, `BUNDLE/`, `SOURCE/` (with `libs/hbb_common`), and audits clean-room extraction (`0` missing, `0` mismatch, `0` unlisted files). |

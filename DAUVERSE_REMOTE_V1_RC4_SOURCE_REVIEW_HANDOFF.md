# DAUVERSE REMOTE DESKTOP V1 — RC4 SOURCE REVIEW HANDOFF

- **Task ID:** `DREMOTE-V1-RC4-FOCUSED-CLOSURE-011` (`PRIORITY: URGENT — FOCUSED SOURCE CLOSURE`)
- **Developer:** `ANTIGRAVITY CLOUD`
- **Independent Reviewer:** `CODEX`
- **Predecessor Verdict (`RC3`):** `FAIL_SOURCE_GATE` (`QA/DAUVERSE_REMOTE_V1_RC3_INDEPENDENT_SOURCE_QA_REPORT.md`)
- **Windows CI / Native Build Triggered for RC4:** `NONE (0 runs — strictly gated on Codex Targeted Independent Review + Boss Approval)`
- **DAUVERSE AI Impact:** `NONE (0 files / 0 endpoints touched)`
- **Cost Incurred:** `0 VNĐ`
- **Production Status:** `LOCKED`
- **FINAL STATUS:** **`READY_FOR_TARGETED_INDEPENDENT_REVIEW`**

---

## 1. Provenance, Pinned Commits & Low-Quota Review Instructions

| Item | Verified Value |
|---|---|
| **Repository** | `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP.git` |
| **Development Branch** | `develop/dauverse-remote-v1` (fast-forward push only; no `--force`, no tags, no releases, no merge to `main`/`master`) |
| **RC1 Baseline Commit** | `309948002371aba1407532c9ba8d9d216a02e771` |
| **RC2 Baseline Commit** | `0e1e3e87185159a481360b2c2b28f3dee541328f` (Windows CI Run `45720572543`) |
| **RC3 Pinned Baseline Commit (`HEAD~1`)** | `821f1dabbbe865930d1bd0676760956659533c15` |
| **RC4 Pinned Candidate Commit (`HEAD`)** | Single integrated closure commit at `HEAD` of `develop/dauverse-remote-v1` directly atop `821f1dabbbe865930d1bd0676760956659533c15` (`git rev-parse HEAD`; exact 40-hex SHA-1 and GitHub compare link `821f1dabbbe865930d1bd0676760956659533c15...<RC4_SHA>` are recorded externally in the handoff message so this tracked file avoids a self-referential Git SHA-1 cycle) |
| **Submodule (`libs/hbb_common`)** | `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb` (**untouched** — `0` submodule commits/diffs) |
| **Lockfiles (`Cargo.lock`, `flutter/pubspec.lock`)** | **Untouched** (`0` lines changed; zero new crates or packages) |
| **Codex RC1 Report (`QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md`)** | `f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913` (**EXACT MATCH**, `51,476` bytes) |
| **Codex RC2 Report (`QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md`)** | `c23d36e7d83b2fb1402238d8a8501b9de899fcd94b2774155b6a602fd77fb954` (**EXACT MATCH**, `66,814` bytes) |
| **Codex RC3 Report (`QA/DAUVERSE_REMOTE_V1_RC3_INDEPENDENT_SOURCE_QA_REPORT.md`)** | `d7bf8f93fde76a95cbfcc3c089018f607c9b7743c679a1b3f8c8d38ce98e61ad` (**EXACT MATCH**, `40,804` bytes, LF-locked via `.gitattributes`) |

### Targeted Low-Quota Review Commands (No Cloud ZIP Required)
To conserve Codex weekly quota (`<25%` remaining), all RC4 changes are delivered as **one narrow commit** directly on top of `821f1dabbbe865930d1bd0676760956659533c15`. The 10 findings already verified `CLOSED-SOURCE` in RC3 are untouched except for tightening internal `F01` signing helpers (`26` lines in `src/dauverse/ai_bridge.rs`):

```bash
git -c core.autocrlf=false -c core.eol=lf fetch origin develop/dauverse-remote-v1
git -c core.autocrlf=false -c core.eol=lf checkout --detach FETCH_HEAD
git rev-parse HEAD~1   # Expect: 821f1dabbbe865930d1bd0676760956659533c15
git submodule status   # Expect:  450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb libs/hbb_common
git diff --stat 821f1dabbbe865930d1bd0676760956659533c15..HEAD
git diff 821f1dabbbe865930d1bd0676760956659533c15..HEAD
```

---

## 2. Complete Disposition Matrix

### 2.1 RC3 Blocking Source Defects & Conditional Constraints (`FT010-B01`–`B05`, `FT010-Q01`–`Q03`)

| ID | Priority / Historical Mapping | Codex RC3 Finding | RC4 Source Closure | Targeted Regression Verification | RC4 Gate Status |
|---|---|---|---|---|---|
| **FT010-B01** | **P1** (`F02`) | `verify_and_package_windows_rc.ps1` excluded `INITIAL_BUILD_SHA256_MANIFEST.txt` from disk count (`1`) while final generator included it (`2`) | Added `New-ReleaseManifestLines -BaseDirectory <path> -ManifestRole <"Initial"\|"Final">` and `[ValidateSet("Auto","Initial","Final")][string]$ManifestRole = "Auto"` in `Assert-ManifestFileValid` (`scripts/windows/verify_and_package_windows_rc.ps1`, `scripts/windows/build_windows_release.ps1`); `Final` requires, hashes, and counts `INITIAL_BUILD_SHA256_MANIFEST.txt` | `TESTS/test_rc3_powershell_validators.py` (`ft010_b01_final_manifest_layout_verified`: positive `Count == 2` + negative missing-initial-manifest, rogue-extra, duplicate, and bad-hash rejections) | `SOURCE_REMEDIATED_RC4` |
| **FT010-B02** | **P1** (`F14`; affects `F16`) | Fresh upload `.download` opened with `create(true)` + `set_len(0)` without single-link check, truncating an outside hardlink victim (`43 -> 0` bytes); upload resume lacked single-link/`O_NOFOLLOW` check | Added `prepare_clean_exclusive_staging_slot` (read-only `links == 1` check **before** unlinking so preexisting hardlinks abort with `0` victim byte mutation) + `create_exclusive_staging_file_no_follow` (`create_new(true)` + `O_NOFOLLOW` / `FILE_FLAG_OPEN_REPARSE_POINT` + post-open handle `nNumberOfLinks == 1` & Windows final-path root confinement) across fresh upload `.download`, `.digest`, destination overwrite, upload resume, fresh download, and download resume (`libs/base/src/fs.rs`, `libs/base/src/fs/download.rs`) | `base::fs::tests::ft010_b02_fresh_and_resume_upload_staging_hardlinks_preserve_outside_victim_bytes` (exact 43-byte victim preserved byte-for-byte across fresh `.download`, `.digest`, and resume hardlinks) + `download_tests::f14_f16_download_refuses_hardlinked_staging_and_sha256_mismatch` (`27/27` `base` tests PASS) | `SOURCE_REMEDIATED_RC4` |
| **FT010-B03** | **P2** (`F08`) | `revoke_all_access` cleared wrapper map and stopped owned SCM service without revoking live `src/server/connection.rs` `Connection` sessions or waiting for disconnect ACK | Added `live_engine_registry()` + `LiveEngineConnectionGuard` (`Condvar` disconnect ACK) in `src/dauverse/service_ctrl.rs`, wired into `Connection::start` (`_dauverse_live_conn_guard`), `peer_keyboard_enabled`, `clipboard_enabled`, `audio_enabled`, `file_transfer_enabled`, `on_message`, `handle_input`, and `try_port_forward_loop` (`!self.is_dauverse_revoked()`, woken via `rx_from_cm.recv()`) (`src/server/connection.rs`), plus `kick_all_cm_clients_for_revoke` (`src/ui_cm_interface.rs`), `CheckIfRestart`, and synchronous `Data::DauverseEmergencyRevoke` IPC `--server` ACK (`src/ipc.rs`, `src/ipc/windows.rs`); owned SCM service (`before_owned == Some(true)`) is always stopped even if an earlier step errored, while external `owned == Some(false)` services remain untouched; timeouts/failures return `ok: false` with conservative access denial latched | `dauverse::service_ctrl::tests::ft010_b03_live_engine_connection_revoke_cuts_capabilities_disconnects_and_fails_on_timeout` + `server::connection::test::ft010_b03_real_engine_connection_capability_and_port_forward_cutoff_on_revoke` (`2/2` PASS) | `SOURCE_REMEDIATED_RC4` |
| **FT010-B04** | **P2** (`F07`, `F08`) | `ServiceController` relied on `Config::set_option` / `Config::get_option`, which updates `CONFIG2` in memory first and swallows `RustDesk2.toml` store/read errors | Added `read_durable_config2_at`, `commit_atomic_config2_file`, and `commit_security_config2_options_at` (`src/dauverse/service_ctrl.rs`), preserving `unlock_pin`, `trusted_devices`, `trusted_devices_v2`, and `socks` credentials in `Config2::file()` (`RustDesk2.toml`), committing atomically (`0o600` + `fsync` + `rename`) without `chmod`-overriding read-only parent dirs, rolling back in-memory `CONFIG2` on post-sync error when `!conservative_deny_on_error`, verifying fresh durable disk readback + `Config2::get_for_sync()`, and latching conservative access denial on failure | `dauverse::service_ctrl::tests::ft010_b04_durable_config2_persistence_fault_injection_and_credential_preservation` + `ft010_b04_rlimit_fsize_mid_write_subprocess_entry` (live `Config2::file()` under `RLIMIT_FSIZE` mid-write `EFBIG`, corrupt TOML, non-string `trusted_devices_v2`, `0o000` ACL, `0o500` parent dir, restart reload) | `SOURCE_REMEDIATED_RC4` |
| **FT010-B05** | **P2** (`F16`) | `TransferQueueManager` keyed jobs globally as `engine-fs-{id}`, conflated peers/directions/`conn_id=0`, verified outside lock without generation CAS, and ignored finalization errors before `Done` | Replaced global key with `EngineTransferIdentity { session_scope, conn_id > 0, direction, engine_job_id }` + monotonic `generation: u64` (`src/dauverse/transfer_guard.rs`); removed all unscoped helpers; enforced `commit_engine_job_with_cas` generation/status CAS; wired positive session identities in `src/ui_cm_interface.rs` (incl. `CancelWrite`, `WriteError`, `ReadFile`), `src/client/io_loop.rs` (incl. premature peer `Done` guard), and `src/dauverse/ffi.rs`; added `TransferJob::try_finalize_write_files() -> ResultType<()>` (`libs/base/src/fs.rs`) propagated before `verify_and_finalize_engine_receive_scoped` and `fs::new_done` | `dauverse::transfer_guard::tests::ft010_b05_concurrent_same_id_peers_directions_generations_and_race_isolation` (peer A corrupt fails while peer B valid passes on job ID `1`, opposite directions, reconnect supersede, cancel isolation, `conn_id=0` rejection, multi-thread race) + `TESTS/test_e2e_hooks_and_secrets.py` live `.so` C-ABI test | `SOURCE_REMEDIATED_RC4` |
| **FT010-Q01** | Constraint (`F02`) | `Assert-OriginalBuildLogValid` accepted synthetic 9-marker + padding text without compiler output; text logs alone do not prove CI execution | Updated `Invoke-Checked` (`scripts/windows/build_windows_release.ps1`) to pipe native stdout/stderr through `Write-Host` for `Start-Transcript`; hardened `Assert-OriginalBuildLogValid` to require ordered Cargo (`Finished \`release\` profile`) x2 and NSIS (`Output: "`) lines; added positive + complete-marker negative tests; documented mandatory cross-check against raw GitHub Actions provider logs when Windows CI is authorized | `TESTS/test_rc3_powershell_validators.py` (`ft010_q01_complete_marker_fabricated_log_rejected`) | `SOURCE_HARDENED` + Native CI Raw-Log Gate Retained |
| **FT010-Q02** | **P3** (`F15`) | Workflow `$ResolvedNsis` was process-local and not passed into `build_windows_release.ps1` | Exported `DAUVERSE_MAKENSIS_PATH` and passed `-MakensisPath "$RESOLVED_NSIS_WIN"` in `.github/workflows/dauverse-windows-build.yml`; added `Resolve-PinnedMakensisExecutable` + immediate pre-invocation `v3.11` check in `scripts/windows/build_windows_release.ps1` | `TESTS/test_rc3_powershell_validators.py` (`ft010_q02_pinned_makensis_resolution_verified`: wrong-PATH `v3.10` vs alternative `v3.11`, explicit wrong-version rejection, no-exact-version failure) | `SOURCE_REMEDIATED_RC4` |
| **FT010-Q03** | Compatibility Policy (`F16`) | Wire-additive `FileEntry.sha256` intentionally rejects legacy senders without SHA-256, while legacy receivers do not return cryptographic receipts and `ipc::FS::NewWrite` / Hook V3 require coordinated restart | Preserved fail-before-write `INTEGRITY_REJECT_MISSING_SENDER_SHA256` for legacy senders; changed outbound `UploadToRemote` `Done` to record `SENDER_STREAM_EOF_CHECKED_UNVERIFIED_RECEIVER` (`verified_sha256: None`, never `SENDER_SHA256_VERIFIED`, and rejecting premature peer `Done` while local `read_jobs` is active); documented homogeneous RC4-to-RC4 pilot & coordinated upgrade/restart requirement | `dauverse::transfer_guard::tests::ft010_b05` (outbound `Done` unverified-receiver status + missing-SHA pre-write rejection) | `SCOPED_AND_ENFORCED` |

### 2.2 Historical `F01`–`F16` + `N01` Disposition (10 Preserved `CLOSED-SOURCE` + 7 Split Clearly Between Source Closure vs. Native Pilot)

| ID | Sev | RC3 Independent Disposition | RC4 Source Disposition | Remaining Native Windows / Pilot Verification (No Native PASS Claimed) |
|---|---|---|---|---|
| **F01** | **P1** | `CLOSED-SOURCE` (internal signer qualification noted) | `CLOSED-SOURCE (PRESERVED + SIGNER TIGHTENED)` — added `sign_event_envelope_checked`, switched `sign_with_runtime_secret` to checked `Result`, gated raw helpers to `#[cfg(test)]` | Windows DLL execution in approved pilot |
| **F02** | **P1** | `OPEN/PARTIAL` (`B01` + `Q01`) | `SOURCE_REMEDIATED_RC4` (`B01` closed; `Q01` transcript capture + validator hardened) | Authorized Windows CI build + raw GitHub Actions run logs + PE/DLL negative checks |
| **F03** | **P1** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — external `owned == Some(false)` services strictly skipped by SCM & IPC revoke | Live running external `RustDesk` Windows service coexistence pilot |
| **F04** | **P1** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — `HeadlessOperationalStatus` & `WDKTestCert` block intact | Physical monitorless GPU driver activation, capture & reboot pilot |
| **F05** | **P1** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — dedicated vault/PIN fail-closed persistence intact | Windows DPAPI, multi-profile ACL & OS reboot pilot |
| **F06** | **P1** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — `dart.vm.product` compile-time guard intact (`flutter_all_tests.log`: `187 passed, 1 skipped`) | Compiled Windows release GUI wrong-DLL / missing-export banner check |
| **F07** | **P2** | `OPEN/PARTIAL` (`B04`) | `SOURCE_REMEDIATED_RC4` (`B04` atomic durable `RustDesk2.toml` commit + credential preservation + fault injection) | Native Windows ACL, disk-full & OS reboot persistence pilot |
| **F08** | **P2** | `OPEN/PARTIAL` (`B03` + `B04`) | `SOURCE_REMEDIATED_RC4` (`B03` real `Connection` cutoff/disconnect ACK + `B04` durable `Config2` + conservative deny latch) | Native Windows portable + owned-SCM live session cutoff & reboot pilot |
| **F09** | **P2** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — strict replay journal (`HTTP 503` on corrupt/unreadable state) intact | Multi-process writer, crash atomicity & Windows reboot pilot |
| **F10** | **P2** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — unmeasured `measured_fps` stays `None` | 2-PC LAN/WAN FPS, latency & RTX 3060 NVENC pilot |
| **F11** | **P2** | `PARTIAL-NATIVE` | `PARTIAL-NATIVE (SOURCE HARDENED)` — bidirectional backup closure preserved; single-build Stage `[6/7]` & JSON/MD reports explicitly labeled `SIMULATED_BINARY_OVERLAY` / `PASS_SIMULATED_BINARY_OVERLAY_PARTIAL_NATIVE` | Distinct two-release (`Release A -> Release B -> Rollback A`) Windows installer upgrade/rollback pilot |
| **F12** | **P2** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — Authenticode / thumbprint check & unsigned auto-update refusal intact | Commercial publisher PKI / revocation pilot (`0 VNĐ` unsigned policy) |
| **F13** | **P2** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — zero-packet dry-run WoL & `DisabledSmartPlugAdapter` intact | Physical LAN Wake-on-LAN & host sleep/shutdown pilot |
| **F14** | **P2** | `OPEN/PARTIAL` (`B02` `P1`) | `SOURCE_REMEDIATED_RC4` (`B02` exclusive no-follow single-link staging across fresh & resume upload/download) | Native Windows NTFS hardlink/junction/ADS stress; kernel oplock race remains unverified |
| **F15** | **P3** | `OPEN/PARTIAL` (`Q02`) | `SOURCE_REMEDIATED_RC4` (`Q02` exact NSIS `3.11` path propagation & pre-invocation enforcement; `6` `.ps1` files PS 5.1 clean) | Authorized Windows CI build & provenance verification |
| **F16** | **P2** | `OPEN/PARTIAL` (`B02` + `B05` + `Q03`) | `SOURCE_REMEDIATED_RC4` (`B05` full `EngineTransferIdentity` + `generation` CAS + `try_finalize_write_files`, `B02` staging confinement, `Q03` scoping) | Homogeneous RC4-to-RC4 2-PC Windows transfer/resume/tamper & coordinated upgrade restart pilot |
| **N01** | **P2** | `CLOSED-SOURCE` | `CLOSED-SOURCE (PRESERVED)` — microsecond `hmac_event_sign_us` precision intact (`200` iterations) | Local microbenchmark only (not end-to-end transport latency) |

---

## 3. Root-Cause & Blocker Closure Evidence (`FT010-B01`–`B05`, `Q01`–`Q03`, `F01`)

### 3.1 `FT010-B01` (`P1`, `F02`) — Initial vs. Final Manifest Counting Parity
- **Root Cause:** `Assert-ManifestFileValid` in `scripts/windows/verify_and_package_windows_rc.ps1` hardcoded `$ExcludedNames = @("sha256_manifest.txt", "initial_build_sha256_manifest.txt")` when counting disk files, whereas Stage `[7/7]` generated final `SHA256_MANIFEST.txt` excluding only `SHA256_MANIFEST.txt` (`2` manifest lines vs. `1` counted disk file).
- **Closure Implementation:**
  - `scripts/windows/verify_and_package_windows_rc.ps1`: Added `New-ReleaseManifestLines -BaseDirectory <path> -ManifestRole <"Initial"|"Final">` (`Initial` excludes both manifest filenames; `Final` excludes only `sha256_manifest.txt`) and updated `Assert-ManifestFileValid` with `[ValidateSet("Auto", "Initial", "Final")][string]$ManifestRole = "Auto"` (`Auto` resolves `"Initial"` for `INITIAL_BUILD_SHA256_MANIFEST.txt` and `"Final"` for `SHA256_MANIFEST.txt`). When `$EffectiveRole -eq "Final"`, `INITIAL_BUILD_SHA256_MANIFEST.txt` is counted on disk, required in `$Seen`, and SHA-256 verified; all mutable verification transcripts (`$TempVerifyLog`) are stopped and copied into `$ReleaseDir` **before** `New-ReleaseManifestLines -ManifestRole "Final"` runs.
  - `scripts/windows/build_windows_release.ps1`: Step 11 writes `INITIAL_BUILD_SHA256_MANIFEST.txt` first (excluding both manifest names) and then writes `SHA256_MANIFEST.txt` including `INITIAL_BUILD_SHA256_MANIFEST.txt` so build output already conforms to the `Final` layout.

### 3.2 `FT010-B02` (`P1`, `F14`/`F16`) — Exclusive Single-Link Staging & Pre-Unlink Victim Protection
- **Root Cause:** Fresh upload in `libs/base/src/fs.rs` (`TransferJob::write`) opened `.download` with `create(true)` + `FILE_FLAG_OPEN_REPARSE_POINT` and truncated via `set_len(0)` without verifying `nNumberOfLinks == 1`. An NTFS/POSIX hardlink is a regular file (`!reparse`) whose opened path resolves inside the allowed root while mutating its out-of-root alias (`43 -> 0` bytes). Similarly, `set_stream_offset` on upload resume lacked `O_NOFOLLOW` / `FILE_FLAG_OPEN_REPARSE_POINT` and single-link validation, and unconditionally unlinking a preexisting `.download`/`.digest` without checking `links == 1` first could silently sever or replace links without rejecting the attack.
- **Closure Implementation:**
  - `libs/base/src/fs.rs`:
    * `open_readonly_no_follow_single_link` & `verify_std_handle_single_link_regular_confined`: Opens read-only with `O_NOFOLLOW` (Unix) / `FILE_FLAG_OPEN_REPARSE_POINT` (Windows), verifies regular non-reparse metadata, Windows `GetFinalPathNameByHandleW` confinement against `pre_captured_canon_root`, and `nNumberOfLinks == 1` (`GetFileInformationByHandle` on Windows / `MetadataExt::nlink` on Unix).
    * `prepare_clean_exclusive_staging_slot`: Inspects any preexisting staging file via `open_readonly_no_follow_single_link` **before** calling `remove_file` — if `links > 1`, reparse, or symlink, it aborts immediately without truncating or unlinking, leaving the out-of-root victim 100% byte-identical.
    * `create_exclusive_staging_file_no_follow` & `write_exclusive_digest_file_no_follow`: After `prepare_clean_exclusive_staging_slot`, opens exclusively via `create_new(true)` + `O_NOFOLLOW` / `FILE_FLAG_OPEN_REPARSE_POINT` and re-verifies `verify_std_handle_single_link_regular_confined` on the opened handle before returning or writing bytes (`0` check-then-reopen window).
    * `ensure_destination_safe_for_overwrite`: Rejects preexisting hardlinked/reparse destination targets before staging write and before final `rename`.
    * `set_stream_offset` & `resume_failed_err`: Enforces `O_NOFOLLOW` / `FILE_FLAG_OPEN_REPARSE_POINT` + handle confinement + `links == 1` on upload resume, and guards `.download`/`.digest` cleanup so hardlinked staging artifacts are never deleted on error.
  - `libs/base/src/fs/download.rs`: Routed `start_download_file`, `resume_download` (including `.digest` read-only single-link check), and `finish_download` through the same exclusive single-link helpers.

### 3.3 `FT010-B03` (`P2`, `F08`) — Live Engine Session Revocation & Observable Disconnect ACK
- **Root Cause:** `revoke_all_access` cleared `DeviceShield`'s wrapper map and stopped an owned SCM service, leaving live `src/server/connection.rs` `Connection` instances (portable sessions, active input/clipboard/audio/file-transfer/port-forward loops) active with cached per-connection flags.
- **Closure Implementation:**
  - `src/dauverse/service_ctrl.rs`: Added `live_engine_registry()` (`Mutex<HashMap<u64, LiveEngineConnectionEntry>>` + `Condvar`), `register_live_engine_connection`, `LiveEngineConnectionGuard` (exposing `LiveEngineConnectionGuard::is_revoked` and whose `Drop` removes the entry and `notify_all()`s the `Condvar`), and `revoke_all_local_engine_connections(timeout)` (sets `revoked = true`, zeroes all per-connection permission flags, sends `ipc::Data::Close`, kicks CM clients via `kick_all_cm_clients_for_revoke`, fails active transfer ledger entries, and blocks on `Condvar::wait_timeout` until all live `Connection` guards drop or returns `Err("ENGINE_REVOKE_DISCONNECT_TIMEOUT: ...")`).
  - `src/server/connection.rs`: Registered `_dauverse_live_conn_guard` inside `Connection::start`; gated `peer_keyboard_enabled`, `clipboard_enabled`, `audio_enabled`, `file_transfer_enabled`, `on_message`, `handle_input`, and `try_port_forward_loop` (woken immediately on revoke via `rx_from_cm.recv()` receiving `Data::Close`) on `!self.is_dauverse_revoked()`; blocked new connections while `is_conservative_access_denied()` is latched until `configure_unattended` explicitly re-authorizes access.
  - `src/ipc.rs`, `src/ipc/windows.rs`, & `src/dauverse/service_ctrl.rs`: Added `Data::DauverseEmergencyRevoke(Option<Result<usize, String>>)` holding `CheckIfRestart::new()` and handled on `--server` via `spawn_blocking(execute_in_process_server_emergency_revoke)`, invoked from non-server callers via synchronous `BytesCodec` framing (`request_local_server_ipc_revoke_sync` — zero nested Tokio runtime or `block_on`, authenticated on Windows via `CLIENT_ACCESS = FILE_GENERIC_READ | FILE_WRITE_DATA` + `ensure_raw_pipe_server`), stopping owned (`before_owned == Some(true)`) Windows SCM `RustDesk` even when earlier steps errored while strictly skipping IPC/SCM stop when an external non-owned (`owned == Some(false)`) service collision is detected (`F03` preserved).

### 3.4 `FT010-B04` (`P2`, `F07`/`F08`) — Atomic Durable `Config2` (`RustDesk2.toml`) Persistence
- **Root Cause:** `Config::set_option` in pinned `libs/hbb_common` updates `CONFIG2` in memory first and calls `.store()`, which swallows read-for-store and disk write errors; `Config::get_option` reads the mutated in-memory `CONFIG2`, reporting false success when `RustDesk2.toml` failed to persist.
- **Closure Implementation:**
  - `src/dauverse/service_ctrl.rs` (`read_durable_config2_at`, `commit_atomic_config2_file`, `commit_security_config2_options_at`):
    * Kept `libs/hbb_common` untouched (`450cc1d`).
    * Checks `OVERWRITE_SETTINGS` policy conflicts first; reads existing `Config2::file()` (`RustDesk2.toml`) strictly from disk via `open_no_follow_regular_file` (`ErrorKind::NotFound` -> clean seed; stat/ACL/UTF-8/TOML/schema error or non-string `trusted_devices_v2` -> `Err` + `set_conservative_access_denied(true)` when `conservative_deny_on_error` is set).
    * Updates only the target `options` entries in the parsed TOML document while explicitly preserving existing `unlock_pin`, `trusted_devices`, `trusted_devices_v2`, and `socks` fields byte-for-byte without re-encoding or clearing credentials on failure.
    * Commits atomically via `.RustDesk2.toml.tmp.<uuid>` (`create_new` + `0o600` + `O_NOFOLLOW` + `sync_all` + `rename`, respecting read-only `0o500` parent directories without `chmod`-overriding them).
    * When targeting live `Config2::file()`, snapshots `prev_mem_options = Config2::get().options` before `Config::set_option`, re-commits the atomic fsynced document, verifies fresh durable disk readback via `read_durable_config2_at` plus pinned API readback via `Config2::get_for_sync()`, and rolls back `Config::set_options(prev_opts)` if any post-sync step fails while `!conservative_deny_on_error`.
    * Wired into `ServiceController::status`, `configure_unattended`, `revoke_all_access_immediately`, `set_clipboard_policy`, and `DauverseRuntime::dashboard_snapshot` (`storage_healthy`).

### 3.5 `FT010-B05` (`P2`, `F16`), `FT010-Q03`, & `F01` Tightening
- **`FT010-B05` Full Identity Ledger & Finalization Error Propagation:**
  - `src/dauverse/transfer_guard.rs`: Replaced `engine-fs-{id}` with `EngineTransferIdentity { session_scope, conn_id > 0, direction, engine_job_id }` (`storage_key` + per-generation `job_id` = `engine-{session_scope}-{dir_tag}-c{conn_id}-j{engine_job_id}-g{generation}`) and monotonic `generation: u64` on `TransferJob`. Removed all unscoped helpers. Verification snapshots `(job_snapshot, expected_generation)` and commits solely via `commit_engine_job_with_cas(&key, expected_generation, ...)` (`INTEGRITY_STALE_GENERATION_OR_CANCELLED` if superseded or cancelled concurrently). Reused keys in active state mark the prior generation superseded in audit history and allocate a fresh `generation` without inheriting peer/bytes/root from any other connection or direction.
  - `libs/base/src/fs.rs` & `src/ui_cm_interface.rs`: Added `pub fn try_finalize_write_files(&self) -> ResultType<()>` on `base::fs::TransferJob` (keeping `pub fn modify_time(&self)` as a thin wrapper for untouched callers) and called it in `ipc::FS::WriteDone` **before** `verify_and_finalize_engine_receive_scoped` and `fs::new_done`, propagating any staging SHA-256, confinement, or `rename` error as `fs::new_error`. Also wired `job.conn_id` into `CancelWrite`/`WriteError` and enforced `make_cm_transfer_identity` mismatch/positive checks on `ReadFile`.
  - `src/client/io_loop.rs` & `src/dauverse/ffi.rs`: Assigned unique per-`Remote` `dauverse_scope_id` (`client-sess-{}-r{}`) and positive `dauverse_round` across all client transfer paths, guarded outbound `Done` against premature peer `Done` while `read_jobs` is still active, and required positive `conn_id` + `session_scope` in FFI commands `"transfer_track_receive"` / `"transfer_finalize_receive"`.
- **`FT010-Q03` Outbound `Done` Honesty:** `track_engine_transfer_finish_scoped` for `TransferDirection::UploadToRemote` sets `integrity_status = "SENDER_STREAM_EOF_CHECKED_UNVERIFIED_RECEIVER"` with `verified_sha256 = None` (never claiming cryptographic receiver verification without a receiver receipt), while keeping `INTEGRITY_REJECT_MISSING_SENDER_SHA256` fail-closed before write for incoming transfers.
- **`F01` Signer Qualification:** `src/dauverse/ai_bridge.rs` added `canonical_signing_bytes_checked` / `sign_event_envelope_checked`, changed `AiEventBridge::sign_with_runtime_secret` to return `Result<SignedAiEventEnvelope, String>`, updated `src/dauverse/ffi.rs`, and gated raw unchecked `canonical_signing_bytes` / `sign_event_envelope` to `#[cfg(test)]`.

---

## 4. Targeted Regression Summary & Mandatory Regression-Surface Report

### 4.1 Executed Verification Suites (RC4)

| Suite | Command | Result | Evidence File |
|---|---|---|---|
| **Base FS & Staging Confinement (`FT010-B02`, `F14`, `F16`)** | `cargo test --locked -p base --lib` | **PASS (`27 passed; 0 failed; 0 ignored`)** | `ARTIFACTS/evidence/rc2_base_fs_tests.log` |
| **Real Engine Connection Cutoff (`FT010-B03`)** | `cargo test --locked --features linux-pkg-config --lib ft010_b03` | **PASS (`2 passed; 0 failed` — `service_ctrl` + `server::connection::test`)** | Verified in RC4 test pipeline |
| **DAUVERSE Unit & Security Suite (`B03`, `B04`, `B05`, `F01`–`N01`)** | `cargo test --locked --features linux-pkg-config --lib dauverse::` | **PASS (`33 passed; 0 failed; 0 ignored`)** | `ARTIFACTS/evidence/dauverse_unit_security_tests.log` |
| **PowerShell 5.1 AST & Validators (`B01`, `Q01`, `Q02`, `F11`, `F01`)** | `python3 TESTS/test_rc3_powershell_validators.py` | **PASS (`6` `.ps1` files `0` PS7 tokens; `B01`, `Q01` pos+neg, `Q02`, `F11`, `F01` checks all `true`)** | `TESTS/test_rc3_powershell_validators.py` |
| **Release `.so` Build + 4-Process E2E & Secret Scan (`B05`, `F01`, `F09`, `N01`)** | `cargo build --locked --features linux-pkg-config --release --lib && python3 TESTS/test_e2e_hooks_and_secrets.py` | **PASS (`phase1`, `phase2` incl. `FT010-B05` C-ABI isolation, `phase3_corrupt`, `phase4_corrupt_replay -> HTTP 503`, `PASS_ZERO_SECRETS` across `1,197` files)** | `ARTIFACTS/evidence/{ai_bridge_and_secret_scan.json,rc2_security_negative_matrix.json,release_ffi_smoke_test.json,benchmark_results.json}` |
| **Reused Unchanged Flutter Suites (`F06`)** | Unchanged `flutter/` tree from RC3 (`0` Dart diffs) | **`dauverse_ui_test.dart`: `5 passed`; `flutter_all_tests.log`: `187 passed, 1 skipped`** | `ARTIFACTS/evidence/flutter_dauverse_ui_tests.log` |

### 4.2 Mandatory Regression-Surface Report (`AGENTS.md`)
Every modified file outside `src/dauverse/` was audited for minimal invasiveness:
1. **`libs/base/src/fs.rs`, `libs/base/src/fs/download.rs`, `libs/base/src/fs/download_tests.rs`:** Strictly required by `FT010-B02` (exclusive single-link no-follow `.download`/`.digest` staging and upload/download resume protection) and `FT010-B05` (`try_finalize_write_files() -> ResultType<()>`). Existing `pub fn modify_time(&self)` is preserved as a thin wrapper for untouched callers.
2. **`src/server/connection.rs`:** Thin hooks registering `_dauverse_live_conn_guard` in `Connection::start`, gating capability checks (`peer_keyboard_enabled`, `clipboard_enabled`, `audio_enabled`, `file_transfer_enabled`, `on_message`, `handle_input`, `try_port_forward_loop`) on `!self.is_dauverse_revoked()`, and adding 1 regression test (`ft010_b03_real_engine_connection_capability_and_port_forward_cutoff_on_revoke`). Normal session behavior when revoke is inactive is unchanged.
3. **`src/ipc.rs` & `src/ipc/windows.rs`:** One new `Data::DauverseEmergencyRevoke` enum variant + handler arm (with `CheckIfRestart::new()`) in `src/ipc.rs` and a thin `#[cfg(windows)] pub(crate) fn ensure_raw_pipe_server` helper in `src/ipc/windows.rs` reusing existing Windows Named Pipe server authentication for `FT010-B03`.
4. **`src/ui_cm_interface.rs` & `src/client/io_loop.rs`:** Required by `FT010-B03` (`kick_all_cm_clients_for_revoke`) and `FT010-B05` (scoping transfer ledger calls by positive connection/session identity, guarding premature peer `Done`, and checking `try_finalize_write_files()` before `fs::new_done`). Non-generic jobs (`JobType::Printer`, Android document URIs) remain bypassed.
5. **`.github/workflows/dauverse-windows-build.yml` & `scripts/windows/*.ps1`:** Required by `FT010-B01` (`Initial` vs `Final` manifest closure), `FT010-Q01` (`Invoke-Checked` transcript capture + `Assert-OriginalBuildLogValid` compiler/NSIS output verification), `FT010-Q02` (`-MakensisPath` exact `v3.11` propagation), `F11` (`SIMULATED_BINARY_OVERLAY` wording in JSON and Markdown), and RC3 report SHA-256 gating.

---

## 5. Internal Cross-Review Results

- **Reviewer Context & Honest Identity Disclosure:** Conducted via an independent read-only `research` subagent context (conversation ID `2e0e53708c239ace7f12d547ee7e56b3`) using `Model: inherit` (same platform model as developer context; no external model routing used or spoofed; `0 VNĐ` cost). Internal review does **not** replace Codex Independent QA.
- **Findings Raised by Independent Reviewer Subagent & Resolved Before Commit:**
  1. **`[P1]` `FT010-Q01` PowerShell `Start-Transcript` Native Output Capture (`scripts/windows/build_windows_release.ps1`, `TESTS/test_rc3_powershell_validators.py`):** PowerShell `Start-Transcript` does not capture unpiped native `cargo.exe` stderr (`Finished \`release\` profile`) or `makensis.exe` stdout (`Output: "`). Updated `Invoke-Checked` to pipe `& $Command 2>&1 | ForEach-Object { Write-Host "$_" }` with `$ErrorActionPreference = "Continue"` and `$PSNativeCommandUseErrorActionPreference = $false` restored in `finally`, and added both positive and exact-9-banner negative tests in `test_rc3_powershell_validators.py`.
  2. **`[P2]` `FT010-B03` Owned SCM Stop Under Prior Step Error & `--server` Mediator Restart (`src/dauverse/service_ctrl.rs`, `src/ipc.rs`, `src/ipc/windows.rs`):** Changed `os_action_err.is_none()` to `before_query_err.is_none()` on `stop_owned_windows_scm_service("RustDesk")` so an owned (`before_owned == Some(true)`) Windows service is stopped even when an earlier revoke step errors (still strictly skipping external `Some(false)`/`None`), added `CheckIfRestart::new()` on `Data::DauverseEmergencyRevoke(None)`, and hardened Windows Named Pipe client access (`FILE_GENERIC_READ | FILE_WRITE_DATA` + `ensure_raw_pipe_server`).
  3. **`[P2]` `FT010-B04` In-Memory `CONFIG2` Rollback & Live `Config2::file()` `RLIMIT_FSIZE` Test (`src/dauverse/service_ctrl.rs`):** Added `prev_mem_options` rollback when a post-sync check fails with `!conservative_deny_on_error`, respected read-only `0o500` parent directories in `commit_atomic_config2_file`, and updated `ft010_b04_rlimit_fsize_mid_write_subprocess_entry` to exercise `ServiceController` against live `Config2::file()` under `ScopedPinnedAppName`.
  4. **`[P2/P3]` `FT010-B05` Edge Cases (`src/ui_cm_interface.rs`, `src/client/io_loop.rs`):** Passed `removed_job` `conn_id` in `CancelWrite`/`WriteError`, validated `make_cm_transfer_identity` in `ReadFile`, and rejected premature peer `FileResponse::Done` while `self.read_jobs` still holds an unfinished upload.
  5. **`[P3]` Report JSON `F11` Wording & Handoff Identifier Parity (`scripts/windows/verify_and_package_windows_rc.ps1`, `DAUVERSE_REMOTE_V1_RC4_SOURCE_REVIEW_HANDOFF.md`):** Updated `WINDOWS_RC_VERIFICATION_REPORT.json` to `schema_version = 4` (`RC4`) and `simulated_binary_overlay_rollback_helper_and_tamper_unlisted_refusal = "PASS_SIMULATED_BINARY_OVERLAY_PARTIAL_NATIVE"`, gated `verify_post_revoke_os_truth` under `#[cfg(test)]` (`0` RC4 compiler warnings), and verified all symbol names and `SHA256_MANIFEST.txt` entries.

---

## 6. Remaining Native Windows Verification (Controlled Pilot Scope — Not Claimed as PASS)

The following items require native Windows / multi-host hardware execution and are **not** claimed as `PASS` in this source handoff:
1. **Windows Native Build, Protobuf Codegen, Flutter Windows AOT & NSIS `v3.11` Packaging (`F02`, `F06`, `F15`):** Compilation of `#[cfg(windows)]` Rust paths (`GetFinalPathNameByHandleW`, `GetFileInformationByHandle`, Windows Named Pipe `ensure_raw_pipe_server`, `windows_service` SCM stop), `DAUVERSE_REMOTE.exe` / `librustdesk.dll` missing-export & wrong-DLL banner diagnostics, final `SHA256_MANIFEST.txt` closure (`FT010-B01`), and raw GitHub Actions provider run-log cross-checking (`FT010-Q01`).
2. **Native Windows Live Session Cutoff & Service Coexistence (`F03`, `F08`, `FT010-B03`):** Live portable and owned-SCM `RustDesk` sessions under concurrent keyboard/clipboard/file-transfer/port-forward traffic during emergency revoke, plus coexistence with an actively running external non-owned `RustDesk` service.
3. **Native Windows Durable Storage & Fault Injection (`F05`, `F07`, `F09`, `FT010-B04`):** DPAPI vault, NTFS ACL denial, disk-full, multi-profile isolation, crash atomicity, and Windows OS reboot persistence of `RustDesk2.toml` and replay journals.
4. **Windows NTFS Confinement & Two-Peer Homogeneous RC4 File Transfer (`F14`, `F16`, `B02`, `B05`, `Q03`):** Live Windows NTFS hardlink/junction/ADS negative tests (noting kernel-level oplock/path-swap stress remains outside unit proof), homogeneous RC4-to-RC4 two-PC LAN/WAN transfers in both directions (files, folders, empty dirs, skipped files, resume, cancel, same-size tamper, duplicate job IDs), and coordinated service/CM/hook restart on upgrade.
5. **Distinct Two-Release Installer A/B Upgrade & Rollback (`F11`):** Stage `[6/7]` single-build `.dll` marker append remains explicitly classified as `SIMULATED_BINARY_OVERLAY` (`PARTIAL-NATIVE`); full `F11` acceptance requires distinct Release A -> Release B upgrade -> Rollback A execution, B-only file removal, and restored-A launch verification.
6. **Hardware / Governance-Locked Pilots (`F04`, `F10`, `F12`, `F13`):** Monitorless virtual display driver activation/reboot, 2-PC RTX 3060 NVENC FPS/latency measurement, commercial Authenticode signing/revocation, and physical LAN Wake-on-LAN / smart-plug testing.

---

## 7. Windows Build Readiness Checklist

| Gate Item | RC3 State | RC4 State |
|---|---|---|
| **B01:** Final Windows package manifest generator & validator parity | FAIL (`Count 2 != 1`) | **READY** (`New-ReleaseManifestLines` + `Assert-ManifestFileValid -ManifestRole Final` verified) |
| **Q02:** Exact NSIS `v3.11` executable propagated from workflow into build | PARTIAL (`$ResolvedNsis` local) | **READY** (`-MakensisPath` + `Resolve-PinnedMakensisExecutable` enforced pre-invocation) |
| **Q01:** Build transcript captures toolchain output & rejects complete-marker fabricated text | PARTIAL (marker-only accepted) | **READY** (`Invoke-Checked` pipes native output + Cargo/NSIS lines required + pos/neg tests; raw CI log gate documented) |
| **B02–B05:** Confinement, live revoke, durable `Config2`, & transfer identity | OPEN (`4` blockers) | **READY** (All `4` remediated at source with targeted positive + negative regressions) |
| **10 Closed-Source Findings (`F01,F03–F06,F09,F10,F12,F13,N01`)** | `CLOSED-SOURCE` | **PRESERVED** (`+ F01` internal signer tightened) |
| **PowerShell 5.1 Syntax Across All 6 Scripts** | Verified | **READY** (`0` parse errors, `0` PS7 tokens) |
| **Windows CI Execution Status** | Not run | **HELD — Awaiting Codex Targeted Review & Boss Approval** |

---

## 8. SHA-256 Manifest Verification

Selective source, QA report, script, and evidence digests are recorded in root `SHA256_MANIFEST.txt` and `ARTIFACTS/SHA256_MANIFEST.txt` (including `QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md`, `QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md`, `QA/DAUVERSE_REMOTE_V1_RC3_INDEPENDENT_SOURCE_QA_REPORT.md`, and this handoff `DAUVERSE_REMOTE_V1_RC4_SOURCE_REVIEW_HANDOFF.md`):

```bash
sha256sum -c SHA256_MANIFEST.txt
sha256sum -c ARTIFACTS/SHA256_MANIFEST.txt
```

**FINAL STATUS: `READY_FOR_TARGETED_INDEPENDENT_REVIEW`**

**Production `LOCKED`. Zero Windows CI runs triggered. Zero `DAUVERSE AI` impact. Zero cost incurred.**

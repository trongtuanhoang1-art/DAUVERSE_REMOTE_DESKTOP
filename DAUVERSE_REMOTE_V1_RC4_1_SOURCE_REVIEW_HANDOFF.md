# DAUVERSE REMOTE DESKTOP V1 — RC4.1 SOURCE REVIEW HANDOFF & CARBON IMPLEMENTATION REPORT

- **Task ID:** `DREMOTE-V1-RC4.1-FAST-TRACK-013` (`PRIORITY: CRITICAL URGENT`)
- **Phase 1 Developer:** `GEMINI CARBON HIGH` (`ANTIGRAVITY CLOUD`)
- **Phase 2 Independent Reviewer Context:** `Antigravity Isolated Read-Only Subagent (Model tier: "pro" — per Boss explicit routing authorization; not spoofing Gemini Neon High)`
- **Predecessor Baseline (`RC4`):** `980373472ae17b869f273b7544336b133ca3ce86`
- **Input Claude RC4 QA Report:** `QA/DAUVERSE_REMOTE_V1_RC4_CLAUDE_QA_REPORT.md` — SHA-256: `38c30b6515532a031c0a9ea630581f592f2c006f1b67c79ef06a4ba508fb714d` (**VERIFIED EXACT**, `17,734` bytes)
- **Windows CI Triggered:** `NONE (0 runs — strictly gated on Boss approval)`
- **DAUVERSE AI Impact:** `NONE (0 files / 0 endpoints touched)`
- **Cost Incurred:** `0 VNĐ`
- **Production Status:** `LOCKED`

---

## 1. Provenance & Minimal Delta Scope (`RC4` -> `RC4.1`)

| Item | Verified Value |
|---|---|
| **Repository / Branch** | `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP` — `develop/dauverse-remote-v1` |
| **Pinned Parent Baseline (`RC4`)** | `980373472ae17b869f273b7544336b133ca3ce86` (`HEAD` during pre-commit Phase 2 review; `HEAD~1` once the single RC4.1 closure commit is recorded) |
| **RC4.1 Candidate Delta** | Single narrow closure delta directly atop `980373472ae17b869f273b7544336b133ca3ce86` (exact 40-hex commit SHA-1 and GitHub compare URL are recorded externally upon commit so this tracked file avoids self-referential hash cycles) |
| **Submodule (`libs/hbb_common`)** | `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb` (**untouched**) |
| **Lockfiles (`Cargo.lock`, `flutter/pubspec.lock`)** | **Untouched** (`0` lines changed) |
| **Production Code Files Touched in `RC4 -> RC4.1`** | **1 file only:** `libs/base/src/fs.rs` (`RC4-N01` fix + bidirectional resume regression test; all `src/`, `flutter/`, `installer/`, `scripts/`, and `.github/` files from verified RC4 remain **100% untouched**) |
| **Preserved In-Repo Independent QA Reports (`-text` LF-locked)** | RC1 (`f07b61ed...`), RC2 (`c23d36e7...`), RC3 (`d7bf8f93...`), and RC4 Claude (`38c30b6515532a031c0a9ea630581f592f2c006f1b67c79ef06a4ba508fb714d`). Phase 2's RC4.1 Independent QA Report is delivered externally alongside the commit handoff so `SHA256_MANIFEST.txt` remains strictly non-self-referential |

---

## 2. Phase 1 Carbon Implementation — `RC4-N01` Root Cause, Fix & Test-First Proof

### 2.1 Root Cause (`RC4-N01`, `P2` — `libs/base/src/fs.rs`, `TransferJob::set_stream_offset`)
In RC4 (`980373472`), `TransferJob::set_stream_offset` selected writer-staging resume vs. reader-source resume using `if !self.is_remote && (.download || .digest)` / `else if self.is_remote && file_path.exists()`. However, `self.is_remote` does **not** identify writer vs. reader role:
- Client upload sender (`src/client/io_loop.rs` `SendFiles`) constructs a **reader** via `TransferJob::new_read(..., false /* is_remote */, ...)`.
- Host `Connection` direct download sender (`src/server/connection.rs` `ReadFile`) constructs a **reader** via `TransferJob::new_read(..., false /* is_remote */, ...)`.
- Host CM upload receiver (`src/ui_cm_interface.rs` `NewWrite`) constructs a **writer** via `TransferJob::new_write(..., false /* is_remote */, ...)`.

Consequently, when resuming at `OffsetBlk(offset > 0)`, any reader with `is_remote == false` skipped the reader branch, left `self.data_stream` unseeked at byte `0` (or opened a stray `<file>.download` in write mode if one existed locally), and streamed from byte `0` instead of `offset` — causing receiver size/SHA-256 verification to reject the resumed transfer.

### 2.2 Surgical Fix (`libs/base/src/fs.rs`)
1. Added explicit role field `#[serde(skip)] is_write_job: bool` on `TransferJob` (constructed exclusively via `TransferJob::new_write` -> `is_write_job: true` and `TransferJob::new_read` -> `is_write_job: false`).
2. Branched `TransferJob::set_stream_offset` strictly on `self.is_write_job`:
   - **Writer branch (`self.is_write_job == true`):** Preserves 100% of `FT010-B02` invariants (`capture_confined_transfer_root`, `open_readonly_no_follow_single_link` on `.digest`, `O_NOFOLLOW` / `FILE_FLAG_OPEN_REPARSE_POINT` open on `.download`, `verify_std_handle_single_link_regular_confined` `links == 1`, `opened.metadata()?.len() == offset`, and `self.resume_failed_err = Some(...)` on missing/unsafe staging).
   - **Reader branch (`!self.is_write_job`):** Regardless of `self.is_remote` and ignoring any stray `<file>.download`/`.digest` alongside the source file, rejects symlink/reparse swaps (`is_existing_symlink_or_reparse`), opens `file_path` read-only via `File::open`, validates `meta.is_file() && offset <= meta.len()`, seeks to `offset`, updates `transferred` / `finished_size`, and clears `self.data_stream = None` on any open/metadata/seek error so `read()` fails closed instead of silently streaming from byte `0`. At EOF, `read()` continues to verify full-file sender SHA-256 (`libs/base/src/fs.rs:1646`, `verify_staging_file_sha256`).

### 2.3 Pre-Fix `FAIL` -> Post-Fix `PASS` Bidirectional Regression Proof
- **Pre-Fix `FAIL` on Unmodified RC4 (`980373472ae17b869f273b7544336b133ca3ce86`):**
  Executing `cargo test --locked -p base --lib rc4_n01` before editing production lines failed deterministically (`PRE_FIX_EXIT_CODE=101`):
  `assertion left == right failed: client upload reader (is_remote=false) must seek to offset 24 on resume (left: 0, right: 24)`.
- **Post-Fix `PASS` on RC4.1 (`ARTIFACTS/evidence/rc2_base_fs_tests.log`):**
  `cargo test --locked -p base --lib` -> **`28 passed; 0 failed; 0 ignored`** (`0` compiler warnings in `base`), covering:
  1. **Client -> Host Upload Resume (`new_read(is_remote=false)` -> `new_write(is_remote=false)` at `OffsetBlk(24)`):** Reader seeks to `24`, streams exact remaining `40` bytes, `try_finalize_write_files()` verifies SHA-256 and publishes the exact `64`-byte file.
  2. **Host `Connection` -> Client Download Resume (`new_read(is_remote=false)` + stray sender `.download`/`.digest` -> `new_write(is_remote=true)` at `OffsetBlk(29)`):** `download_digest` reports `NeedConfirm(29)`, reader seeks to `29` without touching stray sender `.download`, `finish_download()` verifies SHA-256 and publishes exact `64`-byte file.
  3. **Host `CM` -> Client Download Resume (`new_read(is_remote=true)` -> `new_write(is_remote=true)` at `OffsetBlk(37)`):** End-to-end resume + SHA-256 verification passes.
  4. **`FT010-B02` Confinement Preserved:** `ft010_b02_fresh_and_resume_upload_staging_hardlinks_preserve_outside_victim_bytes` (`43`-byte victim untouched across fresh `.download`, `.digest`, and resume hardlinks) and `download_tests::f14_f16_download_refuses_hardlinked_staging_and_sha256_mismatch` pass unchanged.

---

## 3. Evaluation of Claude's Non-Blocking Observations (`N02`–`N07`)

| ID | Claude Observation | RC4.1 Disposition |
|---|---|---|
| **N02** (`P3` evidence) | `server::connection::test::ft010_b03_...` was not captured in a committed `.log` file because `dauverse::` filter excluded `server::connection` | **RESOLVED:** Executed `cargo test --locked --features linux-pkg-config --lib ft010_b03` (`2 passed; 0 failed`) and committed verbatim output at `ARTIFACTS/evidence/rc4_ft010_b03_connection_tests.log` (tracked in `SHA256_MANIFEST.txt`). |
| **N03** (`P3` doc/FFI) | RC4 handoff overstated that FFI `transfer_track_receive` / `transfer_finalize_receive` required explicit `conn_id`, whereas FFI defaults omitted `conn_id` to `1` (`"ffi-conn-1"`) | **RESOLVED (Documentation Corrected, Zero Production Churn):** Real Rust engine paths (`ui_cm_interface.rs`, `client/io_loop.rs`) always supply explicit positive per-connection/session identities; the C-ABI FFI test harness in `src/dauverse/ffi.rs` defaults omitted `conn_id` to `1` (`"ffi-conn-1"`) for existing E2E test callers while rejecting explicit `conn_id <= 0` via `EngineTransferIdentity::validate()`. Keeping `src/dauverse/ffi.rs` untouched preserves Claude §6 Acceptance #3 (minimal delta). |
| **N04** (`P3`) | When `!conservative_deny_on_error` fails after initial atomic write in `commit_security_config2_options_at`, memory rolls back while disk holds the written value (revoke path uses `conservative=true` and is unaffected) | **DOCUMENTED KNOWN LIMIT:** Per `AGENTS.md` corner-case rules and §6 Acceptance #3, `src/dauverse/service_ctrl.rs` (`B04` `CLOSED-SOURCE`) is left untouched; attempting a second compensating disk write during an active readback/sync fault risks secondary I/O failure, and emergency revoke always runs with `conservative_deny_on_error = true`. |
| **N05** (`P3` style) | `handle_input` block indentation in RC4 (`src/server/connection.rs`); `verify_staging_file_sha256` wrapper note | **NO CHURN:** `src/server/connection.rs` (`B03` `CLOSED-SOURCE`) is left untouched in RC4.1 so the `RC4 -> RC4.1` delta remains minimal; `verify_staging_file_sha256` is actively invoked in production at `libs/base/src/fs.rs:1646` (`0` dead-code warnings in `base`). |
| **N06 / N07** (`P3` / `info`) | `"RC2"` in workflow cache key / archive script name; `"Finished \`release\` profile"` tied to pinned Rust `1.100.0`; flat `ReleaseDir` recursion | **NO CHURN:** Preserving `prefix-key: dauverse-win-x64-rc2` avoids invalidating the Windows CI Cargo cache; Rust toolchain is pinned to `RUST_VERSION: "1.100.0"` in `.github/workflows/dauverse-windows-build.yml:33`; `RELEASE/` is flat by design. |

---

## 4. Source Gate Summary & Windows Build Readiness Proposal

- **Phase 2 Model Routing & Honest Identity Disclosure:** Per Boss's explicit Phase 2 directive, independent delta QA runs in a separate read-only `research` subagent context configured with **`Model: "pro"`** (`Gemini Neon High` direct routing is not exposed as a distinct model selector on this platform; actual tier `Model: "pro"` is recorded truthfully without spoofing). The Phase 2 reviewer's standalone report is delivered externally alongside the commit handoff without modifying any manifest-tracked repository file post-review.
- **Source Gate Summary Across All Historical & RC3/RC4 Items:**
  - `B01`–`B05`, `Q02`, `Q03`, `F01`: `CLOSED-SOURCE` (verified by Claude in RC4, untouched in RC4.1).
  - `Q01`: `SOURCE_HARDENED` (raw GitHub Actions run-log cross-check required when Windows CI executes).
  - `RC4-N01`: `SOURCE_REMEDIATED` in RC4.1 (`libs/base/src/fs.rs`, verified by pre-fix `FAIL` -> post-fix `PASS` `28/28` `base` tests).
  - `F11`: `PARTIAL-NATIVE` (`SIMULATED_BINARY_OVERLAY` in single-build harness; distinct A->B->A pilot required for native closure).
- **Windows Build Readiness Proposal (Developer Assessment — Subject to Phase 2 Verdict & Boss Approval):** Candidate is technically ready for **01 controlled Windows CI build** (`workflow_dispatch` on `develop/dauverse-remote-v1`, currently **NOT** triggered). Remaining unverified native items (`#[cfg(windows)]` MSVC compilation/link, NTFS hardlink/reparse/ACL runtime behavior, live portable/SCM session cutoff, 2-PC RC4.1<->RC4.1 transfer/resume, distinct A/B rollback, raw GitHub Actions log cross-check) belong to the controlled Windows build & native pilot phase.

# DAUVERSE REMOTE DESKTOP V1 — RC4.2 MINIMAL HOTFIX & TARGETED QA HANDOFF

- **Task ID:** `DREMOTE-V1-RC4.2-BUILD-RECOVERY-015` (`PRIORITY: CRITICAL URGENT`)
- **Phase 1 Developer:** `GEMINI CARBON HIGH` (`ANTIGRAVITY CLOUD`)
- **Phase 2 Targeted Reviewer Context:** `Antigravity Isolated Read-Only Subagent (Model tier: "pro" — honest model tier disclosure; not spoofing Gemini Neon High)`
- **Predecessor Baseline (`RC4.1`):** `800443eacba6cf77bec7068cea569c5f8a72ba5d`
- **Failed Windows CI Run Input:** `45854069899` (`https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/actions/runs/45854069899`, Job `140027709052`)
- **DAUVERSE AI Impact:** `NONE (0 files / 0 endpoints touched)`
- **Cost Incurred:** `0 VNĐ`
- **Production Status:** `LOCKED`

---

## 1. Provenance & Minimal Delta Scope (`RC4.1` -> `RC4.2`)

| Item | Verified Value |
|---|---|
| **Repository / Branch** | `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP` — `develop/dauverse-remote-v1` |
| **Pinned Parent Baseline (`RC4.1`)** | `800443eacba6cf77bec7068cea569c5f8a72ba5d` |
| **RC4.2 Candidate Delta** | Single minimal compiler hotfix delta directly atop `800443eacba6cf77bec7068cea569c5f8a72ba5d` (exact 40-hex commit SHA-1 recorded externally upon commit to avoid self-referential manifest cycles) |
| **Submodule (`libs/hbb_common`)** | `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb` (**untouched**) |
| **Lockfiles (`Cargo.lock`, `flutter/pubspec.lock`)** | **Untouched** (`0` lines changed) |
| **Production Code Files Touched in `RC4.1 -> RC4.2`** | **1 file only:** `src/dauverse/service_ctrl.rs` (`2 insertions(+), 1 deletion(-)` inside `#[cfg(all(target_os = "windows", not(test)))]` in `ServiceController::revoke_all_access_immediately`) |
| **Preserved In-Repo Independent QA Reports (`-text` LF-locked)** | RC1 (`f07b61ed...`), RC2 (`c23d36e7...`), RC3 (`d7bf8f93...`), and RC4 Claude (`38c30b6515532a031c0a9ea630581f592f2c006f1b67c79ef06a4ba508fb714d`) — all **100% untouched** |

---

## 2. Root Cause from Raw CI Log (`45854069899`) & Surgical Hotfix

### 2.1 Raw Compiler Diagnostic (`rustc 1.100.0` `x86_64-pc-windows-msvc`)
In GitHub Actions Run `45854069899`, `dylib_virtual_display` (`--release`) and crate `base` (`libs/base`, including `FT010-B02` and `RC4-N01` Windows code) compiled cleanly (`0` errors). Crate `rustdesk` (`--features flutter,hwcodec,vram --lib --release`) finished full type-checking and borrow-checking with **literally 1 error**:

```text
error[E0382]: borrow of moved value: `before_query_err`
    --> src\dauverse\service_ctrl.rs:1169:16
     |
1087 |             before_query_err,
     |             ---------------- move occurs because `before_query_err` has type `std::option::Option<std::string::String>`, which does not implement the `Copy` trait
...
1141 |             let mut os_action_err: Option<String> = first_error.or(before_query_err);
     |                                                                    ---------------- value moved here
...
1169 |             if before_query_err.is_none()
     |                ^^^^^^^^^^^^^^^^ value borrowed here after move

error: could not compile `rustdesk` (lib) due to 1 previous error; 9 warnings emitted
```

### 2.2 Surgical Fix (`src/dauverse/service_ctrl.rs:1141,1170`)
Inside `#[cfg(all(target_os = "windows", not(test)))]` in `ServiceController::revoke_all_access_immediately`:
1. Added `let before_query_ok = before_query_err.is_none();` (`bool`, `Copy`) immediately before `let mut os_action_err: Option<String> = first_error.or(before_query_err);` (avoiding any `.clone()` allocation per `AGENTS.md`).
2. Replaced `if before_query_err.is_none()` with `if before_query_ok` at the owned SCM service stop guard (`line 1170`).

**Behavioral Invariance Proof:**
- `before_query_err` is bound at line `1087` and never mutated before line `1170`, so `before_query_ok` has the exact same truth value as `before_query_err.is_none()`.
- `os_action_err` still receives `first_error.or(before_query_err)` unchanged, so `if before_run_present || os_action_err.is_some()` (`line 1144`) still attempts `HKCU\...\Run\DauverseRemoteDesktop` deletion even when initial registry/SCM inspection errored (`FT010-B03` / `FT010-B05`).
- External `RustDesk` SCM service protection (`F03`: `before_query_ok && before_owned == Some(true) && before_svc_state != ServiceRunState::Stopped`) is 100% preserved.

---

## 3. Audit of Related Windows Branches & Honest Pre-CI Compile-Check Boundary

1. **Audit of All Related `#[cfg(...windows...)]` & `#[cfg(test)]` Branches:**
   - `src/dauverse/service_ctrl.rs`: Inspected all Windows blocks (`request_local_server_ipc_revoke_sync`, `query_owned_scm_service_state`, `query_windows_service_ownership_and_run_state_detailed`, `status`, `set_auto_start`, `revoke_all_access_immediately`, `stop_owned_windows_scm_service`, and `#[cfg(test)]` `status` arm `let _ = run_present;`). Zero other post-move borrows or `#[cfg(all(target_os = "windows", test))]` type mismatches exist (`before_run_present: bool`, `before_owned: Option<bool>`, `before_svc_state: ServiceRunState` are all `Copy`; `after_query_err` is consumed once at line `1196`).
   - `libs/base/src/fs.rs` & `libs/base/src/fs/download_tests.rs`: `libs/base` `--lib --release` already compiled with `0` errors on `x86_64-pc-windows-msvc` in Run `45854069899`; `#[cfg(windows)]` test blocks (`create_dir_link_or_junction_for_test`, `set_files_rejects_unc_absolute_path`, `rename_file_rejects_invalid_new_name`, `download_rejects_windows_streams_and_ambiguous_components`) and portable `ft010_b02` / `rc4_n01` tests verified clean.
   - `scripts/windows/verify_and_package_windows_rc.ps1`: Verified with real `pwsh` `Start-Transcript` that ANSI color sequences (`CARGO_TERM_COLOR=always`) are stripped by PowerShell 7 `Start-Transcript`, so `Assert-OriginalBuildLogValid` (`FT010-Q01`) matches `Finished \`release\` profile` without churning verified script files.
2. **Pre-CI Compile-Check & Explicit Environment Limitation (No Synthetic Windows PASS Claimed):**
   - **Isolated `rustc --target=x86_64-pc-windows-msvc` Borrow-Check Proof (`PASS`):** Executed real `rustc --edition=2021 --target=x86_64-pc-windows-msvc --crate-type=lib --emit=metadata` on the exact `revoke_all_access_immediately` move/borrow pattern: pre-fix reproduced `error[E0382]: borrow of moved value: before_query_err` (`exit 1`), post-fix succeeded cleanly (`exit 0`, `0` diagnostics).
   - **Full Workspace Cross-Target Check Limitation (`NOT_FEASIBLE_ON_LINUX_DEVBOX`):** Attempting full `cargo check --target x86_64-pc-windows-msvc` or `x86_64-pc-windows-gnu` on this Ubuntu 24.04 Linux environment stops inside third-party C/C++ `build.rs` scripts (`cc-rs` requires Windows MSVC `lib.exe`/SDK for `-msvc`; `libsodium-sys` autotools `configure` rejects `--host=x86_64-pc-windows-gnu`, and Windows `vcpkg` `x64-windows-static` libraries `libvpx`/`libyuv`/`opus`/`aom` are Windows-runner artifacts). Therefore, **no full Windows compile PASS is claimed locally**; actual Windows `x86_64-pc-windows-msvc` compilation, linking, testing, and packaging are verified strictly by Phase 3 Windows CI.
   - **Targeted Native Linux Regression Suites (`PASS`):** `dauverse::` unit & security tests (`ARTIFACTS/evidence/dauverse_unit_security_tests.log`), `base` unit & resume tests (`28/28`), and PowerShell validator suite (`TESTS/test_rc3_powershell_validators.py`) all pass cleanly.

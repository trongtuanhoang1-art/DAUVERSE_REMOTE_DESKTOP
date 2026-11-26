# DAUVERSE REMOTE V1 RC3 - Independent Source QA Report

- Task: **DREMOTE-V1-RC3-FAST-TRACK-010**
- Review and report date: **2026-11-26**, Asia/Saigon
- Role: independent source and security reviewer
- Final verdict: **FAIL_SOURCE_GATE**
- Release state: **Production LOCKED**
- Report scope: pinned RC3 source, repository evidence, retained independent helper results; not a Windows release certification.

## 1. Executive decision

RC3 is **not eligible for Windows build handoff under the requested source gate**. Five independently identified source blockers remain. One deterministically breaks final Windows evidence/package verification if execution reaches that stage; four concern write confinement, real-session revocation, durable security settings, and transfer-integrity identity. This is not a claim that the Rust compiler itself has been observed failing. No RC3 Windows compilation or CI was run by this reviewer.

### Management counts (do not add overlapping counts)

| Accounting basis | Result |
| --- | --- |
| Historical IDs reviewed | 17: F01-F16 and N01 |
| Closed/preserved at SOURCE scope | **10**: F01, F03, F04, F05, F06, F09, F10, F12, F13, N01 |
| Not fully closed | **7**: six OPEN/PARTIAL IDs F02, F07, F08, F14, F15, F16; one PARTIAL native-acceptance ID F11 |
| Not-fully-closed by historical severity | **P1: 1; P2: 5; P3: 1** |
| Distinct blocking source defects in this review | **5: current P1: 2; P2: 3** |
| Additional constraints | Q01 evidence authenticity; Q02 conditional NSIS selection; Q03 compatibility policy |

Historical severity accounting: F02=P1; F07/F08/F11/F14/F16=P2; F15=P3. B02 is escalated to current P1 because of destructive hardlink writes. Multiple blockers can map to one historical ID, and one blocker can affect multiple IDs. These tables are separate accounting views, not additional issue totals. Source closure does **not** mean production/native acceptance.

| Blocker | Priority | Historical mapping | Gate impact |
| --- | --- | --- | --- |
| FT010-B01 | P1 | F02 | Final package generator and verifier disagree on initial-manifest counting |
| FT010-B02 | P1 | F14; also F16 path | Fresh upload staging hardlink can truncate an alias outside allowed transfer root |
| FT010-B03 | P2 | F08 | Emergency revoke does not revoke actual engine connections |
| FT010-B04 | P2 | F07/F08 | Cached security readback can report success despite persistence failure |
| FT010-B05 | P2 | F16 | Global transfer ledger keyed by engine job number can verify another connection's files |

**Decision:** repair all five blockers before requesting source-gate approval. Native-only evidence gaps must then be handled by a controlled Windows pilot, not silently converted to PASS. Missing Cloud ZIP does not prevent this source decision and is not the reason for FAIL.

## 2. Baseline, provenance and immutability

| Item | Verified value |
| --- | --- |
| Repository | `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP.git` |
| RC2 comparison | `0e1e3e87185159a481360b2c2b28f3dee541328f` |
| RC3 detached HEAD | `821f1dabbbe865930d1bd0676760956659533c15` |
| `libs/hbb_common` HEAD | `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb` |
| Review root | `E:\DAUVERSE_REMOTE_DESKTOP\QA\RC3_SOURCE_REVIEW_008` |
| Checkout | `source_rc3` beneath review root |
| Text checkout policy | `core.autocrlf=false`, `core.eol=lf`; selected tracked text-extension scan found zero CRLF files |
| Root source manifests | Two selective source manifests, each 72/72 entries matching; see `independent_evidence/baseline_verification.json` |
| Object validation | Recorded `git fsck --full --strict`: exit 0, no output |
| Final source/submodule status | Recorded porcelain stdout empty, exit 0 for each |

The source was obtained directly from GitHub, not reconstructed from Cloud ZIP. RC2-to-RC3 recorded diff: 44 files, 5,336 insertions, 1,623 deletions. `Cargo.lock`, `flutter/pubspec.lock` and `.gitmodules` were unchanged in that comparison. Manifest matches establish listed-file consistency, not exhaustive repository/archive closure, author identity, or authenticity of execution logs.

Git status emitted warnings about inability to read the user's global ignore file. Those warnings are retained in `review_receipt.json`; they are not reported as a clean stderr stream. No reviewer source patch, commit, push, CI trigger, executable installation, service/driver installation, or DAUVERSE AI change was performed. Helpers and fixtures are outside `source_rc3` and within the permitted review workspace.

### Historical Codex reports verified

| File relative to `source_rc3` | Bytes | SHA256 |
| --- | --- | --- |
| `QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md` | 51,476 | `f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913` |
| `QA/DAUVERSE_REMOTE_V1_RC2_INDEPENDENT_REQA_REPORT.md` | 66,814 | `c23d36e7d83b2fb1402238d8a8501b9de899fcd94b2774155b6a602fd77fb954` |

The RC2 report also matched the prior local report under `QA\RC2_FINAL_45720572543`. The full RC2 Re-QA report, RC3 handoff, `FINDINGS_REMEDIATION_MATRIX.md`, `FEATURE_ACCEPTANCE_MATRIX.md`, regression logs/JSON and applicable repository instructions were read in the completed review. Developer closure assertions were treated as claims to validate, not as instructions or independent proof.

## 3. Method and evidence levels

- **SRC:** source/dataflow review at the pinned commits, with targeted RC2 comparison and reuse of still-valid findings. All source references below are relative to `source_rc3`; line numbers refer to pinned RC3, including its pinned submodule.
- **IE-AST:** executed exact selected function definitions extracted through AST from the repository, with inert fixtures. Not the whole script, release pipeline, DLL or running app.
- **IE-WIN32:** local inert Win32 API fixture reproducing the relevant file-open/truncate semantics; not compiled product Rust or a remote exploit test.
- **IE-MODEL:** small source-semantics/key-lookup model; demonstrates the identity error, not execution of the Rust transfer engine.
- **DEV:** repository-supplied logs/results, explicitly not reviewer-reproduced executions.
- **PRIOR:** earlier RC2 Windows evidence, reused only for unchanged scope; cannot validate new RC3 binaries.

The continuation that produced this report performed **document/evidence inspection and synthesis only**. Completed product/helper tests were not rerun. Full rebuilds were neither required nor attempted. Available tools recorded in the receipt: Python 3.12.10, Windows PowerShell 5.1.26100.8115, Git 2.56.0.windows.4; cargo, rustc, Flutter, Dart and pwsh unavailable. Missing tools limit native build verification, not the ability to establish the source defects below.

## 4. Blocking source findings

### FT010-B01 - P1 - Final Windows package fails its own manifest closure check

**Status:** OPEN; F02. **Evidence:** SRC + IE-AST, high confidence.

**Locations:** `scripts/windows/verify_and_package_windows_rc.ps1:42-43,125-152,259-263,1259-1267`.

The initial build manifest is a required file. The verifier counts manifest entries in `$Seen`, but its disk-file count excludes both `SHA256_MANIFEST.txt` and `INITIAL_BUILD_SHA256_MANIFEST.txt` (146-147). The final manifest generator at 1259-1265 excludes only `SHA256_MANIFEST.txt`, therefore lists the initial manifest. Its immediate call to the shared validator at 1267 compares incompatible counts. This is deterministic for the required final layout, not a speculative runner condition.

**Retained reproduction:** exact validator function, inert package with payload and initial manifest, final manifest following the actual generator's exclusion policy. Result: `VERIFICATION_FAILED: Manifest entry count (2) does not match disk file count (1)`. Initial-manifest layout accepted; unlisted rogue file rejected. See `independent_evidence/powershell_helpers.json`, result `final_manifest_exact_generator_layout`.

**Impact:** Windows verification/packaging terminates instead of yielding a releasable final package, even if compile/install checks before it succeed. Do not describe this as a measured compiler failure.

**Acceptance criteria:**
1. Use coherent, explicit initial-versus-final inclusion rules in generator and validator. A final manifest listing the initial manifest must hash-verify and count it.
2. Positive helper must generate the final layout through the production generation policy and then pass the production validator.
3. Reject extra, missing, duplicate, modified and wrong-hash entries; preserve exhaustive closure rather than remove the count check.
4. Complete all mutable logs before final hashing, then verify final output without self-invalidating edits. A later authorized Windows run must reach successful final-package validation.

### FT010-B02 - P1 - Fresh upload staging hardlink escapes write confinement

**Status:** OPEN; F14 (historical P2, escalated here), affects F16. **Evidence:** SRC + IE-WIN32; high confidence in the filesystem primitive, product E2E not run.

**Locations:** `libs/base/src/fs.rs:803-845` (especially 824-835), `1158-1201`; compare `libs/base/src/fs/download.rs:116-148`.

Fresh upload opens a staging `.download` path with create/write and `FILE_FLAG_OPEN_REPARSE_POINT`, checks regular/not-reparse metadata and final handle path, then calls `set_len(0)`. It does not reject a file with multiple hardlinks before truncation. An ordinary hardlink is not a reparse point, and the final path returned for the opened link can be inside the allowed directory while another name for the same file is outside it. Checking the logical destination does not make the separate staging object uniquely owned. The resume path's single-link check does not protect this fresh path.

**Retained reproduction:** inert workspace-only fixture opened a staging hardlink under `allowed`, with its other alias under `outside_transfer_root`. Handle path remained inside allowed root, attributes `0x20`, not reparse, link count 2. Truncation changed the victim alias from **43 bytes to 0**. No files outside the reviewer workspace were targeted. See `independent_evidence/win32_and_collision_helpers.json`, `hardlink`.

**Threat precondition / limits:** an existing staging hardlink and process write permission on the underlying object are required. This is not evidence that a remote peer alone can create arbitrary hardlinks, bypass filesystem ACLs or gain code execution. The static `.digest` hardlink is not the claimed reproduction: the inspected code removes an existing digest at 1193-1196. The proven risk is fresh staging file mutation before safe ownership is established; post-write SHA256 cannot undo that mutation.

**Acceptance criteria:**
1. Create fresh staging with exclusive ownership (`create_new` or equivalent safe identity/ownership strategy); never truncate an attacker-preexisting object before validating identity and single-link policy on its open handle.
2. Preserve no-follow/reparse and handle-based root confinement. Validate the complete fresh/resume lifecycle and related metadata/finalization operations; avoid introducing a check-then-reopen race.
3. Windows negative tests must cover fresh and resume hardlinks, junctions and path swaps. The out-of-root victim must remain byte-identical, including on rejected/error paths.
4. Retest both file-transfer directions in the product when authorized; retain error propagation and valid-resume behavior.

### FT010-B03 - P2 - Emergency revoke succeeds without revoking real engine sessions

**Status:** OPEN; F08. **Evidence:** SRC/dataflow; high confidence; no live remote session test claimed.

**Locations:** `src/dauverse/ffi.rs:315-339`; `src/dauverse/security.rs:797,897,945-954`; `src/dauverse/service_ctrl.rs:348-355,398-405,458-481`; actual engine `src/server/connection.rs:600-608,811-863,2403-2424,3250-3285`.

The emergency FFI operation revokes the security module's session map and invokes service configuration changes. Source search found its authentication/authorization methods in definitions/unit tests, not wired into the actual engine's production permission checks. The engine keeps its own per-connection cached permissions. The revoke path neither updates those connections through their permission IPC nor obtains a disconnect/deny acknowledgement. Stopping only an owned SCM service also does not establish that an already-authorized portable connection is terminated. Verification can succeed with no owned service while a portable engine remains active.

**Impact:** `ok:true` and revoked wrapper sessions are not proof that live keyboard, clipboard, file transfer or forwarding authority is revoked. Existing actual-engine connections can retain their cached authorization. This is distinct from durable configuration failure in B04.

**Acceptance criteria:**
1. Revoke through the actual engine/session registry across applicable processes, not an isolated wrapper map. Deny at real capability boundaries and disconnect or explicitly revoke every relevant live connection.
2. Return success only after observable acknowledgement/verification. Timeouts and partial failures must be errors, with conservative access denied and no premature success audit.
3. Controlled portable and owned-service tests must establish a live authorized connection, invoke revoke, and prove subsequent input/clipboard/transfer/forwarding operations fail, including concurrent/in-flight cases.
4. External/non-owned SCM services must remain untouched; service nonexistence alone must not satisfy live-session revocation.

### FT010-B04 - P2 - Security-setting readback verifies cache, not durable persistence

**Status:** OPEN; F07/F08. **Evidence:** SRC in main tree and pinned submodule; no actual configuration fault injection claimed.

**Locations:** `src/dauverse/service_ctrl.rs:349-355,426-433`; pinned `libs/hbb_common/src/config.rs:523-545,562,741-746,1381-1412`.

The service path changes security-sensitive options such as approval mode and permissions through `Config::set_option`, then reads approval mode back. In the pinned implementation, `set_option` first mutates `CONFIG2`, then calls a store API that has no returned failure result. Storage/read-for-store failures are logged and swallowed. `get_option` returns the in-memory/override/default state, not a fresh durable read. A successful cached readback therefore cannot establish that the settings survived disk-full, ACL or corrupt-configuration errors.

**Impact:** the operation can report success while the previous durable security settings return after restart. This can coexist with B03, but fixing real-time revocation alone does not fix restart durability. F05's dedicated security-vault persistence fixes do not fix this separate generic configuration path.

**Acceptance criteria:** security-critical persistence must return and propagate errors; commit atomically, verify the durable state in the owning process, and do not emit success before commit. On failure return `ok:false` and enforce conservative access denial without silently clearing credentials. Inject disk-full, access-denied, corrupt-file/read-for-store and atomic-commit failures, restart, and verify no false success or unsafe reversion. Test the actual pinned configuration API, not only an independent JSON writer.

### FT010-B05 - P2 - Transfer integrity ledger conflates connection/job identities

**Status:** OPEN; F16. **Evidence:** SRC + IE-MODEL; no compiled two-peer E2E claim.

**Locations:** `src/dauverse/transfer_guard.rs:699-744,773-807,949-975`; `src/ui_cm_interface.rs:1173-1181,1230-1255`; `src/client/io_loop.rs:2031-2036`; `libs/base/src/fs.rs:29,46-47,1035-1089`.

Tracking receives a connection ID but uses the global key `engine-fs-{engine_job_id}`, omitting connection/session and direction. Existing-key handling replaces destination root, expected file specifications and total while retaining the original peer identity and transferred state. Verification and finish/error/cancel paths look up only the engine integer ID. Client tracking also uses connection 0. Engine IDs are process/peer-local, so they do not establish global uniqueness. Verification snapshots outside the lock and later marks the key completed without validating the same generation. The CM path invokes a finalization method with no returned error result before verification/Done; base finalization errors are logged rather than fully propagated.

**Retained reproduction:** source-key-lookup model tracks connection A and B with job ID 1, different roots and expected files; A's file is corrupt, B's is valid. After B overwrites the global entry, verifying A's ID selects B's root/manifest and passes, while stored peer remains A. See `independent_evidence/win32_and_collision_helpers.json`, `collision_model`. This demonstrates identity misbinding, not a SHA256 cryptographic break. Root guards still protect many single-job paths; this finding does not assert every failed rename ordinarily produces success.

**Impact:** false completion/integrity proof, cross-job cancellation/state interference and denial of service when concurrent peers/directions reuse IDs. Verifying bytes in another job is not verifying the requested transfer.

**Acceptance criteria:**
1. Namespace all transfer operations by immutable full identity: connection/session, direction, engine job ID and generation. Start, progress, resume, verify, error, cancel, finish and FFI must agree on it. Remove shared connection-0 ambiguity.
2. Verification must use an immutable snapshot and commit only if identity/generation still matches; do not overwrite another active job's root/specification or inherit its state.
3. Propagate finalization/rename errors before reporting Done/completion.
4. Test concurrent same-ID peers, opposite directions, reconnect ID reuse and cancellation isolation; with A corrupt and B valid, A must fail and B alone may pass. Include resume, content tamper and stale-snapshot completion races.

## 5. Non-blocking source observations and conditional constraints

### FT010-Q01 - F02 evidence authenticity remains unproven

`verify_and_package_windows_rc.ps1:157-182` checks minimum log size, skip/failure strings and nine ordered markers. An IE-AST synthetic log containing the markers plus padding, without any compiler invocation, was accepted (`all_markers_synthetic_build_log`). These are log sanity checks, not proof of execution. This does not show that a trusted CI run forged a log.

**Classification:** not an additional source blocker for preparing a corrected pilot; does prevent claiming F02's evidence-authenticity acceptance complete. Require provider/raw run logs tied to exact commit, toolchain, step exit codes and artifact provenance, and cross-check them against the claimed output. A caller-supplied text file alone cannot establish independent execution authenticity. Add a negative test for complete-marker fabricated input; no paid attestation service is required by this report.

### FT010-Q02 - P3 / F15 conditional NSIS path/version inconsistency

Workflow `.github/workflows/dauverse-windows-build.yml:188-236` finds an exact NSIS 3.11, including a Program Files candidate, but its selected `$ResolvedNsis` is process-local and not exported/passed into the subsequent build process. `scripts/windows/build_windows_release.ps1:311-330` independently resolves PATH or a Program Files candidate and does not enforce the same exact-version condition before invocation. With PATH pointing at 3.10 and Program Files holding 3.11, workflow preflight can pass while build invokes the wrong tool. Later provenance checking can reject it, but only after wasted/failing build work.

**Classification:** conditional Windows-build blocker, not a demonstrated condition on the unavailable current runner. No extra historical ID is added. Acceptance: pass the exact absolute selected path to build and check its actual version immediately before invocation, or resolve and enforce it inside build. Cover wrong-PATH/correct-alternative, no-exact-version and standalone-build scenarios.

### FT010-Q03 - Backward compatibility is not equivalent to verified interoperability

- `libs/base/protos/message.proto:368-375` adds per-file SHA256 string field 6 while preserving prior field numbers: wire-additive, not a demonstrated protobuf numbering collision.
- `transfer_guard.rs:297-303,347-353` rejects missing SHA256 before write. An old sender is therefore intentionally rejected by RC3. Do not downgrade this fail-closed check to obtain compatibility.
- An old receiver can ignore RC3's new field. Sender-side hashing/mutation checks do not establish the old receiver's final bytes; a legacy Done is not a cryptographic receiver receipt. No complete new integrity-capability negotiation was established by the source review.
- `src/ipc.rs:182-189` changes file tuple shape from `(name,size)` to `(name,size,mtime,sha256)`. RC3 producer `src/server/connection.rs:3831-3839` and consumer `src/ui_cm_interface.rs:1074-1092` were updated together. Mixed old CM/service processes can fail deserialization; no mixed-version handshake was established.
- Hook schema V2 is rejected by the V3 receiver. Coordinated hook replacement is required.

**Classification:** explicit compatibility limitation, not a separate blocker for a homogeneous RC3-only pilot with documented limits. It blocks a claim of transparent old-peer compatibility or integrity-verified legacy transfers. Acceptance: publish/test RC3-to-RC3, old-to-new fail-before-write, new-to-old explicit refusal or clearly unsupported/unverified behavior, empty directories, and mixed-process upgrade/restart. Introduce negotiation if interoperability is promised; otherwise fail clearly and document coordinated restart. Never label an unchecked legacy receipt integrity-verified.

## 6. Complete F01-F16 + N01 disposition

`CLOSED-SOURCE` means the examined source residual is fixed or an unchanged prior correction is preserved. It does not certify unavailable native scenarios. `PARTIAL-NATIVE` means source closure improved but a specified acceptance scenario has not been demonstrated. Existing Windows/pilot caveats are retained rather than rediscovered as new findings.

| ID | Historical severity | Independent disposition | Evidence and precise remaining boundary |
| --- | --- | --- | --- |
| F01 | P1 | CLOSED-SOURCE | HMAC V3 checked receiver, bit-level floats and strict envelope parsing; invalid internal signer inputs caveat below. No new acceptance bypass established. |
| F02 | P1 | OPEN/PARTIAL | B01 deterministic final-manifest failure; Q01 log authenticity; no RC3 Windows artifact certification. |
| F03 | P1 | CLOSED-SOURCE / prior fix preserved | Owned-service boundaries preserved; live owned/external-running-service native scenario not independently executed. |
| F04 | P1 | CLOSED-SOURCE | Headless Active depends on actual Windows activation/monitor state; unsupported/test-driver policy preserved. Monitorless native pilot still required. |
| F05 | P1 | CLOSED-SOURCE | Dedicated security-vault/PIN persistence returns errors and rejects corrupt/unreadable existing state. Generic Config durability is separately OPEN in B04. |
| F06 | P1 | CLOSED-SOURCE | Release FFI mock/force-unbound guard preserved; full compiled Windows release GUI wrong-DLL/missing-export behavior not independently exercised. |
| F07 | P2 | OPEN/PARTIAL | B04: runtime security setting cache is not durable proof. |
| F08 | P2 | OPEN/PARTIAL | B03+B04: real engine-session cutoff and durable emergency configuration not established. |
| F09 | P2 | CLOSED-SOURCE | Strict replay-journal read failure handling and write-failure rejection; multi-process/crash/Windows restart pilot outstanding. |
| F10 | P2 | CLOSED-SOURCE / prior fix preserved | Unmeasured FPS stays unavailable rather than fabricated; CPU/loopback benchmark cannot establish remote FPS/GPU performance. |
| F11 | P2 | PARTIAL-NATIVE | Rollback closure hardened and helper-tested, but simulated overlay is not a real distinct-release A/B upgrade/rollback proof. See section 7. |
| F12 | P2 | CLOSED-SOURCE / prior fix preserved | Signature/thumbprint policy and unsigned auto-update refusal preserved; real publisher chain/revocation/native deployment not checked. |
| F13 | P2 | CLOSED-SOURCE / prior fix preserved | Safe power/WoL/preset/manual-activation policy preserved; physical device/wake/shutdown behavior requires pilot. |
| F14 | P2 | OPEN/PARTIAL; current B02 P1 | Long-path/root/reparse improvements do not close fresh staging hardlink truncation. |
| F15 | P3 | OPEN/PARTIAL | Six PowerShell files parse successfully; Q02 exact NSIS path not consistently carried into build. Parsing is not execution. |
| F16 | P2 | OPEN/PARTIAL | Per-file/stream/resume SHA256 improvements present, but B05 identity and B02 confinement prevent integrity closure; Q03 legacy limits. |
| N01 | P2 | CLOSED-SOURCE | Benchmark per-iteration precision corrected; numeric evidence consistent within rounding, not end-to-end latency proof. |

### F01 - HMAC V3 and strict input handling

`src/dauverse/ai_bridge.rs:163-180,219-240,610-646` uses checked receiver canonicalization with binary32 tags; schema version is 3, with unknown-field denial on envelope structures (`77,86,106,144`). Strict UTF-8/exact body handling is at `905-994`. Retained exact Python adapter AST checks agree for Unicode input and HMAC formula, reject negative zero, non-finite and out-of-range values. PowerShell tags agree on the sampled values. This is not reviewer execution of the Rust receiver or HTTP endpoint.

**Qualification:** internal `canonical_signing_bytes` / `sign_event_envelope` at `243-271` are not universally checked signer APIs. They can construct signatures for inputs that the checked receiver rejects. Therefore a broad assertion that every signer rejects invalid input before signing is too strong. No receiver-acceptance bypass was established from this fact; it is not counted as an additional blocker.

### F03-F06 - Service, headless, vault and release guard

Service operations are restricted by owned-service logic rather than permission to alter arbitrary external services. That source boundary does not prove all Windows alias/race behavior or an actual external running service pilot.

`src/dauverse/headless.rs:112-114,319-347` blocks the examined WDK test-certificate/RustDeskIdd route and reports Active through actual Windows `plug_in_headless`/monitor state rather than a mock success. Actual driver, monitorless GPU capture, reboot and activation were not attempted.

`src/dauverse/security.rs:597-605,626-634,755-791` propagates dedicated security-state persistence errors and distinguishes missing fresh state from corrupt/unreadable existing state. This closes the examined F05 source residual; DPAPI, ACL, multi-profile and reboot behavior remain native work. It does not repair `Config::set_option` in B04.

`flutter/lib/dauverse/bridge/dauverse_bridge.dart:33-61,81-90` uses `dart.vm.product` and release guard behavior; debug-only assert assignment/mock behavior cannot be treated as release authorization. Release must not silently route to mocks through force-unbound. Standalone/simulated-release probes and debug widget tests do not establish the full native release GUI's wrong-DLL/missing-export error-banner behavior.

### F09 - Replay persistence

`src/dauverse/ai_bridge.rs:384-438` distinguishes a legitimately missing journal from read, UTF-8 or JSON failures. A failure latch rejects events (`598-608`), and journal persistence failure rejects the operation with in-memory rollback (`704-710`). Dashboard health exposure is at `src/dauverse/mod.rs:371-374`. Developer evidence includes restart and corrupt-journal denial; this reviewer did not rerun it. Concurrent process writers, crash/atomicity fault injection and native Windows restart were not proved by local helper tests. No new replay acceptance bypass was established in the examined source.

### F14/F16 - Improvements retained without overclaim

`libs/base/src/fs.rs:731-798` improves Windows path/root handling, ADS/reparse rejection and final-path buffer/error handling. It is not a proof against every kernel-level swap/oplock race. Resume single-link validation does not cover fresh writes (B02).

Per-file SHA256 capture (`fs.rs:908-909`), streaming/mutation handling, resumed whole-file checks and pre-rename validation improve upon aggregate byte totals. Those improvements matter: equal total bytes such as `[4,6]` versus `[2,8]` and same-length content replacement cannot be accepted merely on size. They do not fix cross-connection ledger lookup (B05), and sender hashes alone do not prove a legacy receiver's bytes (Q03). Both-direction native file/folder/empty-file/resume/skip/cancel/integrity behavior remains a required pilot.

### N01/F10 - Benchmark precision and scope

`src/dauverse/performance.rs:476-486` computes microseconds per iteration from total elapsed time and rounds to three decimals. Recorded example: 1.75 microseconds x 200 = 350 microseconds, compared with total 350.042 microseconds; the 0.042 microsecond discrepancy is consistent with per-iteration rounding. The former precision inconsistency is corrected at source. Neither that example nor local CPU/loopback tests establish RTX 3060 NVENC performance, monitorless FPS, WAN latency or actual remote desktop throughput.

## 7. Rollback closure versus real A/B release acceptance (F11)

Source references in this paragraph refer to `scripts/windows/rollback_windows_release.ps1:85-190,254-256,299-323`. The rollback validates bidirectional backup closure, restores only listed files and verifies restored output. The retained exact-AST helper accepted a complete backup and rejected a rogue extra file. Its PE fixture was synthetic 512-byte data and was **not executed** as an EXE.

However, `scripts/windows/verify_and_package_windows_rc.ps1:1054-1072` reinstalls the same Setup EXE and appends a 64-byte `DAUVERSE_DISTINCT_RELEASE_B_OVERLAY_MARKER` overlay to a DLL. This produces a different hash but is explicitly a **SIMULATED_BINARY_OVERLAY**, not a distinct independently built release B and not an ABI/installer/upgrade compatibility exercise. Handoff language must not upgrade that scenario to actual A/B acceptance.

**Acceptance criteria still outstanding:** use genuinely distinct A and B builds/commits, record installer and installed-file identities, upgrade A to B, then restore A; verify removal of B-only files and successful launch of restored A, complete backup/output closure, refusal before mutation for invalid backups, interrupted/failed rollback recovery, and external/non-owned-service preservation. F11 is counted as PARTIAL-NATIVE, not as a sixth newly discovered blocking source defect.

## 8. Completed independent checks - retained, NOT rerun

| Evidence file in `independent_evidence/` | Completed result | What it does not prove |
| --- | --- | --- |
| `baseline_verification.json` | Pinned commits, listed manifest entries and source text preservation recorded | Exhaustive ZIP closure or execution authenticity |
| `review_receipt.json` | Final HEAD/submodule, status, fsck and tool availability recorded | Native application acceptance |
| `powershell_helpers.json` | Six scripts parse with zero errors; eight helper outcomes plus four float tags | Full build/install/rollback/service execution |
| `python_hook_helpers.json` | Both adapters: nine float cases each (18 assertions); Unicode canonical bytes equal; HMAC formula matches | Rust receiver, socket/HTTP E2E or DLL execution |
| `win32_and_collision_helpers.json` | Staging hardlink truncation and cross-job lookup model outcomes | Compiled product two-peer remote exploitation |

Exact PowerShell files parsed: `scripts/hooks/dauverse_job_wrapper.ps1`, `scripts/windows/build_windows_release.ps1`, `scripts/windows/package_complete_rc2_qa_archive.ps1`, `scripts/windows/rollback_windows_release.ps1`, `scripts/windows/verify_and_package_windows_rc.ps1`, `installer/nsis/dauverse_setup_helper.ps1`.

Exact-AST PowerShell outcomes: initial manifest accepted; exact final generator layout rejected (B01); unlisted extra rejected; synthetic complete-marker build log accepted (Q01); complete backup accepted; extra backup file rejected; negative-zero float rejected; just-above-100 float rejected. Valid tags: 0=`f32:00000000`, 0.95=`f32:3f733333`, 1=`f32:3f800000`, 100=`f32:42c80000`.

Python helper extracted only `quantize_and_encode_f32`, `canonical_signing_bytes_v3` and `sign_envelope` from `claude_code_hook.py` and `codex_notify_hook.py`. Zero/0.95/100 accepted; negative zero, next binary32 above 100, NaN, positive/negative infinity and confidence above one rejected. Unicode fixture canonical SHA256 for both adapters: `23892fb748e86924085e7e01c8316b7497dd9415c868d25033a675fc0afbc71f`. An inert fixture key was used. No adapter main routine, live hook, network callback or restricted secret was invoked/displayed.

Reviewer scripts and retained inert fixtures remain in the review root / `independent_evidence`. They were not inserted into the source checkout. This report's completion verification only checks the saved document and evidence inventory; it is not a new regression run.

## 9. Reused developer and prior QA evidence

The following repository evidence under `source_rc3/ARTIFACTS/evidence` was read and reused at its actual scope, without re-execution:

| Evidence | Recorded result / limitation |
| --- | --- |
| `dauverse_unit_security_tests.log` | 29 passed, 0 failed, 0 ignored; Linux, 215 filtered out; not all Rust tests |
| `rc2_base_fs_tests.log` | 26 passed, 0 failed, 0 ignored; contents updated for RC3 despite RC2 filename |
| `flutter_dauverse_ui_tests.log` | Five passed; debug/mock/error-path coverage, not full native release GUI |
| `flutter_all_tests.log` | **187 passed, one skipped**, not 188 passed |
| `cargo_release_flutter_lib.log` | Linux release build completed in 7m42s; not Windows MSVC cfg/link proof |
| `flutter_linux_release_build.log` | Linux bundle/rustdesk build; not Windows installer proof |
| `ai_bridge_and_secret_scan.json`, `rc2_security_negative_matrix.json` | Developer process/FFI/hook/restart/tamper/replay/vault-negative evidence; corrupt-journal phase records 503 denial; not independently rerun |
| Secret-scan portion | 1,194 files; zero reported secret findings apart from identified upstream websocket-key.pem fixture exception; not an exhaustive secret-safety guarantee |
| `release_ffi_smoke_test.json` | Recorded `{ok,data}` status/snapshot; does not validate every native side effect |
| `benchmark_results.json` | Linux CPU/loopback measurements; explicitly not RTX/NVENC/end-to-end remote performance |
| WP02 baseline logs | Historical context only; not represented as fresh RC3 execution |

Old RC2 Windows evidence from run **45720572543** concerned one disposable Windows Server runner, not Windows Sandbox `.wsb` or two independent PCs. External-service coverage used a `cmd.exe` service definition that was not started. GUI/DLL liveness did not establish input, clipboard or file-transfer correctness. Evidence was unsigned. Preserve still-valid baseline conclusions, but do not assign those old binaries to changed RC3 code, claim two-PC/native-headless coverage, or rerun broad discovery merely to restate these limits.

Repository evidence is useful corroboration; hashes and logs supplied by one producer cannot alone prove independent execution. No new CI was triggered to obtain additional evidence.

## 10. Windows build readiness and native pilot boundary

### Build/readiness disposition

1. **Deterministic pipeline blocker:** B01 final manifest verification must be repaired; otherwise the final Windows package cannot pass its own closure check.
2. **Conditional toolchain blocker:** Q02 can select a different NSIS executable/version in build from the one approved in preflight. The actual current runner state is unverified.
3. **Security handoff blockers:** B02-B05 remain gating even if compilation is green. Building successfully cannot compensate for unsafe filesystem mutation, incomplete emergency revoke, false durable success or wrong-job integrity proof.
4. **Not measured here:** Windows-specific Rust/MSVC compile/link, generated protobuf bindings, actual NSIS invocation and the full Flutter Windows AOT/FFI boundary. PowerShell parse success and Linux logs are not substitutes. This report does not invent a Windows compiler error.

### Unverified items / controlled native pilot required

- Full Windows compile/link/protobuf regeneration, release Flutter GUI, real DLL exports/missing/wrong DLL diagnostics and installer flow.
- Live portable and owned-service sessions, permission IPC, actual emergency cutoff, running external-service ownership/revoke preservation and multi-process behavior.
- DPAPI/ACL/multi-profile storage, disk-full/access-denied/corrupt-write failures, crash atomicity, replay multi-writer/reboot persistence.
- Real two-peer LAN/WAN transfer in both directions: file/folder/empty file/empty directory, skipped files, resume, cancel, same-size content tamper, concurrent duplicate IDs, reconnects and final error propagation.
- Windows staging hardlink/junction/reparse/path swap/oplock stress; no claim of complete kernel race immunity.
- Real distinct A/B installer upgrade and A rollback; restored-A launch, B-only file removal and interrupted recovery.
- Old-peer and mixed old/new-process compatibility, version negotiation or documented coordinated restart and explicit refusal.
- Monitorless virtual-display/driver/GPU capture and reboot; RTX 3060 NVENC/FPS/latency measurement.
- Publisher signing, certificate-chain/revocation checks and native auto-update validation; actual WoL/sleep/shutdown and physical smart-plug/manual-approval behavior.

Native pilot is future acceptance work, not authorization from this report to install anything or unlock production. No costs, EXE/service/driver installations, full rebuild, CI or production interaction occurred in this task.

## 11. Cloud ZIP and unavailable evidence

Cloud ZIP was not accessible in this review. Source checkout, pinned history and repository evidence were available, so the review continued and reached a source decision. **NOT AVAILABLE is not a finding that the ZIP is corrupt.**

Not verified: outer ZIP checksum, packaged archive contents/closure, files/logs/binaries absent from Git, exact binaries behind developer JSON assertions, and new Windows artifact/run attestations. These missing items must not be represented as inspected, downloaded, passed or failed. They are explicit limitations, not a reason to label an otherwise reviewable source gate BLOCKED.

## 12. Acceptance and handoff checklist

Before reconsidering the source verdict, Developer should supply a corrected commit plus focused evidence for **all B01-B05 acceptance criteria in section 4**, resolve or explicitly scope Q01-Q03, and update the historical matrix without converting simulated/native-pending evidence into completed acceptance. Use narrow regression evidence; unchanged prior results may be reused. A future review should not unnecessarily rebuild or rediscover previously closed residuals.

| Required gate | Current state |
| --- | --- |
| Correct pinned source and submodule, selective manifests | VERIFIED |
| Historical reports read and byte identities recorded | VERIFIED |
| All 17 historical IDs dispositioned | COMPLETE at source-review scope |
| Blocking source residuals resolved | **NO - five remain** |
| Final Windows package generator/validator agree | **NO - B01** |
| Full native Windows/compatibility acceptance | NOT VERIFIED; pilot required |
| Cloud ZIP-only evidence | UNAVAILABLE; limits documented |
| Production authorization | **NONE - LOCKED** |

## 13. Report integrity and completion record

At the start of the requested continuation, the named report did **not** exist; retained evidence files did. This document was subsequently created by synthesis of those completed results, without rerunning tests. It is not an assertion that a previous failed write succeeded.

The final report is UTF-8 without BOM, LF line endings. Its final SHA256 and byte count are recorded externally in `independent_evidence/reviewer_evidence_sha256.json` and in the management handoff. A report must not embed its own final hash as a self-referential checksum. The external index also inventories the principal evidence files and reviewer helper scripts; it is not a publisher signature or external attestation.

**FINAL VERDICT: FAIL_SOURCE_GATE**

**Production LOCKED. No source modification, push, CI or deployment is authorized by this report.**

# DAUVERSE REMOTE V1 — INDEPENDENT QA & SECURITY ACCEPTANCE REPORT

**Task:** DREMOTE-V1-INDEPENDENT-QA-004  
**Reviewer:** CODEX — independent QA/security reviewer  
**Developer:** ANTIGRAVITY CLOUD  
**Date:** 25 November 2026, Asia/Saigon (UTC+07:00)  
**FINAL VERDICT: FAIL**  
**Production remains LOCKED. This report is NOT Production Approved.**

## 1. Executive Summary / Tóm tắt điều hành

**Không chấp nhận RC hiện tại cho controlled Windows pilot.** Đã hoàn thành phần kiểm định khả thi: xác minh đầu vào cục bộ, hash/manifest/bundle cũ, rà soát source tại commit chỉ định, Windows remediation, workflow và phản ví dụ độc lập không chạy mã ứng viên. Có lỗi static/evidence đủ để kết luận FAIL, không chỉ thiếu môi trường.

Gói Windows RC chính xác chưa có trong các vị trí truy cập được đã kiểm tra. Binary integrity, Windows native, remote session hai máy và persistence thực tế đều **BLOCKED**, không được chuyển thành PASS từ báo cáo developer/CI. Không kết luận binary bị giả mạo: chưa có bytes để kiểm chứng.

Điểm chặn: F01 HMAC; F02 acceptance harness; F03 installer ownership; F04 Headless truthfulness; F05 Step-Up PIN change boundary; F06 unbound FFI success fallback. Điều kiện/giới hạn kết luận ở §6. Không gán lỗi local thành remote unauthenticated exploit.

**Governance:** no candidate EXE/DLL/installer executed; no application installation, source patch or rebuild; no service/driver/BIOS/firewall/router changes; no DAUVERSE AI interference; no paid API, purchase or CI trigger. Only reviewer-owned files created. Hunonic SK02 not contacted. No claim production was compromised.

| Acceptance area | Outcome | Scope |
|---|---|---|
| Available-input checks and independent models | PASS, narrow | Reviewer procedures, not product acceptance |
| Exact package/binary hashes and source-to-binary chain | BLOCKED | Exact RC unavailable |
| Pinned source acceptance | FAIL | F01–F06 |
| Evidence/harness acceptance | FAIL | F02; historical manifest also incomplete |
| Windows native lifecycle | BLOCKED | No exact candidate/authorized guest execution |
| Two-machine functionality/performance | BLOCKED | No authorized endpoint pair/session |
| Full CVE, secret and IPC audit | NOT TESTED / partial static | No security clean bill |
| Controlled pilot now | FAIL — do not install | Reopen after §13 gates |
| Production | LOCKED | Outside approval scope |

No P0 demonstrated does not mean no P0 exists. Severity is acceptance risk, not certified CVSS. FAIL reflects observed defects; unavailable runtime evidence remains separately BLOCKED.

## 2. Scope, method and boundaries

The user's lists define the review checklist. A separately versioned full Master Build Order was not delivered; equivalence to an unseen document cannot be certified.

**PASS:** identified independent check met its criterion. **FAIL:** evidence contradicts criterion. **BLOCKED:** artifact/authorized environment/hardware unavailable. **NOT TESTED:** insufficient independent procedure performed.

**REAL-SOURCE** means an engine/OS call path exists, not that the RC executes it. **UI/STATE** means presentation/model without demonstrated native effect. **MOCK/FALLBACK** is synthetic state, excluded from live evidence. **UNSUPPORTED/DISABLED** is intentionally unavailable. A row may FAIL static requirements and remain BLOCKED for runtime. Unit tests, screenshots and CI green cannot substitute for Windows integration.

### Workspace

Requested `E:\DAUVERSE_REMOTE_DESKTOP\QA\` was unavailable: E: exists, but the project/QA directory was not found. No project was created there or other E: project touched. Output:

`C:\Users\ADMIN\Documents\DREMOTE-V1-INDEPENDENT-QA-004\`

Root listing/writes encountered restrictions; Documents was usable. Git network access failed; read-only GitHub web access allowed pinned-file review. No restriction bypassed.

`C:\Windows\System32\WindowsSandbox.exe` exists. This does not establish a configured/authorized guest. No VM/sandbox launched. Common VirtualBox/vmrun locations were absent, not an exhaustive hypervisor inventory.

## 3. Baseline verification and provenance

| Item | Requested baseline | Independent outcome |
|---|---|---|
| Commit | `309948002371aba1407532c9ba8d9d216a02e771` | GitHub page/pinned raw source accessible; local Git object closure BLOCKED [R01] |
| Branch | `develop/dauverse-remote-v1` | Associated with requested run; no claim about future HEAD [R02] |
| Actions run | `45603088230` | GitHub reports Success, 57m54s, one artifact, eight warnings [R02] |
| Final bundle | Exact commit and prerequisites | Not delivered in accessible inputs |
| Corresponding source/submodules for binary | Complete matching tree | BLOCKED |

Run page displays manual trigger **25 November 2026, 11:17**, timezone not established; not represented as UTC/local time. It links requested branch and `3099480`. Logs require sign-in on the inspected page. This is provider metadata, not downloaded logs, signed provenance or output digest verification. No workflow triggered. [R02] citeturn688578view2

### Windows remediation history reviewed

Observed chain: `35e3f2d → e88c971 → d33ef4e → ce6b860 → 3099480`. Four Windows remediation commit pages/current affected files inspected; full local object history unavailable. [R01, R04–R06]

| Change | Assessment | Limit |
|---|---|---|
| DPAPI import, e88c971 | Correct imports in current crypto source [R06, R29] | Runtime/reopen not independently run |
| Headless `not(test)`, d33ef4e | Legitimate test isolation [R05, R09] | Not evidence of real virtual display; F04 |
| GUI/FFI, d33ef4e | Stronger forged-event check, but interactive early-exit assertion removed [R05] | F02 acceptance regression |
| NSIS SetRegView 64, ce6b860 | Both initialization paths updated [R04, R08] | Does not fix service ownership |
| Registry/Start Menu | Broader view/location handling [R04] | Existence is not target/ownership verification |
| `credential_vault`, 3099480 | Correct JSON field, not product security fix [R01, R11] | Not DPAPI durability proof |
| Manifest regeneration | Changed hashes recorded [R01, R04–R06] | Cannot prove old/missing evidence |

No assertion every historical change outside this observed remediation chain was reviewed.

## 4. Artifact integrity, dependencies and submodules

### 4.1 Exact RC — expected hashes, NOT observed hashes

| Artifact | Expected SHA256 (user-supplied) | Actual / outcome |
|---|---|---|
| `DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC_PACKAGE.zip` | `b8a0428f67c2968066d2f208a6afe471c62f83d5e67b7c527cf6e7c6acecbd26` | Unavailable / BLOCKED |
| `DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` | `9331caee11bd9fc326b723b4573800be6c8c0e9dac3551930fc76f1eec748ba6` | Unavailable / BLOCKED |
| `DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe` | `e7b82cdbaf052dac4a3ee291423a5a9c814ad77602d6f9a5663e70827056e1a2` | Unavailable / BLOCKED |
| `FINAL_HANDOFF_SHA256_MANIFEST.txt` | Complete required coverage | Unavailable / BLOCKED |
| Native build log; Windows JSON/MD report | Original exact-run records | Unavailable / BLOCKED |
| DLL/driver/license/source/SBOM artifacts | Recursive inventory and digests | Final payload unavailable / BLOCKED |

Bounded filename discovery: Downloads depth 5, 1,176 files; Documents depth 5, 11,003 files; no final delivery hit, no reported errors, no reparse traversal. This is not global absence proof across all disks. Missing evidence was not excluded from acceptance. [L01, L04]

### 4.2 Historical handoff found — NOT substituted

| Input in Downloads | Bytes | Independently computed SHA256 |
|---|---:|---|
| `DAUVERSE_REMOTE_DESKTOP_V1_RC1_REMEDIATED.bundle` | 1,892,522 | `334c4f2f8f82abc588b0370a119a563ae2ecc8185f6820b065041407a90a4d8e` |
| `DAUVERSE_REMOTE_DESKTOP_V1_RC1_REMEDIATED_QA.zip` | 9,834,175 | `675c3640f56e46e28a8dda8e7a842bba8a58b1ae93fbe4509c1404cde58131d0` |

Bundle advertises branch head `35e3f2d4b8a0f4a2e0e44068e30591265b8092e5` and tag `rc1-baseline-35027150` at `35027150fcc497ade9145fcb4ea5cbc625035630`. Own empty bare-repository `git bundle verify` exited **1**: missing prerequisite `a0c0963c483fc8f1aeed4547787d1673adcb583c`. No-checkout clone also failed. This is a non-self-contained older handoff, not necessarily corruption, and cannot establish requested baseline. [L02]

Old ZIP safely extracted 1,497 entries, rejecting absolute/escaping paths, drive syntax and symlinks. No candidate code executed. Each historical manifest (`SHA256_MANIFEST.txt`, `ARTIFACTS/SHA256_MANIFEST.txt`) has **41 entries: 39 MATCH, 2 MISSING, 0 MISMATCH, 0 MALFORMED**. Missing:

```text
target/release/liblibrustdesk.so
flutter/build/linux/x64/release/bundle/rustdesk
```

**Historical manifest completeness: FAIL.** Thirty-nine matches are not whole-manifest PASS. This is not a finding that the inaccessible final manifest has the same missing entries. [L03]

Old Cargo.lock: 1,026 packages, SHA256 `c09e5bfcb87918f84c0c4f806f1f3b7ef1a8a879c3214f44046f7b516756909b`. SPDX JSON parses as SPDX-2.3/CC0-1.0, 1,239 package records. LICENSE/LICENCE match. Historical inventory is not a current CVE/legal certification. [L03]

Current `.gitmodules` references upstream hbb_common; exact final gitlinks/recursive objects unverified. [R24] Workflow pins actions/vcpkg/Flutter/LLVM, but Rust stable moves and NSIS installation is unversioned. Tests can be disabled by input. Targeted tests and locked dependencies do not establish full regression. Original run inputs/logs unavailable; no allegation tests actually skipped. [R03, R07]

### 4.3 Required manifest retest

Freeze required recursive inventory before validation. Validate expected manifest bytes before regeneration; reject missing/unreadable/listed-but-absent files, malformed/duplicate/conflicting paths, mismatches and unexpected executables. Include source/submodules, DLLs, driver set, licenses, SBOM and original logs. Preserve original expected manifest; generate a distinct packaging manifest only afterwards. Keep outer ZIP hash separately. Map run→checkout/tool versions→binary digests→archive. These are proposed gates, not completed final-RC checks.

## 5. Full functional QA

Every live RC case below is **BLOCKED** unless explicitly stated. Source classification is separate; upstream code presence is not acceptance.

| Scope | Source classification / reference | Independent outcome or remaining live case |
|---|---|---|
| Remote Engine integration | REAL-SOURCE launcher/FFI [R12, R14] | BLOCKED: delivered DLL binding and real session |
| Remote Session | Native launcher [R14] | BLOCKED: approve/deny/end/revoke |
| Mouse and keyboard | Engine-dependent, no live proof | BLOCKED: drag/wheel/shortcuts/stuck-key release |
| Vietnamese Unicode | UTF-8 clipboard policy [R20] | BLOCKED: IME and NFC/NFD round-trip |
| Clipboard text | Guard source [R20] | BLOCKED: bidirectional/disabled/loop handling |
| Clipboard image | Payload policy [R20] | BLOCKED: DIB/PNG/transparency/denial |
| Clipboard file | Policy, engine-dependent [R20] | BLOCKED: Explorer copy/paste/cancel |
| File transfer | Receive hooks/tracking present [R15, R16] | BLOCKED: both directions; not wholly absent |
| Transfer integrity | SHA256/resume code [R16] | BLOCKED: independent hashes/tamper/resume |
| P2P | Engine-dependent | BLOCKED: prove actual direct route |
| Relay | Engine-dependent | BLOCKED: authorized relay and encryption |
| Reconnection | No live evidence | BLOCKED: recover without permission bypass |
| Audio | No live evidence | BLOCKED: capture/mute/consent/continuity |
| Multi-monitor | No topology acceptance | BLOCKED: monitor switch/mixed DPI/unplug |
| Floating Toolbar | UI/control scope | BLOCKED: interaction/focus/permission checks |
| Mini Control | UI/state/runtime flags [R13, R23] | BLOCKED: minimize/restore/session truth |
| Smart Power | Actions/guards; F05/F13 [R12, R18] | FAIL static gaps; live BLOCKED |
| Headless Mode | Mixed native/state; F04 [R09] | FAIL truthfulness; monitorless runtime BLOCKED |
| Windows Startup | UI/STATE setter; F08 [R17] | Not proof of startup; reboot BLOCKED |
| Windows Service | SCM/optional NSIS [R08, R17] | F03/F08; lifecycle/ACL BLOCKED |
| Unattended Access | Mixed state/upstream disable [R17] | BLOCKED: enable/login/revoke |
| Hardware Monitor | Sampling interface [R12] | BLOCKED: independent counters; unavailable sensors N/A |
| AI Event Bridge | REAL-SOURCE loopback [R19] | FAIL F01/F09; native hooks BLOCKED |
| AI Notification Center | Event/history source [R21] | BLOCKED: delivery/dedup/restart |
| Corner Toast | Toast model [R21] | BLOCKED: actual corner/DPI/no focus steal |
| AI Live Status | Task model [R19] | BLOCKED; inherits F01; no actual AI changed |
| Security Center | Policy/UI [R11] | BLOCKED: verify engine enforcement |
| Installer | REAL NSIS [R08] | FAIL F03; native install BLOCKED |
| Portable | Packaging/binding [R07, R13] | BLOCKED: clean-host extraction and GUI |
| Uninstaller | Removal path [R08] | FAIL F03; native removal BLOCKED |
| Rollback | Script [R22] | BLOCKED: distinct-version/data recovery |
| Settings persistence | Mixed disk/in-memory [R10, R11, R21, R23] | F07; native close/reopen BLOCKED |
| UI/UX | Source only | BLOCKED: pixels/interactions/accessibility |
| Hunonic SK02 | UNSUPPORTED/DISABLED default [R18] | Keep DisabledSmartPlugAdapter; no hardware PASS |
| Simulated plug / unbound FFI | MOCK/FALLBACK [R13, R18] | Excluded from live acceptance |

No historical screenshot is treated as this Windows RC. No inherited audio/clipboard/P2P/relay feature received an independent runtime PASS.

## 6. Findings P0/P1/P2/P3

Confirmed-static means visible source behavior. Model-confirmed means own safe expression/data model, not RC execution. Risk means a plausible gap requiring testing. IDs are stable for AGY response.

### P1 — blockers before controlled pilot

**F01 — HMAC excludes security-relevant event fields.** Confirmed-static + model-confirmed. `canonical_signing_bytes` omits summary, severity, progress, artifact reference, confidence and provenance; evidence_verified affects normalization. A party modifying a legitimate envelope before first accepted ingest can change evidence semantics without invalidating its signature. This does not allow forging signed core fields. Synthetic-key model: ten omitted-field changes preserve signature; task_id control changes it; unsigned provenance changes normalized UNKNOWN→COMPLETED. **Fix:** authenticate every consumed field with versioned unambiguous serialization; derive trust server-side and test field mutations. [R19, L05] citeturn725061view0

**F02 — Windows harness allows false acceptance.** Confirmed-static + GUI model. `verify_and_package_windows_rc.ps1` ~66–79,110–125,143–175,292–397: GUI exits 0/1/2 accepted without surviving window; missing build log replaced by success text; incoming manifest hashes not checked before top-level regeneration; signer subject not full trust/catalog proof; extraction/same-version rollback insufficient; final PASS exceeds observations. **Fix:** fail-closed gates and immutable originals. [R25, L05] citeturn725061view1

**F03 — Installer/uninstaller can affect unrelated RustDesk service.** Confirmed-static. Required install stops RustDesk; uninstall stops/deletes it without ImagePath/product ownership or prior opt-in verification. Optional unchecked creation does not protect an existing installation. Rollback also operates by service/process names. Conditional impact: unrelated RustDesk availability/configuration damaged. No host execution or arbitrary SYSTEM escalation demonstrated. **Fix:** ownership/collision refusal or approved migration, scoped paths/ACLs, checked native status and preservation tests. [R08, R22] citeturn725061view2

**F04 — Headless active state without native activation.** Confirmed-static + model. Windows call requires should_activate AND approval, but active flag is assigned should_activate afterwards. Valid request/approval=false reports active without OS call. Literal topology token and constant compatibility/security flags are not measurements. Driver authorization accepts booleans rather than verifying payload trust. **Fix:** pending/blocked/verified states, actual topology/capture/restore evidence, byte-level signature verification. Retain unit-test OS isolation, not as native acceptance. [R09, L05] citeturn725061view3

**F05 — Step-Up PIN replacement lacks existing-owner authentication.** Confirmed-static, conditional local threat. Setter checks length/writes sealed PIN; FFI accepts new PIN without old-PIN challenge. Someone controlling unlocked GUI/local invocation boundary can replace this gate before sensitive actions. No remotely reachable unauthenticated reset endpoint demonstrated. PIN method itself lacks evident lockout; general auth limiter is separate. **Fix:** authenticated enrollment, owner reauthentication for replacement, protected recovery, per-principal lockout and safe audit. [R11, R12] citeturn688578view1turn160914view1

**F06 — Unbound FFI fallback can report successful mutations.** Confirmed-static. Failed native binding reaches `_fallbackTestState`; generic commands return ok:true with supplied data. Dashboard does disclose UNBOUND-TEST/zero values, but fallback is not compile-restricted to tests. Actions can appear successful without native effect. **Fix:** test-only dependency injection; production error/unavailable state with privileged controls disabled; missing-DLL/wrong-export/architecture tests. [R13] citeturn688578view0

### P2 — significant acceptance gaps

| ID | Observation and confidence | Remediation / proof required |
|---|---|---|
| F07 | Static: new runtime defaults to temporary storage/ignores write errors [R10]; trust/preferences/auxiliary state partly in memory [R11, R21, R23]. Not all upstream settings are volatile. | Stable protected locations, explicit errors, durable schema/crash-safe writes; restart/corruption tests |
| F08 | Static: auto-start setter changes state; enable-unattended alone does not establish OS configuration; status shown only promotes Running [R17]. | Transactional OS configuration, authoritative refresh, failure/revoke propagation |
| F09 | Static + model: 2,048-entry replay FIFO can evict within five-minute validity [R19, L05]. Requires sufficient legitimate signed events, not forged flood. | Retain replay identities for validity window; safe capacity handling and restart tests |
| F10 | Static: FPS derives from target, bitrate from estimate; timing defaults are not measured delivery [R26]. | Label target/estimate/N/A; independent frame/timing/network counters |
| F11 | Static: rollback quarantines installation then copies backup called verified without digest validation/transaction recovery [R22]. | Verify before mutation; failure-safe copy/restart and distinct-version/data migration tests |
| F12 | Static trust gap: update function consumes descriptor SignatureStatus; hash comparison is not actual publisher verification [R27]. No deployed exploit proven. | Authenticate metadata; verify platform signature/chain; auto-update stays off pending proof |
| F13 | Static: Wake-on-LAN UDP send bypasses dry-run handling [R18]. Reviewer sent no packet. | Zero network/OS effect for all dry runs; guest traffic verification |
| F14 | Risk only: path/reparse checks precede later filesystem actions [R16]. No junction race exploited. | Handle-based confinement and native race tests; do not certify traversal protection |

| F16 | Static: receive tracking starts without expected SHA256 and finish marks Completed without calling finalize_and_verify; independent hash method exists [R15, R16]. No corrupted live transfer demonstrated. | Connect sender/receiver digests, batch-file coverage and integrity failures to engine completion; unit tests alone insufficient |

### P3

**F15 — Reproducibility closure:** moving tool selection/artifact aggregation needs exact resolved tool versions and output linkage, not a reproducible label. Pin or record/verify every compiler/tool/dependency resolution. [R03, R07]

### Blocking observations, not proven code exploits

A01 exact final ZIP/setup/portable/manifest absent in accessible delivery — BLOCKED, not checksum mismatch. A02 old incremental bundle cannot establish pinned commit — final provenance BLOCKED. A03 no authorized exact-RC guest/two-host execution — native/E2E BLOCKED. A04 final logs/driver trust/license/source closure unavailable — compliance/evidence BLOCKED.

**Counts:** P0 demonstrated 0; P1 6; P2 9 including unproven F14 risk; P3 1. These are finding counts, not executed product-test counts.

## 7. Security QA

| Security scope | Outcome | Remaining acceptance / reference |
|---|---|---|
| Authentication | Partial source; native BLOCKED | Verify actual engine denial, brute force and revoke [R11] |
| Encryption | BLOCKED | Security-summary string is not packet/protocol proof [R11] |
| Device pairing | Partial source; BLOCKED | Authenticated exchange, MITM/fingerprint tests [R11] |
| Trusted devices | BLOCKED / F07 | Durable allowlist/revocation, concurrent sessions |
| Session permissions | BLOCKED | View/control/clipboard/file/audio/power denial at engine boundary |
| Unattended Access | BLOCKED / F08 | Lock/login desktop, identity/MFA; caller assertions not authority |
| Windows DPAPI | Source only; BLOCKED | Native APIs visible [R29]; process/user/service profile tests |
| Credential Vault | BLOCKED | File ACL, entropy, corruption, recovery and plaintext leak checks |
| Step-Up PIN | FAIL | F05 |
| HMAC event verification | FAIL | F01 |
| Replay protection | FAIL design | F09; native adversarial test BLOCKED |
| Event spoofing | FAIL integrity requirement | Signed-event mutation differs from wrong-signature rejection |
| Clipboard abuse | Partial static; BLOCKED | Size/direction/UTF-8/loop policy [R20]; all engine paths/HTML/files |
| File traversal | Partial static; BLOCKED | Existing validation [R16]; native receive path/drive/UNC/ADS/device names |
| Junction/reparse point | NOT TESTED / risk | F14, no successful exploit claimed |
| Privilege escalation | NOT TESTED | Directory ACL/DLL search/privileged IPC need guest audit |
| Unauthorized power control | FAIL local boundary / remote BLOCKED | F05/F13, no remote exploit claim |
| Safe shutdown interlocks | Partial source; BLOCKED | Guards [R12, R18]; real busy state/races/cancel |
| Active file transfer interlocks | Partial source; BLOCKED | Receive hooks present [R15]; outgoing/clipboard/race coverage |
| Update security | Partial / F12 | Artifact/metadata publisher trust unresolved |
| Installer integrity | BLOCKED / F03 | Exact hash/signature/contents and ownership preservation |
| Driver authenticity | BLOCKED | Actual CAT trust + INF/DLL membership, not labels |
| Secret exposure | NOT TESTED comprehensively | No complete final source/binary/log sweep; no clean claim |
| Network listeners | Source partial; runtime BLOCKED | Loopback events [R19]; enumerate all binds/IPv4/IPv6/service context |
| IPC security | NOT TESTED comprehensively | Named-pipe ACL/impersonation not audited; DLL exports not automatically network endpoints |
| AGPL compliance | BLOCKED final distribution | Corresponding source/submodules/offer/notices/license payload |
| WDKTestCert | Prohibited; none installed by reviewer | Final guest driver-store verification BLOCKED |
| Hunonic SK02 | DISABLED source default [R18] | Maintain disabled adapter; no proprietary API bypass |

### usbmmidd_v2, origin and license

Build script pins download SHA256 `629b51e9944762bae73948171c65d09a79595cf4c771a82ebc003fbba5b24f51` from rustdesk-org/rdev release staging. This declaration is not an independently hashed final driver or vendor-origin attestation. [R07]

Amyuni's own forum discusses free personal/business use and distribution with conditions concerning repurposed INF/DLL components/distribution arrangements. That context does not certify this inaccessible package. Obtain actual applicable license/redistribution terms, vendor origin, version, archive hash and complete license files. No proven license violation is asserted. [R28]

Driver retest requires unchanged Secure Boot/DSE, recorded trust-chain/revocation policy and CAT membership. No test-root import, WDKTestCert installation or real-host driver install is authorized by this report.

## 8. Technical QA / QA harness integrity

F02 governs harness acceptance. Further static observations [R25]: AuthorizedSandbox is declarative; version is recorded not asserted; module errors swallowed; one service-name check is not full persistence inventory; Python/installer/uninstaller nonzero checks are useful; one-process sealing is not reopen proof. Broad process/profile cleanup makes this harness unsuitable for a normal workstation.

Build wrapper resets LASTEXITCODE before a command then checks it. That reset alone is not evidence failures are masked. Cleanup/failure propagation requires sentinel regression. [R07]

Proposed negative sentinels, NOT EXECUTED against product:

1. Missing required file, bad digest, duplicate manifest path: fail without overwriting expected evidence.
2. GUI exit 1/2/no window/missing DLL: fail.
3. Missing original build log: mark missing, never success-substitute.
4. Expired/untrusted signature/wrong catalog member: fail.
5. Nonzero child Python/setup/uninstall/rollback: preserve original failure through cleanup.
6. Skip tests intentionally: expose SKIPPED/NOT TESTED, forbid overall acceptance PASS.
7. Existing unrelated service/profile: refuse collision without changes.
8. Every-field HMAC mutation and replay-capacity overflow: preserve authentication/replay invariants.

Run corrected harness only in an authorized disposable guest with immutable pre-state and original logs. Developer-generated report is not independent acceptance.

## 9. Windows native verification — BLOCKED

No exact-RC PE/dependency/signature/native execution was possible without its bytes. Static code inspection is not Windows verification.

| Native gate | Outcome | Required rerun evidence |
|---|---|---|
| PE/imports/architecture | BLOCKED | Bounded MZ/PE parsing, x64 payload, dependency closure |
| Setup/portable signature/contents | BLOCKED | Exact hashes, inventory, trust result |
| Portable GUI | BLOCKED | Actual render/window/input/DLL binding |
| Installer | BLOCKED | Files/registry/services/drivers/tasks/startup pre/post diff |
| Uninstaller | BLOCKED | Product cleanup AND unrelated asset preservation |
| Upgrade/rollback | BLOCKED | Distinct releases, forced failure, binary/config hashes |
| Close/reopen/reboot | BLOCKED | Settings and vault continuity |
| DPAPI | BLOCKED | Encrypt→exit→decrypt, other-user/profile denial, corruption |
| Event bridge | BLOCKED | Synthetic hook→listener→UI, HMAC/replay negatives |
| No automatic service/driver | BLOCKED | Full inventory diff, not one name |
| No unexpected persistence | BLOCKED | Run keys/tasks/services/WMI/startup/profile changes |
| Headless/login/restore | BLOCKED | Authorized driver/hardware and real capture/topology |

Sandbox executable presence does not unlock these gates. No testing on Boss production host performed.

## 10. Disk persistence/recovery and UI/UX

New-runtime default is `%TEMP%\dauverse_remote_v1` unless DAUVERSE_DATA_DIR is supplied; selected write failures are discarded. Cleanup/write failure can lose state or replace keys. [R10] Trust, preferences and auxiliary history are not all durable just because audit/vault/journal files exist. [R11, R21, R23]

Rollback DOES quarantine the current installation before copying backup; this report does not claim stale-file overlay. The gap is unverified backup trust and recovery if copy/restart fails. [R22]

Future recovery cases: normal exit, forced write interruption, disk full/access denied, truncated JSON/vault, stale backup, downgrade/migration, temp cleanup, account/service-profile change, reinstall/uninstall-retain-data and reboot. Require explicit fail-closed recovery, not silent trust/PIN reset. **Native cases BLOCKED.**

Visual acceptance BLOCKED. F06 needs conspicuous native-unavailable state; F10 needs target/estimate/N/A labels; F04/F08 need intent distinct from confirmed state. [R09, R13, R17, R26]

Proposed UI tests: Vietnamese/IME/truncation, keyboard/accessibility, 100/150/200% DPI, contrast/themes, toolbar obstruction, Mini Control focus, toast dedup/no-focus-steal, destructive target/confirmation, unreachable vs powered-off, no success before native result. No pixel or interaction PASS inferred from source.

## 11. Regression and independent checks actually executed

Only reviewer-owned Python standard-library models and local input verification ran. No independent Rust/Flutter unit, native FFI or product E2E suite ran. No candidate code imported.

Model timestamp: `2026-11-25T13:30:34.605782+00:00` (20:30:34 Asia/Saigon). Method: `SOURCE_DERIVED_PYTHON_COUNTEREXAMPLES_NOT_RC_RUNTIME`.

| Check | Actual model outcome | Meaning |
|---|---|---|
| Ten unsigned HMAC-field mutations | Signature unchanged for all | F01 counterexample |
| Signed task_id control | Signature changes | Positive model control |
| Provenance normalization | UNKNOWN→COMPLETED | Unsigned trust data changes status |
| GUI exits 0/1/2 | Gate accepts | F02 counterexample |
| Negative crash exit | Gate rejects | Negative control, not GUI PASS |
| Valid headless request, approval=false | No modeled OS call; active=true | F04 |
| 2,049 events/2,048 FIFO | First identity evicted | F09, assuming validity window |

No real envelope/socket/event flood/GUI/power/driver action occurred. Models reproduce selected predicates, not compiler/ABI/Windows behavior. [L05]

Post-remediation regression required: F01 full payload; F02 sentinel failures; F03 collision host; F04 denied/no-driver/call-failure; F05 enrollment/change/lockout; F06 DLL unavailable; F07 crash/reopen; F08 actual configure/revoke; F09 window/capacity; F10 measured telemetry; F11 interrupted restore; F12 metadata/signature tamper; F13 zero-effect dry run; F14 native race; F16 engine integrity. Status remains NOT TESTED/BLOCKED until executed.
## 12. Performance methodology and acceptance design

**Actual Internet remote-desktop benchmark: BLOCKED.** No independent numeric performance claim is made. Source exposes local dirty-frame scanning, loopback and crypto measurements; those measure their own operations, not a complete remote desktop path. Source comments also limit the scope. Configured FPS and an estimated bitrate must not become measured telemetry. [R26, R23]

| Quantity | Required measurement | Invalid substitute |
|---|---|---|
| CPU processing time | Instrument a specified stage with monotonic timestamps; include queueing separately | Whole-session latency label |
| Encode latency | Capture-ready→encoded access unit, codec/profile/resolution and hardware path | Dirty-region scan duration |
| Decode latency | Encoded unit available→decoded frame, renderer queue separate | Sender encode time |
| Network RTT | Timestamped request/response on the actual negotiated session route | TCP loopback on one host |
| End-to-end input latency | Input event→visible response on receiving display; synchronized capture or high-speed camera | RTT alone or encode+decode sum |
| Actual FPS | Unique presented frames per second, drops/repeats and sampling window | Target FPS setting |
| Bandwidth | Session interface/transport byte deltas, direction and interval; include retransmits | Pixel-count estimate |
| CPU/GPU overhead | Baseline-subtracted host/client process and system counters; codec GPU engines, RAM/VRAM | One instantaneous percentage |

Proposed experiment: record hardware, OS, display/DPI, power state, build hashes, codec and route; idle, text/scroll, video and file-transfer workloads; same-LAN P2P, separate-network P2P where available, and verified relay. Include quiet baseline, warmup and at least three recorded steady-state runs per scenario. Record raw traces and p50/p95/p99 where sample count supports them, min/max, frame counts, disconnects and environmental changes. Keep transfer throughput distinct from screen bandwidth. An approved lab network impairment tool is optional, not permission to change Boss firewall/router.

Agree numerical SLOs **before** collecting acceptance data; none were supplied, so this report invents no performance threshold or PASS. Route evidence must demonstrate P2P/relay rather than infer it from perceived speed. One-machine loopback remains a diagnostic control only.

## 13. Controlled Windows pilot recommendation and two-machine procedure

**Recommendation now: do not install this RC on Boss production or general-use hosts.** The following is a future acceptance protocol, not authorization granted by this report. First fix/review P1 findings, deliver the exact immutable package and matching source/bundle/submodules, obtain complete manifest/logs, and pass isolated guest lifecycle checks. A newly approved candidate needs a new pinned baseline and hashes; never silently replace the bytes under this report's identity.

Use two explicitly approved disposable Windows machines/VMs A and B, separate test accounts and synthetic data only. Record owner consent, snapshot/backup, intended installation locations, connectivity and cleanup procedure. No paid endpoints. Keep production locked. Service, startup persistence, virtual-display driver and actual power transitions each require explicit scope approval on those test endpoints; skip/mark BLOCKED if absent. WDKTestCert is prohibited; keep Hunonic SK02 DisabledSmartPlugAdapter throughout.

| Phase | Procedure and observable acceptance evidence |
|---|---|
| 0 — Freeze | Hash ZIP and every required payload; reconcile bidirectional manifest coverage, omissions, duplicates and unexpected files. Verify bundle prerequisites, exact commit/gitlinks, Actions run/artifact identity, build inputs and code-signing chain. Preserve originals read-only. Stop on mismatch/missing mandatory evidence. |
| 1 — Isolated lifecycle | Snapshot before install. Inspect PE/imports/signatures offline first. Run portable under standard user, verify rendered GUI and native binding, close/reopen. Separately install/uninstall/rollback in clean and preexisting-product snapshots; retain file/registry/service/task/startup/network diffs and original exit codes. Verify unrelated RustDesk assets survive. |
| 2 — Authentication | Pair A↔B only through intended consent; reject wrong/expired/replayed credentials, untrusted device and revoked pairing. Confirm trust survives approved restart and revocation actually removes access. Re-pair without exposing real secrets. |
| 3 — Permission boundary | Receiver grants/denies each keyboard, mouse, clipboard, file, audio and power permission. Attempt from denied session, local UI and reconnect. Log native denial and zero side effect, not merely disabled buttons. Test Step-Up enrollment/change/retries/expiry. |
| 4 — Interactive input | Remote desktop, login/lock transitions where approved, mouse buttons/wheel/drag, key combinations, IME and Vietnamese Unicode. Record sender input and receiver result; test toolbar/Mini Control focus and interruption. |
| 5 — Clipboard and transfer | Unicode text, image formats, empty/large payloads, bidirectional clipboard policy. Transfer synthetic files/directories/Unicode names; compare independent source/destination SHA256. Test overwrite/cancel/resume/disconnect, traversal/UNC/ADS/reserved names and lab-only reparse/race cases. Confirm active-transfer journal tracks actual engine completion and integrity independently. |
| 6 — Transport | Demonstrate negotiated P2P and relay with diagnostic evidence; induce an approved connectivity loss, reconnect, authenticate anew as required and verify no permission expansion or duplicate transfers. If either route cannot be forced/observed, mark that route BLOCKED. |
| 7 — Media/display | Exercise audio with synthetic tones, mute and receiver consent; switch monitors, DPI/resolution and hotplug on both sides. Headless requires authorized signed driver and real capture/topology before/after app exit. Unit PASS is not Headless acceptance. |
| 8 — Synthetic AI events | Use a test producer only, never DAUVERSE AI production. Verify real Windows listener→HMAC/replay check→status/toast/notification path; mutate every field, duplicate IDs, expiry, restart and malformed/oversized inputs. Capture sanitized request/result and UI evidence. |
| 9 — Durability | Save settings/trust and DPAPI vault, exit all processes, reopen and reboot approved endpoint. Compare persisted semantics and encrypted bytes. Test other-user/profile denial, corrupt/truncated state, temp cleanup, disk-full/denied writes and interruption in disposable snapshots; prove no silent trust/PIN reset. |
| 10 — Optional persistence | Only if explicitly authorized: service and Windows Startup install/remove, correct account/ImagePath/ACLs, unattended access after reboot and complete revocation. Compare observed OS state with UI. Decline scope rather than install implicitly. |
| 11 — Power interlocks | Start with zero-side-effect dry run and disabled smart plug. On separately approved disposable endpoint only: verify remote permission, target identity, fresh Step-Up, shutdown confirmation, active-transfer veto and cancel. Do not perform actual shutdown/WOL/network sends without that approval. |
| 12 — Performance | Execute §12 scenarios, preserve route and counter traces, compare preagreed SLOs; distinguish processing, network and display latency. |
| 13 — Cleanup/restore | Uninstall, restore approved snapshots/config, inventory files/registry/tasks/services/drivers/listeners/startup and re-hash unrelated controls. Verify no unexpected persistence or credential remnants; record residual data retained by design. |

For every case: unique case ID, exact candidate hashes, operator, endpoint/OS, preconditions, expected result, observed result, timestamps, raw evidence and status. Screenshots alone cannot prove execution, signature trust, integrity or absence of persistence. Redact credentials without deleting test outcomes. Test failures remain FAIL; unavailable prerequisites remain BLOCKED. Never regenerate evidence from fabricated values to fill gaps.

## 14. Remediation required from AGY

All below are requests to the developer; reviewer made **no candidate patch**.

**P1 acceptance gates (before pilot):**
1. F01: bind all consumed security-relevant event content to a versioned, unambiguous authenticated representation; reject unsupported versions and unauthenticated trust metadata. Prove field-by-field tamper rejection and compatibility deliberately, not by permissive fallback.
2. F02: restore fail-closed evidence collection and required-case gates; qualify exact artifacts/logs and propagate real failures. Deliberately fail each gate and prove no PASS/report/manifest path hides it. Review remediation diff against unchanged acceptance requirements.
3. F03: verify ownership before stopping/deleting service/process/install state, preserve unrelated products, and test name/path collisions plus rollback. Avoid broad name-only destructive operations.
4. F04: report confirmed native state only after successful authorized OS operation and verified topology/driver trust; denied or failed activation must stay inactive/error. Provide real Windows headless evidence.
5. F05: separate first enrollment from credential change/reset; enforce current-owner reauthentication and appropriate retry/lockout boundary in backend, not just UI. Specify recovery without silent bypass.
6. F06: production native-unavailable calls must fail explicitly and visibly. Restrict synthetic fallback to unmistakable test-only paths; do not return generic success for unexecuted commands.

**P2/P3 closure or explicit risk disposition:** durable app-data and fail-closed write recovery (F07); actual OS service/unattended synchronization (F08); replay validity/capacity design (F09); truthful measured telemetry (F10); verified/transactional rollback recovery (F11); independent publisher verification (F12); zero-effect dry runs (F13); reparse-safe handle-based access and adversarial race tests (F14); pinned reproducible build closure (F15); actual receive-integrity linkage (F16). Preserve intended disabled hardware boundaries rather than add features.

**Delivery gate:** immutable final ZIP, complete required and unexpected-file manifest reconciliation, self-contained or explicitly complete bundle chain, recursive source/dependencies/licenses/SBOM, exact-run originals, signed-driver origin/license/trust evidence and independent sandbox lifecycle results. Missing mandatory files must fail the gate. Do not overwrite or regenerate historical results as though they were newly executed.

A remediation response should map each finding to a commit, rationale, negative/positive regression, exact candidate bytes and original evidence. Independent re-review is required; developer self-certification or green unit tests cannot close runtime gates. Even after closure, the maximum outcome within this task is **CONDITIONAL GO FOR CONTROLLED WINDOWS PILOT**, never production approval.
## 15. Evidence integrity and source register

### 15.1 Local evidence retained by reviewer

These are working evidence records supporting this **single report**, not additional acceptance reports. All paths below are relative to the reviewer workspace in §2. Records do not replace missing final RC bytes.

| ID | Local record | Scope / limitations |
|---|---|---|
| L01 | `local_input_hashes.json` | Independently computed digests for the two older Downloads inputs only |
| L02 | `prior_bundle_validation.json`; `bundle_validation.git` | Own empty repository: init exit 0, verify exit 1, exact missing prerequisite captured |
| L03 | `prior_manifest_audit.json`; `prior_snapshot/` | Historical ZIP inventory/manifest outcomes; not requested final baseline |
| L04 | `delivery_search.json` | Bounded filename discovery, not a global disk inventory |
| L05 | `independent_counterexamples.py`, `independent_counterexamples.json` | Safe synthetic expression models, explicit no candidate execution/network/OS power action |

L05 script SHA256: `eea00d842cf3afeccabd1ab618c89900f4973815e6fac1b25c2c87b645b61ef3`.
L05 result SHA256: `150e0e0c2bc275d906c656de1c421818f29dd123dd786c1b429cae02f2818051`.

Reproduction specification for L05: port the inspected canonical field selection into Python HMAC with a **synthetic** key; mutate excluded fields and one included control; evaluate the inspected GUI exit predicate, headless approval/state assignment and bounded replay FIFO. This validates counterexamples to those predicates, not implementation equivalence of every byte, Rust compiler behavior or Windows runtime correctness. No production event/key used.

Integrity distinctions:
- **Developer assertions:** old handoff prose, CI success and developer test reports. Useful leads, never promoted to independent PASS.
- **Provider observations:** GitHub commit/run pages and pinned raw source. Establish what was readable, not signed output provenance or source-to-binary identity.
- **Independent observations:** local hashes/bundle/manifest checks and own models, restricted to their actual inputs and scope.
- **Missing evidence:** exact final ZIP/binaries/manifests/original logs/native lifecycle; status stays BLOCKED. No missing file was silently ignored in a PASS denominator.
- **Unperformed analysis:** exhaustive CVE/secret/privileged IPC and all runtime attacks remain untested; source presence is not negative security proof.

External references were read-only. Source URLs below pin the full requested commit except history/run/vendor references. Line ranges in findings are navigation aids for that snapshot. No immutable local Git closure or archival copy of every remote page was available, which limits offline reproduction; fetch the exact pinned sources into the approved QA evidence store for a later retest. Source citations and R-identifiers are not artifact attestations.

### 15.2 External source register

| ID | Source | Exact reference |
|---|---|---|
| R01 | Pinned commit / final remediation diff | `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/commit/309948002371aba1407532c9ba8d9d216a02e771` |
| R02 | Requested Actions run metadata | `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/actions/runs/45603088230` |
| R03 | Windows workflow | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/.github/workflows/dauverse-windows-build.yml` |
| R04 | Registry/installer remediation history | `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/commit/ce6b860` |
| R05 | Headless/GUI remediation history | `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/commit/d33ef4e` |
| R06 | DPAPI/harness remediation history | `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/commit/e88c97182954315ac1eb6490bfa6db9dc7d71828` |
| R07 | Windows build script | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/scripts/windows/build_windows_release.ps1` |
| R08 | NSIS installer | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/installer/nsis/dauverse_setup.nsi` |
| R09 | Headless implementation | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/headless.rs` |
| R10 | Runtime initialization/storage | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/mod.rs` |
| R11 | Security state/PIN/vault | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/security.rs` |
| R12 | Native FFI dispatch | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/ffi.rs` |
| R13 | Dart bridge/fallback | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/flutter/lib/dauverse/bridge/dauverse_bridge.dart` |
| R14 | Flutter engine launcher integration | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/flutter/lib/main.dart` |
| R15 | Engine receive hooks | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/ui_cm_interface.rs` |
| R16 | Transfer guard/journal/hash functions | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/transfer_guard.rs` |
| R17 | Service/unattended controller | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/service_ctrl.rs` |
| R18 | Smart power/adapters/dry-run | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/smart_power.rs` |
| R19 | Event bridge/authentication/replay | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/ai_bridge.rs` |
| R20 | Clipboard policy | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/clipboard_guard.rs` |
| R21 | Notification state | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/notifications.rs` |
| R22 | Windows rollback | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/scripts/windows/rollback_windows_release.ps1` |
| R23 | Session tools/state | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/session_tools.rs` |
| R24 | Submodule declaration | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/.gitmodules` |
| R25 | Windows verification/packaging harness | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/scripts/windows/verify_and_package_windows_rc.ps1` |
| R26 | Performance helpers and scope | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/performance.rs` |
| R27 | Update descriptor verification | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/update_center.rs` |
| R28 | Amyuni vendor driver discussion/terms context | `https://www.amyuni.com/forum/viewtopic.php?t=3323` |
| R29 | DPAPI crypto utility/imports | `https://raw.githubusercontent.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/309948002371aba1407532c9ba8d9d216a02e771/src/dauverse/crypto_util.rs` |

### 15.3 Local evidence file digests

Digests independently re-read at report finalization; these attest file identity only, not the truth of a developer assertion.

| Record | SHA256 |
|---|---|
| `local_input_hashes.json` | `9736f2af2c095d05715b14b746a16dd7a05c2a41ea5aa471f5fd386c33b001d4` |
| `prior_bundle_validation.json` | `9e8e05f1cb0b9e54185587c06c7c6066e157ae0f6e95bf58a76bf3600ef8488b` |
| `prior_manifest_audit.json` | `dde2604f285167ec5efa8a9b2f3798f7b5c550ebaac7b0d20ca63d7fe54f97d9` |
| `delivery_search.json` | `22da15033fe98dfde421a28807adf8f3af0ad22ff4b768b787c0b7b2fbea819a` |
| `independent_counterexamples.py` | `eea00d842cf3afeccabd1ab618c89900f4973815e6fac1b25c2c87b645b61ef3` |
| `independent_counterexamples.json` | `150e0e0c2bc275d906c656de1c421818f29dd123dd786c1b429cae02f2818051` |

## 16. Final disposition

**FINAL VERDICT: FAIL.**

- Confirmed source/evidence defects F01-F06 block controlled Windows pilot acceptance.
- Exact package integrity, source/binary correspondence, real Windows lifecycle, DPAPI reopen, remote functionality and performance remain **BLOCKED**, not PASS and not demonstrated runtime failures.
- Inventory: **0 demonstrated P0; 6 P1; 9 P2 (including F14 unproven risk); 1 P3**. A01-A04 are separate blocking observations, not extra exploit findings.
- No installation recommendation for the current RC. Use the isolated and separately authorized two-host protocol only after the reopening gates; retain unavailable cases as BLOCKED.
- This review did not modify the candidate, install/run it, install a driver/service, change production controls or incur a paid service charge.

**Production remains LOCKED. Not Production Approved.**

# CODEX INDEPENDENT RE-QA HANDOFF — DAUVERSE REMOTE DESKTOP V1 (WINDOWS RC2)

- **Task ID:** `DREMOTE-V1-REMEDIATION-005` -> Independent Re-QA Input Package
- **Repository:** `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP`
- **Branch:** `develop/dauverse-remote-v1` (`master` untouched at upstream `a0c0963c483fc8f1aeed4547787d1673adcb583c`)
- **Pinned Submodule:** `libs/hbb_common` at `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb`
- **Prior Baseline (RC1):** `309948002371aba1407532c9ba8d9d216a02e771`
- **Prior Independent QA Report Included Unaltered:** `QA/DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md` (`SHA-256: f07b61edbd82a376cc5e3f854d72d0cc3331735094bc0631e37fbc9ebc60a913`)
- **Production Status:** **`LOCKED`** (Maximum possible Re-QA disposition remains Conditional Go for Controlled Windows Pilot, never Production Approved).

---

## 1. Archive Layout (`DAUVERSE_REMOTE_DESKTOP_V1_WINDOWS_RC2_COMPLETE_QA.zip`)

Every file inside the archive is enumerated in root `SHA256_MANIFEST.txt` using POSIX `/` relative paths (zero symlinks, zero absolute paths, zero `..` traversal, zero unlisted files):

1. `RELEASE/`
   - `DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` (NSIS x64 installer with SCM/process ownership checks & SHA-256 rollback backup manifest)
   - `DAUVERSE_REMOTE_DESKTOP_V1_PORTABLE.exe` (single-file portable self-extractor)
   - `librustdesk.dll` & `dylib_virtual_display.dll` (staged native x64 DLLs exposed directly for offline PE/import/export inspection without running installers)
   - `usbmmidd_v2/` (`usbmmidd.cat`, `usbmmIdd.inf`, `x64/usbmmIdd.dll`, `License.txt` — unmodified WHQL-signed driver files for offline catalog & license verification; never auto-installed)
   - `BUILD_PROVENANCE.json` (exact RC2 commit SHA, `libs/hbb_common` SHA, CI run metadata, resolved `rustc -Vv`, `flutter --version --machine`, `clang`, `makensis`, `vcpkg` SHA, lockfile digests, and output SHA-256s)
   - `DRIVER_PROVENANCE_AND_LICENSE.json` & `usbmmidd_v2_License.txt`
   - `SIGNING_STATUS.txt` (`UNSIGNED` — auto-update hard-blocked)
   - `INITIAL_BUILD_SHA256_MANIFEST.txt` (frozen pre-test build manifest preserved untouched per Report §4.3)
2. `LOGS/`
   - `WINDOWS_NATIVE_BUILD.log` & `GITHUB_ACTIONS_BUILD_CONSOLE.log` (complete compiler + Rust/Flutter test output)
   - `WINDOWS_RC_VERIFICATION.log` & `GITHUB_ACTIONS_VERIFY_CONSOLE.log` (complete Windows sandbox execution log)
3. `EVIDENCE/`
   - `QA_HARNESS_NEGATIVE_SELFTEST.json` (10 negative harness sentinels verified to fail closed)
   - `WINDOWS_RC_VERIFICATION_REPORT.json` & `WINDOWS_RC_VERIFICATION_REPORT.md`
   - `LINUX_PREFLIGHT/` (local preflight Rust unit/security logs, 3-process `.so` security matrix JSON, benchmark JSON, Flutter fail-closed UI test log)
4. `QA/`
   - `DAUVERSE_REMOTE_V1_INDEPENDENT_QA_REPORT.md` (verbatim `f07b61ed...`)
   - `FINDINGS_REMEDIATION_MATRIX.md` (complete 16-finding `F01`–`F16` + `A01`–`A04` matrix)
   - `CODEX_REQA_WINDOWS_RC2_HANDOFF.md` (this document)
5. `DOCS/` & `LICENSES/`
   - `FEATURE_ACCEPTANCE_MATRIX.md`, `HUONG_DAN_BOSS.md`, `DOCS/*.md`
   - `LICENSE`, `LICENCE`, `THIRD_PARTY_NOTICES`, `LICENSE_COMPLIANCE_REPORT.md`, `UPSTREAM_MANIFEST.json`, `SBOM.spdx.json`, `usbmmidd_v2_License.txt`
6. `BUNDLE/`
   - `DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle` (full-history self-contained Git bundle)
   - `BUNDLE_BARE_VERIFY.txt`
7. `SOURCE/`
   - Complete clean checkout of RC2 `HEAD` + `SOURCE/libs/hbb_common` at `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb`.

---

## 2. Offline Zero-Execution Verification Steps (Safe on Any Host)

Codex can verify provenance, manifest closure, bundle self-containment, source diffs, PE headers, and WHQL catalog trust **without executing any candidate `.exe` or `.dll`**:

### A. Bidirectional Manifest & No-Unexpected-Files Check (PowerShell / Python)
```powershell
$Root = (Resolve-Path ".\extracted_rc2").Path.TrimEnd('\')
$Listed = @{}
Get-Content "$Root\SHA256_MANIFEST.txt" | Where-Object { $_ } | ForEach-Object {
    if ($_ -notmatch '^([0-9a-f]{64})\s\s(.+)$') { throw "Malformed: $_" }
    $Listed[$Matches[2]] = $Matches[1]
    $p = Join-Path $Root ($Matches[2] -replace '/', '\')
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing: $($Matches[2])" }
    $actual = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Matches[1]) { throw "Mismatch: $($Matches[2])" }
}
Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
    if ($rel -ne "SHA256_MANIFEST.txt" -and (-not $Listed.ContainsKey($rel))) {
        throw "Unlisted file: $rel"
    }
}
```

### B. Self-Contained Bare Repository Bundle Verification (`A02` / `L02`)
```powershell
git init --bare .\clean_bare_verify.git
git -C .\clean_bare_verify.git bundle verify .\extracted_rc2\BUNDLE\DAUVERSE_REMOTE_DESKTOP_V1_RC2.bundle
# Expected: exit code 0 ("The bundle records a complete history.")
```

### C. Offline WHQL Catalog & License Check (`F04`, `A02`)
```powershell
Get-AuthenticodeSignature .\extracted_rc2\RELEASE\usbmmidd_v2\usbmmidd.cat
Test-FileCatalog -CatalogFilePath .\extracted_rc2\RELEASE\usbmmidd_v2\usbmmidd.cat -Path .\extracted_rc2\RELEASE\usbmmidd_v2\x64\usbmmIdd.dll -Detailed
Test-FileCatalog -CatalogFilePath .\extracted_rc2\RELEASE\usbmmidd_v2\usbmmidd.cat -Path .\extracted_rc2\RELEASE\usbmmidd_v2\usbmmIdd.inf -Detailed
```

---

## 3. Authorized Disposable Guest Re-Execution (Optional — Only Inside Isolated Sandbox/VM)

Only inside an explicitly authorized disposable Windows VM/Sandbox (never on Boss's host):
```powershell
pwsh -NoProfile -File .\extracted_rc2\SOURCE\scripts\windows\verify_and_package_windows_rc.ps1 `
  -ReleaseDir .\extracted_rc2\RELEASE `
  -RepoRoot .\extracted_rc2\SOURCE `
  -AuthorizedSandbox
```

---

## 4. Honest Remaining `BLOCKED` / `NOT TESTED` Items for Re-QA

- **Two-Machine Live Remote Session (`BLOCKED`):** P2P/Relay negotiation, mouse/keyboard/Vietnamese IME input, WASAPI audio, bidirectional Explorer clipboard/file transfer, and §12 end-to-end latency/FPS benchmarks require two authorized Windows test machines (`Phase 2`–`Phase 7`, `Phase 12` of Report §13).
- **Physical Monitorless GPU & Reboot Persistence (`BLOCKED`):** Installing/activating `usbmmidd_v2` or Windows Service `RustDesk` across OS reboot requires explicit pilot endpoint authorization (`Phase 9`–`Phase 10`).
- **Hunonic SK02 Hardware Control (`BLOCKED`):** `DisabledSmartPlugAdapter` remains enforced due to lack of public vendor API.
- **Kernel-Level NTFS Reparse Race Fuzzing & Privileged Named-Pipe ACL Audit (`NOT TESTED`):** Confined handle + `GetFinalPathNameByHandleW` checks were added (`F14`), while concurrent oplock/junction fuzzing and exhaustive upstream IPC audits remain `NOT TESTED`.

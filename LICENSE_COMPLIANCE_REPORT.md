# DAUVERSE REMOTE DESKTOP V1.0 — LICENSE COMPLIANCE REPORT

**Task ID:** `DREMOTE-V1-MASTER-001`  
**Audit Date:** `2026-11-24`  
**Primary Product License:** **GNU Affero General Public License v3.0 (`AGPL-3.0`)**

---

## 1. Executive Summary

`DAUVERSE REMOTE DESKTOP V1.0` is developed as a compliant open-source derivative of `rustdesk/rustdesk` (`v1.5.3`, commit `a0c0963c483fc8f1aeed4547787d1673adcb583c`).

- **No Proprietary Closure:** The software is licensed and distributed strictly under **AGPL-3.0**. No claim or assumption of closed-source commercialization is made.
- **Verbatim License Preservation:** Upstream `LICENCE` (662 lines, SHA-256 `8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef`) is preserved byte-for-byte, and an identical `LICENSE` file is included at the repository root.
- **Zero New Unvetted Dependencies:** All new Rust subsystems in `src/dauverse/*` reuse crates already locked and vetted in upstream `Cargo.lock` (`hbb_common::sysinfo`, `sha2`, `wol-rs`, `system_shutdown`, `reqwest`, `chrono`, `uuid`, `hex`, `serde`, `serde_json`, `winapi`, `windows`). Zero duplicate or unverified third-party Rust crates were added.

---

## 2. Upstream & Ecosystem License Compatibility Matrix

| Component | Repository | Pinned Version / Commit | License | AGPL-3.0 Compatibility | Integration Method |
|---|---|---|---|---|---|
| RustDesk Client & Core | `rustdesk/rustdesk` | `a0c0963c483fc8f1aeed4547787d1673adcb583c` (`1.5.3`) | `AGPL-3.0` | Native | Direct fork foundation |
| `hbb_common` | `rustdesk/hbb_common` | `450cc1d7b729cfa8d19b5a7527c9cc2fe54cf5eb` | `AGPL-3.0` | Native | Git submodule |
| `rustdesk-server` (`hbbs`/`hbbr`) | `rustdesk/rustdesk-server` | `680b60395ecf99a76f74a1d934e453bb6e5e0aa2` (`1.1.16`) | `AGPL-3.0` | Native | Separate self-host server container |
| `usbmmidd_v2` | `Amyuni Technologies Inc.` (`rustdesk-org/rdev` staging `629b51e9...`) | `v2` (`usbmmidd.cat` WHQL) | `Amyuni Freeware Redistribution Notice` (`usbmmidd_v2/License.txt` preserved unaltered) | Separate unmodified OS driver files (not linked into AGPL binary; opt-in only; free-version prompt disclosed) | Staged in `usbmmidd_v2/` with verbatim `License.txt`; never auto-installed |
| `RustDeskIddDriver` | `rustdesk-org/RustDeskIddDriver` | `f779474e130f641d82102b5128000c6f5c079460` (`v0.4`) | `MS-PL` | Excluded (`BLOCKED_DO_NOT_INSTALL`) | Rejected and excluded due to self-signed `WDKTestCert` SHA-1 certificate |
| `Virtual-Display-Driver` | `VirtualDrivers/Virtual-Display-Driver` | `d7244969b2aa8bb38e76d79505eda217996cefea` (`25.7.23`) | `MIT` | Compatible | Documented fallback driver (not bundled) |
| `sysinfo` | `GuillaumeGomez/sysinfo` (`rustdesk-org/sysinfo`) | `90b1705d909a4902dbbbdea37ee64db17841077d` (`0.29.10`) | `MIT` | Compatible | Linked crate via `Cargo.lock` |
| `LibreHardwareMonitor` | `LibreHardwareMonitor/LibreHardwareMonitor` | `9e2d677cefff5c614ecc38da88fbc447eb478e2a` (`v0.9.6`) | `MPL-2.0` | Compatible | Optional external HTTP/WMI bridge (not linked) |
| Flutter Framework | `flutter/flutter` | `3.50.0` | `BSD-3-Clause` | Compatible | UI framework |

---

## 3. AGPL-3.0 Section 13 & Attribution Obligations

1. **Source Availability:** Because this repository is hosted at `https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP` on branch `develop/dauverse-remote-v1`, complete corresponding source code—including build scripts (`build.py`, `scripts/windows/build_windows_release.ps1`) and manifests—remains available alongside any binary or network-accessible deployment.
2. **Modification Notices:** All DAUVERSE additions are clearly isolated under `src/dauverse/`, `flutter/lib/dauverse/`, `scripts/`, `installer/`, `deploy/`, and documented in `UPSTREAM_MANIFEST.json` and `THIRD_PARTY_NOTICES`.
3. **Secret Hygiene Audit:** Automated pre-commit scanning verified zero API keys, OAuth tokens, passwords, session cookies, internal `DAUVERSE AI` proprietary code, or personal Boss data exist in the repository.

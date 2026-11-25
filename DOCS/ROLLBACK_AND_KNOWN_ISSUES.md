# ROLLBACK INSTRUCTIONS & HONEST ENVIRONMENT BLOCKERS (RC1 REMEDIATED)

## 1. Safe Windows Rollback Instructions

### Method A — Automated Rollback Script (Recommended)
Run PowerShell as Administrator:
```powershell
E:\DAUVERSE_REMOTE_DESKTOP\SOURCE\scripts\windows\rollback_windows_release.ps1 `
  -InstallDir "E:\Program Files\DAUVERSE Remote Desktop" `
  -BackupDir "E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release"
```
This stops the registered SCM service (`RustDesk` — `DAUVERSE Remote Desktop Host Service`) if running, quarantines the current installation folder with a timestamp (never deleting files destructively), restores the pre-upgrade snapshot created by `DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe` at `E:\DAUVERSE_REMOTE_DESKTOP\BACKUP\previous_release`, and restarts the service only if `-RestartService` is requested.

### Method B — Clean Uninstallation
Run `"E:\Program Files\DAUVERSE Remote Desktop\Uninstall.exe"` (or Windows `Installed Apps -> DAUVERSE REMOTE DESKTOP V1.0 -> Uninstall`). This stops and removes the `RustDesk` SCM service if registered, deletes Start Menu/Desktop shortcuts, and cleans the application directory without touching any external `DAUVERSE AI` or personal directories.

---

## 2. Honest Remaining Blockers & Classifications (`DREMOTE-V1-RC1-NEXT-002`)

1. **GitHub Push Attachment (`BLOCKED_PROJECT_RESOURCE_ATTACHMENT`):**
   - `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP` exists as a public fork on GitHub, and `gh` has read/admin metadata visibility, but `git push` from the isolated Antigravity VM returns `HTTP 403` until Boss attaches `trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP` in the Antigravity Project's **Resources** panel (single-repository scope only — zero full-account scope required). Once attached (or pushed from the included Git bundle), `.github/workflows/dauverse-windows-build.yml` can be dispatched on GitHub's free public-repo `windows-2022` runner (`0 VNĐ`).
2. **Native Windows `.exe` Compilation & Live 2-PC Windows E2E Runtime (`BLOCKED` in Linux Cloud VM):**
   - Antigravity Remote Agent runs in an Ubuntu 24.04 Linux x86_64 cloud VM without MSVC, Windows 11 SDK, or physical RTX 3060 hardware. No fake `.exe` files are generated.
   - `Cargo.toml` (`winapi` `dpapi` + `winbase`), CMake `CARGO_TARGET_DIR` (`librustdesk.dll`), PowerShell `$LASTEXITCODE` checks, NSIS `DRIVE_FIXED` + SCM alignment, and SHA-pinned GitHub Actions workflow (`dauverse-windows-build.yml`) are verified and ready for Windows CI or local PowerShell execution.
3. **Smart Plug `Hunonic SK02` Direct API (`BLOCKED` — No Official Public API):**
   - Official Hunonic documentation provides mobile app control only and publishes zero public REST, MQTT, or OpenAPI interface. Per Section 6, `DisabledSmartPlugAdapter` remains active (`BLOCKED`) with zero reverse-engineered endpoints or credential extraction.
4. **Virtual Display Driver `RustDeskIddDriver v0.4` (`BLOCKED_DO_NOT_INSTALL`):**
   - Cryptographic inspection proved `RustDeskIddDriver v0.4` uses a self-signed `WDKTestCert` SHA-1 certificate (`D1:DB:B6:72:D5:A5:00:B9:80:96:89:CA:EA:1C:E4:9E:79:97:67:F0`) and imports it into `LocalMachine\Root`. Hard-blocked; only WHQL-signed `usbmmidd_v2` (`Microsoft Windows Hardware Compatibility Publisher`) or passive HDMI 2.0 Dummy Plug is recommended once Boss approves Headless deployment.
5. **Code Signing Certificate (`UNSIGNED`) & Section 7 Host Non-Deployment:**
   - Binaries are explicitly marked `UNSIGNED` with silent auto-update hard-blocked (`UpdateCenterManager::verify_package`). Per Section 7, no Windows Service, virtual display driver, or unattended access is installed on Boss's PC yet.
6. **Multi-Model Exact Named Routing (`MODEL_ROUTING_UNSUPPORTED`):**
   - The Antigravity subagent runtime exposes `Model` enum `["inherit", "flash_lite", "flash", "pro"]` (host tier aliases) rather than cross-family named selectors (`Carbon High` -> `Neon High/Extra` -> `Hydrogen`). Reported transparently per Section 2 alongside a standalone immutable/remediated QA handoff package for external `Neon` / `Codex` sessions.

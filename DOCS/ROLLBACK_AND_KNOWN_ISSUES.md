# ROLLBACK INSTRUCTIONS & KNOWN ISSUES / HONEST LIMITATIONS

## 1. Safe Windows Rollback Instructions

### Method A — Automated Rollback Script (Recommended)
Run PowerShell as Administrator:
```powershell
E:\DAUVERSE_REMOTE_DESKTOP\SOURCE\scripts\windows\rollback_windows_release.ps1 `
  -InstallDir "E:\Program Files\DAUVERSE Remote Desktop" `
  -BackupDir "E:\Program Files\DAUVERSE_ROLLBACK_BACKUP"
```
This stops `DauverseRemoteService`, quarantines the current folder with a timestamp (never deleting files destructively), restores the pre-upgrade snapshot created automatically by `DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe`, and restarts the service.

### Method B — Clean Uninstallation
Run `"E:\Program Files\DAUVERSE Remote Desktop\Uninstall.exe"` (or Windows `Installed Apps -> DAUVERSE REMOTE DESKTOP V1.0 -> Uninstall`). This stops and removes `DauverseRemoteService`, deletes Start Menu/Desktop shortcuts, and cleans the application directory without touching any external `DAUVERSE AI` or personal directories.

---

## 2. Known Issues & Honest Environment Blockers (V1.0 RC1)

Per Master Build Order Sections 02, 16, 27, 30, 31, and 32, the following items are transparently classified:

1. **Native Windows `.exe` Compilation & Live 2-PC Windows Verification (`BLOCKED` in Linux Cloud VM):**
   - Antigravity Remote Agent runs in an Ubuntu 24.04 Linux x86_64 cloud VM without Microsoft Visual C++ (`MSVC`), Windows 11 SDK, or physical RTX 3060 hardware.
   - **Mitigation Delivered:** Complete integrated Rust + Flutter source code, native Linux desktop build & live Xvfb UI verification, 1-command Windows native build script (`scripts/windows/build_windows_release.ps1`), NSIS installer (`installer/nsis/dauverse_setup.nsi`), and SHA-pinned manual GitHub Actions `windows-2022` workflow (`.github/workflows/dauverse-windows-build.yml`) are ready for immediate execution.
2. **Live Smart Plug Hardware Integration (`BLOCKED` — Model Unspecified):**
   - Boss's smart plug brand/model is not yet specified. `SmartPlugAdapter` interface and safety interlocks are complete, with `DisabledSmartPlugAdapter` active by default and `SimulatedSmartPlugAdapter` clearly labeled `SIMULATED` in unit tests.
3. **Code Signing Certificate (`UNSIGNED`):**
   - No Authenticode PFX certificate has been provisioned yet. Build scripts and Update Center explicitly report **`UNSIGNED`** and disable silent background auto-updates until signed.
4. **Closed Desktop AI Apps Without Official Hooks (`UNKNOWN` / `UNSUPPORTED`):**
   - Standalone desktop chat GUIs without official hooks or structured logs are marked `UNKNOWN` rather than scraping memory, cookies, or OAuth credentials.

# SMART POWER MANAGEMENT, HUNONIC SK02 SURVEY & ASUS PRIME H610M-K D4 BIOS GUIDE

## 1. Safe Power Operations & Mandatory Interlocks

`DAUVERSE REMOTE DESKTOP V1.0` (`src/dauverse/smart_power.rs`) provides:
- **Wake-on-LAN (WoL):** Dispatches standard 102-byte Magic Packets (`6x FF` + `16x MAC`) over LAN broadcast (`255.255.255.255:9`) or a specified target endpoint.
- **Lock / Sleep / Restart / Safe Windows Shutdown:** Protected by **Step-Up Authentication** and pre-flight **AI Workload Interlocks**:
  - Warns and blocks accidental shutdown/restart/sleep if **Claude / Codex / Antigravity** tasks are `RUNNING` or `WAITING_APPROVAL`.
  - Warns and blocks if **ComfyUI** is actively rendering video/images.
  - Warns and blocks if **File Transfers** are in progress.
  - When `dry_run_only == false` and all interlocks + step-up authentication pass, invokes real OS lock (`LockWorkStation` / `loginctl lock-session`) or OS power transition (`system_shutdown::{sleep, reboot, shutdown}`).
- **Hard AC Cut Protection:** Network loss (`NETWORK_UNREACHABLE`) is **never** treated as `CONFIRMED_OFF`. Smart plug AC power-off is hard-blocked unless the OS is confirmed shut down.

---

## 2. Official Survey: `Hunonic SK02` Wi-Fi Smart Plug (`Section 6`)

- **Surveyed Device:** **Hunonic SK02** (`https://hunonic.com/san-pham/o-cam-thong-minh-hunonic-sk02/`)
- **Hardware Specifications:** `90–240V AC 50Hz`, `16A` max load (`~3500–4000W`), `Wi-Fi 2.4GHz IEEE 802.11 b/g/n`, controlled via the proprietary **Hunonic** mobile application (iOS / Android).
- **Official API Verification Result:**
  - Hunonic publishes **NO official public HTTP REST API, local LAN protocol, MQTT specification, or OpenAPI developer documentation** for `Hunonic SK02`.
  - Community third-party scripts (e.g., `home-assistant-tools/vietnam-hunonic`) explicitly document that their integration was produced by **reverse-engineering the Hunonic Android APK (Hermes bytecode) and MITM traffic capture**, and causes **single-session eviction** (logging the user out of the official Hunonic phone app).
- **Strict Section 6 Decision (`BLOCKED` — `DisabledSmartPlugAdapter` Retained):**
  - Per Section 6 rules (*"Không suy diễn API nếu không có tài liệu. Không trích xuất credential, không điều khiển ổ cắm thật. Giữ DisabledSmartPlugAdapter nếu chưa có interface chính thức."*):
    1. **Zero undocumented API guessing or reverse-engineered endpoints** are included.
    2. **Zero Hunonic credentials or tokens** are requested or stored.
    3. **`DisabledSmartPlugAdapter`** remains the active default in `src/dauverse/smart_power.rs`, returning `BLOCKED` with full diagnostic rationale.
- **Recommended Safe Operational Workflow with `Hunonic SK02`:**
  1. Set **`Restore AC Power Loss = Power On`** in the `ASUS PRIME H610M-K D4` BIOS (below).
  2. To **boot** the PC remotely from the office: either send a **Wake-on-LAN** packet (if standby AC was left ON) or toggle **ON** `Hunonic SK02` inside Boss's official **Hunonic mobile app** (zero session conflict).
  3. To **shut down** safely: use **Safe Windows Shutdown** inside `DAUVERSE REMOTE` (which checks AI/ComfyUI/File Transfer interlocks first), wait until the host is confirmed powered down, and only then optionally switch off `Hunonic SK02` in the Hunonic mobile app if desired.

---

## 3. ASUS PRIME H610M-K D4 — BIOS & Windows WoL Setup Guide

> **Verification Note:** Menu labels below correspond to ASUS UEFI BIOS Utility (Advanced Mode) for **ASUS PRIME H610M-K D4**. Please verify the exact menu wording against your installed BIOS version before saving changes. Antigravity never modifies BIOS settings automatically.

### Step A — Enable AC Power Recovery & PCIe/LAN Wake in ASUS UEFI BIOS
1. Power on the home PC and press `Del` or `F2` to enter **ASUS UEFI BIOS Utility**, then press `F7` for **Advanced Mode**.
2. Navigate to **`Advanced` > `APM Configuration`**:
   - **`Restore AC Power Loss`**: Set to **`Power On`** (allows turning the PC on remotely via `Hunonic SK02` AC power-on after a graceful shutdown).
   - **`Power On By PCI-E`** (or **`Power On By PCI-E/PCI`**): Set to **`Enabled`** (required for onboard Realtek LAN Wake-on-LAN).
   - **`ErP Ready`**: Set to **`Disabled`** (keeps standby 5Vsb NIC power active during S5 shutdown for Wake-on-LAN).
3. Press `F10` to review changes, confirm only the above items changed, and save.

### Step B — Enable Wake-on-LAN in Windows 11 Pro
1. Open **Device Manager** -> **Network adapters** -> Right-click **Realtek PCIe GbE Family Controller** -> **Properties**:
   - **Advanced** tab: Enable **`Wake on Magic Packet`**.
   - **Power Management** tab: Check **`Allow this device to wake the computer`** and **`Only allow a magic packet to wake the computer`**.
2. Disable Windows Fast Startup (`Control Panel > Power Options > Choose what the power buttons do > Turn on fast startup` -> **Unchecked**) if hybrid S4 shutdown blocks S5 Magic Packets.

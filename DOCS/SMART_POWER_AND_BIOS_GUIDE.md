# SMART POWER MANAGEMENT & ASUS PRIME H610M-K D4 BIOS GUIDE

## 1. Safe Power Operations & Mandatory Interlocks

`DAUVERSE REMOTE DESKTOP V1.0` (`src/dauverse/smart_power.rs`) provides:
- **Wake-on-LAN (WoL):** Dispatches standard 102-byte Magic Packets (`6x FF` + `16x MAC`) over LAN broadcast or an authorized WoL gateway.
- **Lock / Sleep / Restart / Safe Windows Shutdown:** Protected by **Step-Up Authentication** and pre-flight **AI Workload Interlocks**:
  - Warns and blocks accidental shutdown/restart/sleep if **Claude / Codex / Antigravity** tasks are `RUNNING` or `WAITING_APPROVAL`.
  - Warns and blocks if **ComfyUI** is actively rendering video/images.
  - Warns and blocks if **File Transfers** are in progress.
- **Hard AC Cut Protection:** Network loss (`NETWORK_UNREACHABLE`) is **never** treated as `CONFIRMED_OFF`. Smart plug AC power-off is hard-blocked unless the OS is confirmed shut down.

---

## 2. ASUS PRIME H610M-K D4 — BIOS & Windows WoL Setup Guide

> **Important Verification Note:** Menu labels below correspond to ASUS UEFI BIOS Utility (Advanced Mode) for **ASUS PRIME H610M-K D4**. Please verify the exact menu wording against your installed BIOS version before saving changes. Antigravity never modifies BIOS settings automatically.

### Step A — Enable AC Power Recovery & PCIe/LAN Wake in ASUS UEFI BIOS
1. Power on the home PC and press `Del` or `F2` to enter **ASUS UEFI BIOS Utility**, then press `F7` for **Advanced Mode**.
2. Navigate to **`Advanced` > `APM Configuration`**:
   - **`Restore AC Power Loss`**: Set to **`Power On`** (allows turning the PC on remotely via Smart Plug AC toggle after a graceful shutdown or power outage).
   - **`Power On By PCI-E`** (or **`Power On By PCI-E/PCI`**): Set to **`Enabled`** (required for onboard Realtek LAN Wake-on-LAN).
   - **`ErP Ready`**: Set to **`Disabled`** (if `ErP` is enabled, standby 5Vsb power to the NIC is cut during S5 shutdown, preventing Wake-on-LAN).
3. Press `F10` to review changes, confirm only the above items changed, and save.

### Step B — Enable Wake-on-LAN in Windows 11 Pro
1. Open **Device Manager** -> **Network adapters** -> Right-click **Realtek PCIe GbE Family Controller** -> **Properties**:
   - **Advanced** tab: Enable **`Wake on Magic Packet`** and disable **`Energy Efficient Ethernet`** / **`Green Ethernet`** if WoL drops after long idle periods.
   - **Power Management** tab: Check **`Allow this device to wake the computer`** and **`Only allow a magic packet to wake the computer`**.
2. Disable Windows Fast Startup (which leaves S4 hybrid hibernation locks that can block S5 WoL on some chipsets):
   - `Control Panel > Power Options > Choose what the power buttons do > Turn on fast startup` -> **Unchecked**.

---

## 3. Smart Plug Adapter Status (`BLOCKED` — Hardware Model Unspecified)

- **Implemented in Code:** `SmartPlugAdapter` trait (`src/dauverse/smart_power.rs`), `DisabledSmartPlugAdapter` (active default), and `SimulatedSmartPlugAdapter` (explicitly labeled `SIMULATED` for automated testing).
- **Current Blocker:** Live Smart Plug cloud/LAN hardware API integration is marked **`BLOCKED`** because Boss's specific smart plug brand/model has not yet been specified, and per Section 16 & 35 no unapproved credentials or third-party cloud tokens are extracted.
- **Immediate Operational Workflow:** Once `Restore AC Power Loss = Power On` is set in BIOS, Boss can continue using the existing smart plug mobile app to turn AC power ON from the office, and `DAUVERSE REMOTE` Service will auto-start with Windows and send an **Online Notification** within seconds of boot!

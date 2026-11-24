# HEADLESS MODE & VIRTUAL DISPLAY GUIDE (WINDOWS 11 + RTX 3060)

## 1. Supported Headless Scenarios

`DAUVERSE REMOTE DESKTOP V1.0` supports full hardware-accelerated remote desktop when:
- Physical monitor at home is powered OFF.
- DisplayPort / HDMI cable is unplugged.
- Host PC operates completely headless without any physical monitor attached.
- Windows 11 Pro is at the Lock Screen or Pre-Login Winlogon Desktop (via Windows Service + Session Helper).

---

## 2. Virtual Display Driver Strategy

| Tier | Driver / Mechanism | Version & License | Role |
|---|---|---|---|
| **Primary (Software)** | `RustDeskIddDriver` (`usbmmidd_v2` / IDD) | `v0.4` (`MS-PL`) | Official signed UMDF Indirect Display Driver integrated with `src/virtual_display_manager.rs` & `libs/virtual_display`. Renders on NVIDIA RTX 3060 (`NVENC` preserved). |
| **Secondary Fallback (Software)** | `VirtualDrivers/Virtual-Display-Driver` (`MttVDD`) | `25.7.23` (`MIT`) | Optional fallback if custom 4K/120Hz/HDR EDID profiles are desired later (not installed concurrently). |
| **Hardware Fallback** | HDMI 2.0 / DP EDID Dummy Plug | Passive hardware | Zero-driver fallback only if Boss prefers zero virtual display drivers on host OS. |

---

## 3. Mandatory Driver & OS Security Guardrails (`src/dauverse/headless.rs`)

1. **Secure Boot & Driver Signature Enforcement Preserved:** Never disable UEFI Secure Boot, `bcdedit /set testsigning on`, or Windows Driver Signature Enforcement.
2. **Explicit Boss Approval Required:** Automated scripts and installers **never** silently install kernel or UMDF display drivers onto Boss's PC without explicit administrator confirmation.
3. **Automatic Topology Restoration:** When a headless virtual display is created for a session (`1920x1080@60`, `2560x1440@60`, or `3840x2160@60`), physical display configuration is restored cleanly when the session disconnects.

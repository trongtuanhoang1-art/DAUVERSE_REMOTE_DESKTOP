# HEADLESS MODE & VIRTUAL DISPLAY SECURITY GUIDE (WINDOWS 11 + RTX 3060)

> **Section 7 Authorization Status (`DREMOTE-V1-RC1-NEXT-002`):** Installation of any Windows Service, virtual display driver, unattended access, or host reboot on Boss's PC is **NOT YET APPROVED**. All driver controls remain strictly opt-in and unexecuted until Boss grants explicit approval.

---

## 1. Cryptographic Provenance & Signature Audit (`Section 7`)

Before recommending any virtual display driver for Windows 11 Pro, both candidate archives were downloaded and cryptographically inspected using `openssl x509` and `openssl pkcs7`:

### A. `RustDeskIddDriver v0.4` (`rustdesk-org/RustDeskIddDriver`) — **`BLOCKED_DO_NOT_INSTALL`**
- **Archive Audited:** `RustDeskIddDriver_x64.zip` (`SHA-256: e0f8875407feda12ba7d5df8dfe84ab9755a8b805b4b71d088720b3a8a6318de`)
- **X.509 Certificate Inspection (`RustDeskIddDriver.cer` / `RustDeskIddDriver.cat`):**
  - **Subject & Issuer:** `CN=WDKTestCert admin,133225435702113567` (**self-signed WDK test certificate**, NOT Microsoft WHQL or EV-signed)
  - **Signature Algorithm:** `sha1WithRSAEncryption` (deprecated SHA-1)
  - **SHA-1 Fingerprint:** `D1:DB:B6:72:D5:A5:00:B9:80:96:89:CA:EA:1C:E4:9E:79:97:67:F0`
  - **Install Script Behavior (`install_cert_runas_admin.bat`):** Executes `CertMgr.exe /add RustDeskIddDriver.cer /s /r localMachine root` to inject an untrusted self-signed test CA into Windows `LocalMachine\Root`!
- **Security Decision:** **HARD-BLOCKED** in `src/dauverse/headless.rs` and `scripts/windows/build_windows_release.ps1`. Never bundle or install `RustDeskIddDriver v0.4` or import `WDKTestCert` into `LocalMachine\Root`.

### B. `usbmmidd_v2` (Amyuni USB Mobile Monitor Virtual Display Driver) — **WHQL-Signed Software Option**
- **Upstream Alignment:** Upstream RustDesk `v1.5.3` (`src/virtual_display_manager.rs:9`) sets `IDD_IMPL_AMYUNI` (`usbmmidd_v2`) as its actual default driver.
- **Archive Audited:** `usbmmidd_v2.zip` (`SHA-256: 629b51e9944762bae73948171c65d09a79595cf4c771a82ebc003fbba5b24f51`)
- **PKCS#7 Catalog Signature (`usbmmidd.cat`):**
  - **Leaf Signer:** `CN=Microsoft Windows Hardware Compatibility Publisher, O=Microsoft Corporation, L=Redmond, S=Washington, C=US` (`sha256WithRSAEncryption`)
  - **Intermediate CA:** `CN=Microsoft Windows Third Party Component CA 2014`
  - **Root CA:** `CN=Microsoft Root Certificate Authority 2010`
- **Security Advantage:** Genuine **Microsoft WHQL signature** — works natively with **UEFI Secure Boot ON** and **Driver Signature Enforcement ON** with **zero certificate store modification**.
- **License Compliance:** Redistributed unmodified under `usbmmidd_v2/License.txt` freeware redistribution terms with mandatory Amyuni Technologies Inc. acknowledgment in `THIRD_PARTY_NOTICES` and About screen.

### C. Passive Hardware Option — **HDMI 2.0 / DisplayPort EDID Dummy Plug (Zero Driver)**
- If Boss prefers **zero third-party display drivers** on the home AI workstation, a passive HDMI 2.0 / DP EDID Dummy Plug inserted into the NVIDIA RTX 3060 provides native `1920x1080@60`, `2560x1440@60`, and `3840x2160@60` GPU desktop + full `NVENC` hardware encoding with monitor powered OFF or unplugged.

---

## 2. Mandatory Driver & OS Security Guardrails (`src/dauverse/headless.rs`)

1. **Secure Boot & Driver Signature Enforcement Preserved:** Never disable UEFI Secure Boot, `bcdedit /set testsigning on`, or Windows Driver Signature Enforcement.
2. **Hard-Block on `RustDeskIddDriver v0.4`:** `HeadlessManager::request_driver_install()` rejects any `rustdesk_idd` / `WDKTestCert` driver request even if `boss_admin_approved == true`.
3. **Explicit Boss Approval Gate:** Neither NSIS setup nor runtime code installs `usbmmidd_v2` unless Boss explicitly approves driver installation.
4. **Automatic Display Restoration:** Virtual displays added via `crate::virtual_display_manager` during a headless session are cleanly plugged out when the session ends.

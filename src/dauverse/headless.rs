use super::crypto_util::{check_no_symlink_or_reparse_component, sha256_file};
use serde::{Deserialize, Serialize};
use std::{path::Path, sync::Mutex};

pub const PINNED_USBMMIDD_CAT_SHA256: &str =
    "470149c4cf9970ba59070aa7c9409c9f63a15727de99bab53e7e51f55310779f";
pub const PINNED_USBMMIDD_INF_SHA256: &str =
    "a8750ca15a86742f3012886c9932bb974158cd2d9779cf891c730d976a47726a";
pub const PINNED_USBMMIDD_X64_DLL_SHA256: &str =
    "dc135d675127113915a7e5aa9fe57c84edad6be41d0890b265ef124ab26ea9e3";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DisplayEnvironmentState {
    PhysicalMonitorActive,
    PhysicalMonitorPoweredOff,
    MonitorCableDisconnected,
    HeadlessNoPhysicalMonitor,
    WindowsLockScreen,
    WindowsLoginScreen,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum HeadlessOperationalStatus {
    Configured,
    Available,
    Requested,
    BlockedApprovalRequired,
    BlockedDriverUnavailable,
    Active,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VirtualDisplayPreset {
    pub width: u32,
    pub height: u32,
    pub refresh_hz: u32,
    pub dpi_scale_pct: u32,
}

impl Default for VirtualDisplayPreset {
    fn default() -> Self {
        Self {
            width: 1920,
            height: 1080,
            refresh_hz: 60,
            dpi_scale_pct: 100,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeadlessPolicyState {
    pub display_state: DisplayEnvironmentState,
    pub operational_status: HeadlessOperationalStatus,
    pub status_detail: String,
    pub virtual_display_supported_by_os: bool,
    pub virtual_display_active: bool,
    pub active_preset: VirtualDisplayPreset,
    pub saved_physical_topology: Option<String>,
    pub verified_driver_catalog_sha256: Option<String>,
    pub auto_restore_on_disconnect: bool,
    pub primary_driver: String,
    pub rustdesk_idd_v04_audit: String,
    pub fallback_driver: String,
    pub hardware_fallback: String,
    pub rtx_3060_compatible: bool,
    pub require_signed_whql_driver: bool,
    pub secure_boot_preserved: bool,
    pub driver_signature_enforcement_preserved: bool,
    pub boss_driver_install_approved: bool,
}

fn query_physical_display_topology() -> Option<String> {
    #[cfg(target_os = "windows")]
    {
        use winapi::um::winuser::{GetSystemMetrics, SM_CMONITORS, SM_CXSCREEN, SM_CYSCREEN};
        let monitors = unsafe { GetSystemMetrics(SM_CMONITORS) };
        let w = unsafe { GetSystemMetrics(SM_CXSCREEN) };
        let h = unsafe { GetSystemMetrics(SM_CYSCREEN) };
        if monitors > 0 {
            return Some(format!("win32_monitors={monitors};primary={w}x{h}"));
        }
        None
    }
    #[cfg(not(target_os = "windows"))]
    {
        None
    }
}

pub fn verify_staged_whql_driver_package(driver_dir: &Path) -> Result<String, String> {
    check_no_symlink_or_reparse_component(driver_dir)?;
    let cat_path = driver_dir.join("usbmmidd.cat");
    let inf_path = driver_dir.join("usbmmIdd.inf");
    let dll_path = driver_dir.join("x64").join("usbmmIdd.dll");

    for p in [&cat_path, &inf_path, &dll_path] {
        check_no_symlink_or_reparse_component(p)?;
        if !p.is_file() {
            return Err(format!(
                "DRIVER_PACKAGE_INCOMPLETE: missing required WHQL file '{}'",
                p.display()
            ));
        }
    }

    let inf_text = std::fs::read_to_string(&inf_path)
        .map_err(|e| format!("failed reading usbmmIdd.inf: {e}"))?;
    if inf_text.contains("WDKTestCert") || inf_text.contains("RustDeskIdd") {
        return Err(
            "SECURITY_REJECT_TEST_ROOT_CA: Forbidden WDKTestCert / RustDeskIdd marker detected"
                .to_owned(),
        );
    }

    let cat_sha = sha256_file(&cat_path)?;
    if !cat_sha.eq_ignore_ascii_case(PINNED_USBMMIDD_CAT_SHA256) {
        return Err(format!(
            "SECURITY_REJECT_DRIVER_DIGEST_MISMATCH: usbmmidd.cat sha256 {} != pinned {}",
            cat_sha, PINNED_USBMMIDD_CAT_SHA256
        ));
    }
    let inf_sha = sha256_file(&inf_path)?;
    if !inf_sha.eq_ignore_ascii_case(PINNED_USBMMIDD_INF_SHA256) {
        return Err(format!(
            "SECURITY_REJECT_DRIVER_DIGEST_MISMATCH: usbmmIdd.inf sha256 {} != pinned {}",
            inf_sha, PINNED_USBMMIDD_INF_SHA256
        ));
    }
    let dll_sha = sha256_file(&dll_path)?;
    if !dll_sha.eq_ignore_ascii_case(PINNED_USBMMIDD_X64_DLL_SHA256) {
        return Err(format!(
            "SECURITY_REJECT_DRIVER_DIGEST_MISMATCH: usbmmIdd.dll sha256 {} != pinned {}",
            dll_sha, PINNED_USBMMIDD_X64_DLL_SHA256
        ));
    }

    Ok(cat_sha)
}

impl Default for HeadlessPolicyState {
    fn default() -> Self {
        #[cfg(target_os = "windows")]
        let supported = crate::virtual_display_manager::is_virtual_display_supported();
        #[cfg(not(target_os = "windows"))]
        let supported = false;

        Self {
            display_state: DisplayEnvironmentState::PhysicalMonitorActive,
            operational_status: HeadlessOperationalStatus::Configured,
            status_detail: "Configured idle (opt-in WHQL virtual display inactive; physical topology untouched).".to_owned(),
            virtual_display_supported_by_os: supported,
            virtual_display_active: false,
            active_preset: VirtualDisplayPreset::default(),
            saved_physical_topology: query_physical_display_topology(),
            verified_driver_catalog_sha256: None,
            auto_restore_on_disconnect: true,
            primary_driver: "Amyuni USB Mobile Monitor Virtual Display (usbmmidd_v2 — Microsoft WHQL Signed: CN=Microsoft Windows Hardware Compatibility Publisher, SHA-256 RSA)".to_owned(),
            rustdesk_idd_v04_audit: "BLOCKED_DO_NOT_INSTALL: RustDeskIddDriver v0.4 (SHA-256 e0f88754...) uses anonymous self-signed WDKTestCert (SHA-1 D1:DB:B6:72:D5:A5:00:B9:80:96:89:CA:EA:1C:E4:9E:79:97:67:F0) requiring LocalMachine\\Root import.".to_owned(),
            fallback_driver: "VirtualDrivers/Virtual-Display-Driver 25.7.23 (SignPath Authenticode x64; non-WHQL on Win11 ARM64)".to_owned(),
            hardware_fallback: "HDMI 2.0 / DP EDID Dummy Plug on NVIDIA RTX 3060 (Zero OS Driver Required)".to_owned(),
            rtx_3060_compatible: true,
            require_signed_whql_driver: true,
            secure_boot_preserved: true,
            driver_signature_enforcement_preserved: true,
            boss_driver_install_approved: false,
        }
    }
}

pub struct HeadlessManager {
    state: Mutex<HeadlessPolicyState>,
}

impl HeadlessManager {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(HeadlessPolicyState::default()),
        }
    }

    pub fn get_state(&self) -> HeadlessPolicyState {
        #[allow(unused_mut)]
        let mut g = self.state.lock().unwrap();
        #[cfg(target_os = "windows")]
        {
            g.virtual_display_supported_by_os =
                crate::virtual_display_manager::is_virtual_display_supported();
            if g.saved_physical_topology.is_none() {
                g.saved_physical_topology = query_physical_display_topology();
            }
        }
        g.clone()
    }

    pub fn request_driver_install_from_dir(
        &self,
        driver_dir: &Path,
        boss_approved: bool,
    ) -> Result<String, String> {
        if !boss_approved {
            return Err("APPROVAL_REQUIRED_DRIVER_INSTALL: Virtual display driver installation requires explicit Boss approval.".to_owned());
        }
        let cat_sha = verify_staged_whql_driver_package(driver_dir)?;
        let mut g = self.state.lock().unwrap();
        g.boss_driver_install_approved = true;
        g.verified_driver_catalog_sha256 = Some(cat_sha);
        g.operational_status = if g.virtual_display_supported_by_os {
            HeadlessOperationalStatus::Available
        } else {
            HeadlessOperationalStatus::BlockedDriverUnavailable
        };
        g.status_detail = "WHQL usbmmidd_v2 digests verified and Boss approval recorded (not yet active).".to_owned();
        Ok("WHQL_SIGNED_IDD_DRIVER_INSTALL_AUTHORIZED".to_owned())
    }

    pub fn request_driver_install(
        &self,
        whql_microsoft_signed: bool,
        uses_self_signed_root_cert: bool,
        boss_approved: bool,
    ) -> Result<String, String> {
        if uses_self_signed_root_cert {
            return Err("SECURITY_REJECT_TEST_ROOT_CA: Self-signed WDKTestCert / LocalMachine\\Root injection (e.g. RustDeskIddDriver v0.4) is strictly prohibited.".to_owned());
        }
        if !whql_microsoft_signed {
            return Err("SECURITY_REJECT_UNSIGNED_DRIVER: Non-WHQL/unsigned kernel or UMDF display drivers are prohibited; Secure Boot and DSE remain enforced.".to_owned());
        }
        if !boss_approved {
            return Err("APPROVAL_REQUIRED_DRIVER_INSTALL: Virtual display driver installation requires explicit Boss approval.".to_owned());
        }

        #[cfg(all(target_os = "windows", not(test)))]
        {
            let exe_dir = std::env::current_exe()
                .ok()
                .and_then(|p| p.parent().map(|d| d.to_path_buf()))
                .ok_or_else(|| "DRIVER_PACKAGE_PATH_UNRESOLVED".to_owned())?;
            let staged_dir = exe_dir.join("usbmmidd_v2");
            return self.request_driver_install_from_dir(&staged_dir, true);
        }

        #[cfg(not(all(target_os = "windows", not(test))))]
        {
            let mut g = self.state.lock().unwrap();
            g.boss_driver_install_approved = true;
            g.operational_status = if g.virtual_display_supported_by_os {
                HeadlessOperationalStatus::Available
            } else {
                HeadlessOperationalStatus::BlockedDriverUnavailable
            };
            g.status_detail =
                "Policy approval recorded; native Windows WHQL driver execution remains unavailable in non-Windows/test environment."
                    .to_owned();
            Ok("WHQL_SIGNED_IDD_DRIVER_POLICY_AUTHORIZED".to_owned())
        }
    }

    pub fn activate_headless_session(
        &self,
        env_state: DisplayEnvironmentState,
        preset: VirtualDisplayPreset,
    ) -> Result<HeadlessPolicyState, String> {
        if preset.width < 800
            || preset.height < 600
            || preset.refresh_hz == 0
            || preset.refresh_hz > 240
        {
            return Err("INVALID_VIRTUAL_DISPLAY_PRESET".to_owned());
        }
        let mut g = self.state.lock().unwrap();
        if g.saved_physical_topology.is_none() {
            g.saved_physical_topology = query_physical_display_topology();
        }
        g.display_state = env_state;
        g.active_preset = preset;
        let should_activate = matches!(
            env_state,
            DisplayEnvironmentState::PhysicalMonitorPoweredOff
                | DisplayEnvironmentState::MonitorCableDisconnected
                | DisplayEnvironmentState::HeadlessNoPhysicalMonitor
        );

        if !should_activate {
            g.virtual_display_active = false;
            g.operational_status = if g.boss_driver_install_approved && g.virtual_display_supported_by_os {
                HeadlessOperationalStatus::Available
            } else {
                HeadlessOperationalStatus::Configured
            };
            g.status_detail = "Physical display active; virtual display not required.".to_owned();
            return Ok(g.clone());
        }

        g.operational_status = HeadlessOperationalStatus::Requested;

        if !g.boss_driver_install_approved {
            g.virtual_display_active = false;
            g.operational_status = HeadlessOperationalStatus::BlockedApprovalRequired;
            g.status_detail =
                "BLOCKED: Boss approval required before virtual display activation; virtual display remains INACTIVE."
                    .to_owned();
            return Err("HEADLESS_BLOCKED_APPROVAL_REQUIRED".to_owned());
        }

        #[cfg(all(target_os = "windows", not(test)))]
        {
            if !crate::virtual_display_manager::is_virtual_display_supported() {
                g.virtual_display_active = false;
                g.operational_status = HeadlessOperationalStatus::BlockedDriverUnavailable;
                g.status_detail =
                    "BLOCKED: Windows virtual display driver is not installed or supported on this host."
                        .to_owned();
                return Err("HEADLESS_BLOCKED_DRIVER_UNAVAILABLE".to_owned());
            }
            match crate::virtual_display_manager::plug_in_headless() {
                Ok(_) => {
                    let post_topology = query_physical_display_topology();
                    if post_topology.is_none() {
                        g.virtual_display_active = false;
                        g.operational_status = HeadlessOperationalStatus::Failed;
                        g.status_detail =
                            "FAILED: plug_in_headless returned Ok, but Win32 reported 0 active monitors."
                                .to_owned();
                        return Err("WINDOWS_IDD_POSTCHECK_NO_MONITOR".to_owned());
                    }
                    g.virtual_display_active = true;
                    g.operational_status = HeadlessOperationalStatus::Active;
                    g.status_detail = "ACTIVE: Native Windows WHQL virtual display plugged in and verified.".to_owned();
                    return Ok(g.clone());
                }
                Err(e) => {
                    g.virtual_display_active = false;
                    g.operational_status = HeadlessOperationalStatus::Failed;
                    g.status_detail = format!("FAILED: {e}");
                    return Err(format!("WINDOWS_IDD_PLUGIN_FAILED: {e}"));
                }
            }
        }

        #[cfg(not(all(target_os = "windows", not(test))))]
        {
            g.virtual_display_active = false;
            g.operational_status = HeadlessOperationalStatus::BlockedDriverUnavailable;
            g.status_detail =
                "BLOCKED: Native Windows IDD driver execution is unavailable in non-Windows or unit-test isolation; virtual display is NOT active."
                    .to_owned();
            Err("HEADLESS_BLOCKED_NATIVE_DRIVER_UNAVAILABLE".to_owned())
        }
    }

    pub fn on_session_disconnected(&self) -> HeadlessPolicyState {
        let mut g = self.state.lock().unwrap();
        if g.auto_restore_on_disconnect && g.virtual_display_active {
            #[cfg(all(target_os = "windows", not(test)))]
            if g.boss_driver_install_approved {
                let _ = crate::virtual_display_manager::reset_all();
            }
            g.virtual_display_active = false;
            g.display_state = DisplayEnvironmentState::PhysicalMonitorActive;
            g.operational_status = if g.boss_driver_install_approved && g.virtual_display_supported_by_os {
                HeadlessOperationalStatus::Available
            } else {
                HeadlessOperationalStatus::Configured
            };
            g.status_detail = "Disconnected; restored physical display state.".to_owned();
        }
        g.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f04_headless_never_reports_active_without_approval_or_native_execution_and_rejects_wdk_test_cert() {
        let mgr = HeadlessManager::new();
        assert_eq!(
            mgr.get_state().operational_status,
            HeadlessOperationalStatus::Configured
        );
        assert!(!mgr.get_state().virtual_display_active);

        // 1. Unapproved activation MUST fail and keep virtual_display_active == false (F04 counterexample)
        let unapproved_err = mgr
            .activate_headless_session(
                DisplayEnvironmentState::HeadlessNoPhysicalMonitor,
                VirtualDisplayPreset::default(),
            )
            .unwrap_err();
        assert_eq!(unapproved_err, "HEADLESS_BLOCKED_APPROVAL_REQUIRED");
        let st_unapproved = mgr.get_state();
        assert!(!st_unapproved.virtual_display_active);
        assert_eq!(
            st_unapproved.operational_status,
            HeadlessOperationalStatus::BlockedApprovalRequired
        );

        // 2. Rejects unsigned driver and WDKTestCert self-signed root cert
        assert!(mgr.request_driver_install(false, false, true).is_err());
        assert!(mgr.request_driver_install(true, true, true).is_err());
        assert!(mgr.request_driver_install(true, false, false).is_err());

        // 3. Even after policy approval, in test/non-Windows isolation where plug_in_headless()
        //    is not executed, activate_headless_session MUST NOT claim virtual_display_active == true!
        assert!(mgr.request_driver_install(true, false, true).is_ok());
        let non_native_err = mgr
            .activate_headless_session(
                DisplayEnvironmentState::PhysicalMonitorPoweredOff,
                VirtualDisplayPreset {
                    width: 2560,
                    height: 1440,
                    refresh_hz: 60,
                    dpi_scale_pct: 125,
                },
            )
            .unwrap_err();
        assert_eq!(non_native_err, "HEADLESS_BLOCKED_NATIVE_DRIVER_UNAVAILABLE");
        let st_blocked = mgr.get_state();
        assert!(!st_blocked.virtual_display_active);
        assert_eq!(
            st_blocked.operational_status,
            HeadlessOperationalStatus::BlockedDriverUnavailable
        );
        assert!(st_blocked.secure_boot_preserved);
        assert!(st_blocked.driver_signature_enforcement_preserved);

        // 4. PhysicalMonitorActive remains Configured/Available with virtual_display_active == false
        let phys = mgr
            .activate_headless_session(
                DisplayEnvironmentState::PhysicalMonitorActive,
                VirtualDisplayPreset::default(),
            )
            .unwrap();
        assert!(!phys.virtual_display_active);

        // 5. Tampered staged driver directory is rejected by pinned SHA-256 verifier
        let fake_dir = std::env::temp_dir().join(format!("dv_bad_drv_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(fake_dir.join("x64")).unwrap();
        std::fs::write(fake_dir.join("usbmmidd.cat"), b"fake").unwrap();
        std::fs::write(fake_dir.join("usbmmIdd.inf"), b"WDKTestCert").unwrap();
        std::fs::write(fake_dir.join("x64").join("usbmmIdd.dll"), b"fake").unwrap();
        assert!(verify_staged_whql_driver_package(&fake_dir)
            .unwrap_err()
            .contains("SECURITY_REJECT_TEST_ROOT_CA"));
        std::fs::remove_dir_all(&fake_dir).ok();
    }
}

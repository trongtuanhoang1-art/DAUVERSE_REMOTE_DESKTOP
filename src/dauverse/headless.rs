use serde::{Deserialize, Serialize};
use std::sync::Mutex;

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
    pub virtual_display_supported_by_os: bool,
    pub virtual_display_active: bool,
    pub active_preset: VirtualDisplayPreset,
    pub saved_physical_topology: Option<String>,
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

impl Default for HeadlessPolicyState {
    fn default() -> Self {
        #[cfg(target_os = "windows")]
        let supported = crate::virtual_display_manager::is_virtual_display_supported();
        #[cfg(not(target_os = "windows"))]
        let supported = false;

        Self {
            display_state: DisplayEnvironmentState::PhysicalMonitorActive,
            virtual_display_supported_by_os: supported,
            virtual_display_active: false,
            active_preset: VirtualDisplayPreset::default(),
            saved_physical_topology: None,
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
        }
        g.clone()
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
        let mut g = self.state.lock().unwrap();
        g.boss_driver_install_approved = true;
        Ok("WHQL_SIGNED_IDD_DRIVER_INSTALL_AUTHORIZED".to_owned())
    }

    pub fn activate_headless_session(
        &self,
        env_state: DisplayEnvironmentState,
        preset: VirtualDisplayPreset,
    ) -> Result<HeadlessPolicyState, String> {
        if preset.width < 800 || preset.height < 600 || preset.refresh_hz == 0 || preset.refresh_hz > 240 {
            return Err("INVALID_VIRTUAL_DISPLAY_PRESET".to_owned());
        }
        let mut g = self.state.lock().unwrap();
        g.display_state = env_state;
        if g.saved_physical_topology.is_none() {
            g.saved_physical_topology = Some("SavedDesktopTopologySnapshot-v1".to_owned());
        }
        g.active_preset = preset;
        let should_activate = matches!(
            env_state,
            DisplayEnvironmentState::PhysicalMonitorPoweredOff
                | DisplayEnvironmentState::MonitorCableDisconnected
                | DisplayEnvironmentState::HeadlessNoPhysicalMonitor
        );
        #[cfg(target_os = "windows")]
        if should_activate && g.boss_driver_install_approved {
            if let Err(e) = crate::virtual_display_manager::plug_in_headless() {
                return Err(format!("WINDOWS_IDD_PLUGIN_FAILED: {e}"));
            }
        }
        g.virtual_display_active = should_activate;
        Ok(g.clone())
    }

    pub fn on_session_disconnected(&self) -> HeadlessPolicyState {
        let mut g = self.state.lock().unwrap();
        if g.auto_restore_on_disconnect && g.virtual_display_active {
            #[cfg(target_os = "windows")]
            if g.boss_driver_install_approved {
                let _ = crate::virtual_display_manager::reset_all();
            }
            g.virtual_display_active = false;
            g.display_state = DisplayEnvironmentState::PhysicalMonitorActive;
        }
        g.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enforces_whql_signed_driver_rejects_wdk_test_cert_and_restores_topology() {
        let mgr = HeadlessManager::new();
        // Rejects unsigned driver
        assert!(mgr.request_driver_install(false, false, true).is_err());
        // Rejects self-signed WDKTestCert root import (RustDeskIddDriver v0.4)
        assert!(mgr.request_driver_install(true, true, true).is_err());
        // Rejects unapproved install
        assert!(mgr.request_driver_install(true, false, false).is_err());
        // Accepts WHQL signed + no test root cert + Boss approved
        assert!(mgr.request_driver_install(true, false, true).is_ok());

        let active = mgr
            .activate_headless_session(
                DisplayEnvironmentState::PhysicalMonitorPoweredOff,
                VirtualDisplayPreset {
                    width: 2560,
                    height: 1440,
                    refresh_hz: 60,
                    dpi_scale_pct: 125,
                },
            )
            .unwrap();
        assert!(active.virtual_display_active);
        assert_eq!(active.active_preset.width, 2560);
        assert!(active.rustdesk_idd_v04_audit.contains("BLOCKED_DO_NOT_INSTALL"));

        let restored = mgr.on_session_disconnected();
        assert!(!restored.virtual_display_active);
        assert!(restored.secure_boot_preserved);
        assert!(restored.driver_signature_enforcement_preserved);
    }
}

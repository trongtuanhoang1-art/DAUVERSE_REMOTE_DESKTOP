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
    pub virtual_display_active: bool,
    pub active_preset: VirtualDisplayPreset,
    pub saved_physical_topology: Option<String>,
    pub auto_restore_on_disconnect: bool,
    pub primary_driver: String,
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
        Self {
            display_state: DisplayEnvironmentState::PhysicalMonitorActive,
            virtual_display_active: false,
            active_preset: VirtualDisplayPreset::default(),
            saved_physical_topology: Some("Primary-DP1-1920x1080@60Hz".to_owned()),
            auto_restore_on_disconnect: true,
            primary_driver: "RustDeskIddDriver v0.4 (Signed UMDF Indirect Display Driver)".to_owned(),
            fallback_driver: "VirtualDrivers/Virtual-Display-Driver 25.7.23 (MttVDD)".to_owned(),
            hardware_fallback: "HDMI 2.0 EDID Dummy Plug (Hardware Fallback Only)".to_owned(),
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
        self.state.lock().unwrap().clone()
    }

    pub fn request_driver_install(
        &self,
        driver_signed: bool,
        boss_approved: bool,
    ) -> Result<String, String> {
        if !driver_signed {
            return Err("SECURITY_REJECT_UNSIGNED_DRIVER: Unsigned kernel/UMDF display drivers are strictly prohibited; Secure Boot and DSE remain enforced.".to_owned());
        }
        if !boss_approved {
            return Err("APPROVAL_REQUIRED_DRIVER_INSTALL: Virtual display driver installation requires explicit Boss approval.".to_owned());
        }
        let mut g = self.state.lock().unwrap();
        g.boss_driver_install_approved = true;
        Ok("SIGNED_IDD_DRIVER_INSTALL_AUTHORIZED".to_owned())
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
        g.virtual_display_active = matches!(
            env_state,
            DisplayEnvironmentState::PhysicalMonitorPoweredOff
                | DisplayEnvironmentState::MonitorCableDisconnected
                | DisplayEnvironmentState::HeadlessNoPhysicalMonitor
        );
        Ok(g.clone())
    }

    pub fn on_session_disconnected(&self) -> HeadlessPolicyState {
        let mut g = self.state.lock().unwrap();
        if g.auto_restore_on_disconnect && g.virtual_display_active {
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
    fn enforces_signed_driver_and_restores_topology_on_disconnect() {
        let mgr = HeadlessManager::new();
        assert!(mgr.request_driver_install(false, true).is_err());
        assert!(mgr.request_driver_install(true, false).is_err());
        assert!(mgr.request_driver_install(true, true).is_ok());

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

        let restored = mgr.on_session_disconnected();
        assert!(!restored.virtual_display_active);
        assert!(restored.secure_boot_preserved);
        assert!(restored.driver_signature_enforcement_preserved);
    }
}

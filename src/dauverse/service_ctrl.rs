use serde::{Deserialize, Serialize};
use std::sync::Mutex;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ServiceRunState {
    Running,
    Stopped,
    DegradedRecovering,
    NotInstalledPortableMode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceStartupState {
    pub service_state: ServiceRunState,
    pub auto_start_with_windows: bool,
    pub unattended_access_enabled: bool,
    pub pre_login_session_helper_enabled: bool,
    pub privilege_separation_enforced: bool,
    pub system_tray_indicator_visible: bool,
    pub active_remote_banner_visible: bool,
    pub defender_av_untouched: bool,
    pub no_hidden_persistence: bool,
    pub last_health_check_utc: String,
    pub recovery_restart_count: u32,
}

impl Default for ServiceStartupState {
    fn default() -> Self {
        Self {
            service_state: ServiceRunState::NotInstalledPortableMode,
            auto_start_with_windows: false,
            unattended_access_enabled: false,
            pre_login_session_helper_enabled: false,
            privilege_separation_enforced: true,
            system_tray_indicator_visible: true,
            active_remote_banner_visible: true,
            defender_av_untouched: true,
            no_hidden_persistence: true,
            last_health_check_utc: chrono::Utc::now().to_rfc3339(),
            recovery_restart_count: 0,
        }
    }
}

pub struct ServiceController {
    state: Mutex<ServiceStartupState>,
}

impl ServiceController {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(ServiceStartupState::default()),
        }
    }

    pub fn status(&self) -> ServiceStartupState {
        let mut g = self.state.lock().unwrap();
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        g.clone()
    }

    pub fn configure_unattended(&self, enable: bool, owner_authenticated: bool) -> Result<ServiceStartupState, String> {
        if !owner_authenticated {
            return Err("AUTH_REQUIRED_FOR_UNATTENDED_CONFIG".to_owned());
        }
        let mut g = self.state.lock().unwrap();
        g.unattended_access_enabled = enable;
        g.system_tray_indicator_visible = true;
        g.active_remote_banner_visible = true;
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        Ok(g.clone())
    }

    pub fn set_auto_start(&self, enable: bool, owner_authenticated: bool) -> Result<ServiceStartupState, String> {
        if !owner_authenticated {
            return Err("AUTH_REQUIRED_FOR_STARTUP_CONFIG".to_owned());
        }
        let mut g = self.state.lock().unwrap();
        g.auto_start_with_windows = enable;
        g.no_hidden_persistence = true;
        Ok(g.clone())
    }

    pub fn revoke_all_access_immediately(&self) -> ServiceStartupState {
        let mut g = self.state.lock().unwrap();
        g.unattended_access_enabled = false;
        g.pre_login_session_helper_enabled = false;
        if g.service_state == ServiceRunState::Running {
            g.service_state = ServiceRunState::Stopped;
        }
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        g.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requires_auth_for_unattended_and_supports_instant_revocation() {
        let ctrl = ServiceController::new();
        assert!(ctrl.configure_unattended(true, false).is_err());
        let st = ctrl.configure_unattended(true, true).unwrap();
        assert!(st.unattended_access_enabled);
        assert!(st.system_tray_indicator_visible);
        assert!(st.defender_av_untouched);
        assert!(st.no_hidden_persistence);

        let revoked = ctrl.revoke_all_access_immediately();
        assert!(!revoked.unattended_access_enabled);
    }
}

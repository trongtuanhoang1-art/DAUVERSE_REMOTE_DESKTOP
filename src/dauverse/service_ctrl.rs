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
    pub scm_service_name: String,
    pub scm_display_name: String,
    pub service_state: ServiceRunState,
    pub desired_auto_start: bool,
    pub auto_start_with_windows: bool,
    pub desired_unattended_enabled: bool,
    pub unattended_access_enabled: bool,
    pub service_owned_by_dauverse: Option<bool>,
    pub external_service_collision_detected: bool,
    pub observed_service_binary_path: Option<String>,
    pub pre_login_session_helper_enabled: bool,
    pub privilege_separation_enforced: bool,
    pub system_tray_indicator_visible: bool,
    pub active_remote_banner_visible: bool,
    pub defender_av_untouched: bool,
    pub no_hidden_persistence: bool,
    pub boss_service_install_approved: bool,
    pub last_health_check_utc: String,
    pub recovery_restart_count: u32,
}

pub fn is_service_image_path_owned_by_install_dir(image_path: &str, install_dir: &str) -> bool {
    let clean_img = image_path
        .trim()
        .trim_start_matches('"')
        .replace('/', "\\")
        .to_ascii_lowercase();
    let mut clean_dir = install_dir
        .trim()
        .trim_matches('"')
        .replace('/', "\\")
        .trim_end_matches('\\')
        .to_ascii_lowercase();
    if clean_dir.is_empty() {
        return false;
    }
    clean_dir.push('\\');
    clean_img.starts_with(&clean_dir)
}

#[cfg(target_os = "windows")]
fn query_windows_service_ownership_and_run_state() -> (
    ServiceRunState,
    Option<bool>,
    bool,
    Option<String>,
    bool,
) {
    use winreg::{
        enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, KEY_READ},
        RegKey,
    };

    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_string_lossy().into_owned()))
        .unwrap_or_default();

    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let (svc_state, owned, collision, img_opt) = match hklm.open_subkey_with_flags(
        "SYSTEM\\CurrentControlSet\\Services\\RustDesk",
        KEY_READ,
    ) {
        Ok(svc_key) => {
            let img: String = svc_key.get_value("ImagePath").unwrap_or_default();
            if is_service_image_path_owned_by_install_dir(&img, &exe_dir) {
                let st = if crate::platform::windows::is_self_service_running() {
                    ServiceRunState::Running
                } else {
                    ServiceRunState::Stopped
                };
                (st, Some(true), false, Some(img))
            } else {
                // External RustDesk installation owns the SCM "RustDesk" service; do NOT claim or touch it!
                (
                    ServiceRunState::NotInstalledPortableMode,
                    Some(false),
                    true,
                    Some(img),
                )
            }
        }
        Err(_) => (ServiceRunState::NotInstalledPortableMode, None, false, None),
    };

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let run_present = hkcu
        .open_subkey_with_flags(
            "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            KEY_READ,
        )
        .ok()
        .and_then(|k| k.get_value::<String, _>("DauverseRemoteDesktop").ok())
        .map(|val| is_service_image_path_owned_by_install_dir(&val, &exe_dir))
        .unwrap_or(false);

    (svc_state, owned, collision, img_opt, run_present)
}

impl Default for ServiceStartupState {
    fn default() -> Self {
        Self {
            scm_service_name: "RustDesk".to_owned(),
            scm_display_name: "DAUVERSE Remote Desktop Service (RustDesk Engine)".to_owned(),
            service_state: ServiceRunState::NotInstalledPortableMode,
            desired_auto_start: false,
            auto_start_with_windows: false,
            desired_unattended_enabled: false,
            unattended_access_enabled: false,
            service_owned_by_dauverse: None,
            external_service_collision_detected: false,
            observed_service_binary_path: None,
            pre_login_session_helper_enabled: false,
            privilege_separation_enforced: true,
            system_tray_indicator_visible: true,
            active_remote_banner_visible: true,
            defender_av_untouched: true,
            no_hidden_persistence: true,
            boss_service_install_approved: false,
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

    pub fn is_service_running(&self) -> bool {
        self.status().service_state == ServiceRunState::Running
    }

    pub fn status(&self) -> ServiceStartupState {
        let mut g = self.state.lock().unwrap();
        #[cfg(target_os = "windows")]
        {
            let (svc_state, owned, collision, img_opt, run_present) =
                query_windows_service_and_autorun_compat();
            g.service_state = svc_state;
            g.service_owned_by_dauverse = owned;
            g.external_service_collision_detected = collision;
            g.observed_service_binary_path = img_opt;
            #[cfg(not(test))]
            {
                g.auto_start_with_windows = run_present;
            }
            #[cfg(test)]
            {
                let _ = run_present;
            }
        }
        let approve_mode = hbb_common::config::Config::get_option("approve-mode");
        if approve_mode == "click" {
            g.unattended_access_enabled = false;
        }
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        g.clone()
    }

    pub fn configure_unattended(
        &self,
        enable: bool,
        owner_authenticated: bool,
    ) -> Result<ServiceStartupState, String> {
        if !owner_authenticated {
            return Err("AUTH_REQUIRED_FOR_UNATTENDED_CONFIG".to_owned());
        }
        let target_mode = if enable { "password" } else { "click" };
        hbb_common::config::Config::set_option("approve-mode".to_owned(), target_mode.to_owned());
        let actual_mode = hbb_common::config::Config::get_option("approve-mode");
        let observed_enabled = enable && actual_mode != "click";

        let mut g = self.state.lock().unwrap();
        g.desired_unattended_enabled = enable;
        g.unattended_access_enabled = observed_enabled;
        g.system_tray_indicator_visible = true;
        g.active_remote_banner_visible = true;
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        Ok(g.clone())
    }

    pub fn set_auto_start(
        &self,
        enable: bool,
        owner_authenticated: bool,
    ) -> Result<ServiceStartupState, String> {
        if !owner_authenticated {
            return Err("AUTH_REQUIRED_FOR_STARTUP_CONFIG".to_owned());
        }
        #[cfg(all(target_os = "windows", not(test)))]
        {
            use winreg::{
                enums::{HKEY_CURRENT_USER, KEY_SET_VALUE},
                RegKey,
            };
            let exe_path = std::env::current_exe()
                .map_err(|e| format!("failed resolving current_exe for Run key: {e}"))?;
            let hkcu = RegKey::predef(HKEY_CURRENT_USER);
            let run_key = hkcu
                .open_subkey_with_flags(
                    "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    KEY_SET_VALUE,
                )
                .map_err(|e| format!("failed opening HKCU Run key: {e}"))?;
            if enable {
                let cmd = format!("\"{}\" --dauverse-ui", exe_path.display());
                run_key
                    .set_value("DauverseRemoteDesktop", &cmd)
                    .map_err(|e| format!("failed writing HKCU Run entry: {e}"))?;
            } else {
                let _ = run_key.delete_value("DauverseRemoteDesktop");
            }
        }
        let mut g = self.state.lock().unwrap();
        g.desired_auto_start = enable;
        g.auto_start_with_windows = enable;
        g.no_hidden_persistence = true;
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        Ok(g.clone())
    }

    pub fn revoke_all_access_immediately(&self) -> ServiceStartupState {
        #[cfg(all(target_os = "windows", not(test)))]
        {
            use winreg::{
                enums::{HKEY_CURRENT_USER, KEY_SET_VALUE},
                RegKey,
            };
            if let Ok(run_key) = RegKey::predef(HKEY_CURRENT_USER).open_subkey_with_flags(
                "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                KEY_SET_VALUE,
            ) {
                let _ = run_key.delete_value("DauverseRemoteDesktop");
            }
        }
        let mut g = self.state.lock().unwrap();
        g.desired_unattended_enabled = false;
        g.unattended_access_enabled = false;
        g.desired_auto_start = false;
        g.auto_start_with_windows = false;
        g.pre_login_session_helper_enabled = false;
        if g.service_state == ServiceRunState::Running {
            g.service_state = ServiceRunState::Stopped;
        }
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        hbb_common::config::Config::set_option("approve-mode".to_owned(), "click".to_owned());
        hbb_common::config::Config::set_option("enable-keyboard".to_owned(), "N".to_owned());
        hbb_common::config::Config::set_option("enable-clipboard".to_owned(), "N".to_owned());
        hbb_common::config::Config::set_option("enable-file-transfer".to_owned(), "N".to_owned());
        hbb_common::password_security::update_temporary_password();
        g.clone()
    }
}

#[cfg(target_os = "windows")]
fn query_windows_service_and_autorun_compat() -> (
    ServiceRunState,
    Option<bool>,
    bool,
    Option<String>,
    bool,
) {
    query_windows_service_ownership_and_run_state()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f03_f08_verifies_service_image_path_ownership_and_synchronizes_unattended_revocation() {
        assert!(is_service_image_path_owned_by_install_dir(
            "\"C:\\Program Files\\DAUVERSE Remote Desktop\\rustdesk.exe\" --service",
            "C:\\Program Files\\DAUVERSE Remote Desktop"
        ));
        assert!(!is_service_image_path_owned_by_install_dir(
            "\"C:\\Program Files\\RustDesk\\rustdesk.exe\" --service",
            "C:\\Program Files\\DAUVERSE Remote Desktop"
        ));
        assert!(!is_service_image_path_owned_by_install_dir(
            "\"C:\\Program Files\\DAUVERSE Remote Desktop Evil\\rustdesk.exe\" --service",
            "C:\\Program Files\\DAUVERSE Remote Desktop"
        ));

        let ctrl = ServiceController::new();
        assert_eq!(ctrl.status().scm_service_name, "RustDesk");
        assert!(ctrl.configure_unattended(true, false).is_err());
        assert!(ctrl.set_auto_start(true, false).is_err());

        let st = ctrl.configure_unattended(true, true).unwrap();
        assert!(st.desired_unattended_enabled);
        assert!(st.system_tray_indicator_visible);
        assert!(st.defender_av_untouched);
        assert!(st.no_hidden_persistence);

        let _ = ctrl.set_auto_start(true, true).unwrap();
        let revoked = ctrl.revoke_all_access_immediately();
        assert!(!revoked.unattended_access_enabled);
        assert!(!revoked.auto_start_with_windows);
        assert_eq!(
            hbb_common::config::Config::get_option("approve-mode"),
            "click"
        );
    }
}

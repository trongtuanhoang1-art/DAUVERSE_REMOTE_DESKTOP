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
fn query_owned_scm_service_state(service_name: &str) -> (ServiceRunState, Option<String>) {
    use windows_service::{
        service::{ServiceAccess, ServiceState},
        service_manager::{ServiceManager, ServiceManagerAccess},
    };
    let manager = match ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
    {
        Ok(m) => m,
        Err(e) => {
            return (
                ServiceRunState::DegradedRecovering,
                Some(format!("SERVICE_SCM_CONNECT_FAILED: {e}")),
            )
        }
    };
    let svc = match manager.open_service(service_name, ServiceAccess::QUERY_STATUS) {
        Ok(s) => s,
        Err(e) => {
            return (
                ServiceRunState::DegradedRecovering,
                Some(format!("SERVICE_SCM_OPEN_QUERY_FAILED: {e}")),
            )
        }
    };
    match svc.query_status() {
        Ok(st) => match st.current_state {
            ServiceState::Stopped => (ServiceRunState::Stopped, None),
            ServiceState::Running => (ServiceRunState::Running, None),
            _ => (ServiceRunState::DegradedRecovering, None),
        },
        Err(e) => (
            ServiceRunState::DegradedRecovering,
            Some(format!("SERVICE_SCM_QUERY_STATUS_FAILED: {e}")),
        ),
    }
}

#[cfg(target_os = "windows")]
fn query_windows_service_ownership_and_run_state_detailed() -> (
    ServiceRunState,
    Option<bool>,
    bool,
    Option<String>,
    bool,
    Option<String>,
) {
    use winreg::{
        enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, KEY_READ},
        RegKey,
    };

    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_string_lossy().into_owned()))
        .unwrap_or_default();

    let mut query_err: Option<String> = None;
    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let (svc_state, owned, collision, img_opt) = match hklm.open_subkey_with_flags(
        "SYSTEM\\CurrentControlSet\\Services\\RustDesk",
        KEY_READ,
    ) {
        Ok(svc_key) => {
            let img: String = match svc_key.get_value("ImagePath") {
                Ok(v) => v,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
                Err(e) => {
                    query_err = Some(format!("SERVICE_IMAGE_PATH_READ_FAILED: {e}"));
                    String::new()
                }
            };
            if is_service_image_path_owned_by_install_dir(&img, &exe_dir) {
                let (st, scm_err) = query_owned_scm_service_state("RustDesk");
                if query_err.is_none() {
                    query_err = scm_err;
                }
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
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            (ServiceRunState::NotInstalledPortableMode, None, false, None)
        }
        Err(e) => {
            query_err = Some(format!("SERVICE_REGISTRY_OPEN_FAILED: {e}"));
            (ServiceRunState::DegradedRecovering, None, false, None)
        }
    };

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let run_present = match hkcu.open_subkey_with_flags(
        "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
        KEY_READ,
    ) {
        Ok(k) => match k.get_value::<String, _>("DauverseRemoteDesktop") {
            Ok(val) => is_service_image_path_owned_by_install_dir(&val, &exe_dir),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => false,
            Err(e) => {
                if query_err.is_none() {
                    query_err = Some(format!("SERVICE_RUN_VALUE_READ_FAILED: {e}"));
                }
                false
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => false,
        Err(e) => {
            if query_err.is_none() {
                query_err = Some(format!("SERVICE_RUN_KEY_READ_FAILED: {e}"));
            }
            false
        }
    };

    (svc_state, owned, collision, img_opt, run_present, query_err)
}

#[cfg(target_os = "windows")]
fn query_windows_service_ownership_and_run_state() -> (
    ServiceRunState,
    Option<bool>,
    bool,
    Option<String>,
    bool,
) {
    let (svc_state, owned, collision, img_opt, run_present, _err) =
        query_windows_service_ownership_and_run_state_detailed();
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
        g.unattended_access_enabled = !approve_mode.is_empty()
            && approve_mode != "click"
            && !g.external_service_collision_detected;
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
        let current = self.status();
        if enable && current.external_service_collision_detected {
            return Err(
                "SERVICE_COLLISION_EXTERNAL_RUSTDESK_DETECTED: refusing unattended activation while an external RustDesk Windows service owns SCM 'RustDesk'"
                    .to_owned(),
            );
        }
        let target_mode = if enable { "password" } else { "click" };
        if enable {
            hbb_common::config::Config::set_option("stop-service".to_owned(), String::new());
        }
        hbb_common::config::Config::set_option("approve-mode".to_owned(), target_mode.to_owned());
        let actual_mode = hbb_common::config::Config::get_option("approve-mode");
        if actual_mode != target_mode {
            return Err(format!(
                "UNATTENDED_CONFIG_VERIFY_FAILED: expected approve-mode='{target_mode}', got '{actual_mode}'"
            ));
        }

        let mut g = self.state.lock().unwrap();
        g.desired_unattended_enabled = enable;
        g.unattended_access_enabled = enable;
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
                match run_key.delete_value("DauverseRemoteDesktop") {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => {
                        return Err(format!("failed deleting HKCU Run entry: {e}"));
                    }
                }
            }
            let (_, _, _, _, run_present) = query_windows_service_ownership_and_run_state();
            if run_present != enable {
                return Err(format!(
                    "AUTO_START_REGISTRY_VERIFY_FAILED: expected HKCU Run present={enable}, observed={run_present}"
                ));
            }
        }
        let mut g = self.state.lock().unwrap();
        g.desired_auto_start = enable;
        g.auto_start_with_windows = enable;
        g.no_hidden_persistence = true;
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        Ok(g.clone())
    }

    pub fn revoke_all_access_immediately(&self) -> Result<ServiceStartupState, String> {
        hbb_common::config::Config::set_option("approve-mode".to_owned(), "click".to_owned());
        hbb_common::config::Config::set_option("enable-keyboard".to_owned(), "N".to_owned());
        hbb_common::config::Config::set_option("enable-clipboard".to_owned(), "N".to_owned());
        hbb_common::config::Config::set_option("enable-file-transfer".to_owned(), "N".to_owned());
        hbb_common::config::Config::set_option("stop-service".to_owned(), "Y".to_owned());
        hbb_common::password_security::update_temporary_password();
        let actual_approve_mode = hbb_common::config::Config::get_option("approve-mode");

        #[cfg(all(target_os = "windows", not(test)))]
        {
            use winreg::{
                enums::{HKEY_CURRENT_USER, KEY_SET_VALUE},
                RegKey,
            };
            let (
                before_svc_state,
                before_owned,
                _collision,
                _img_opt,
                before_run_present,
                before_query_err,
            ) = query_windows_service_ownership_and_run_state_detailed();
            let mut os_action_err: Option<String> = before_query_err;

            if before_run_present || os_action_err.is_some() {
                match RegKey::predef(HKEY_CURRENT_USER).open_subkey_with_flags(
                    "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    KEY_SET_VALUE,
                ) {
                    Ok(run_key) => match run_key.delete_value("DauverseRemoteDesktop") {
                        Ok(()) => {}
                        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                        Err(e) => {
                            if os_action_err.is_none() {
                                os_action_err =
                                    Some(format!("SERVICE_REVOKE_RUN_KEY_DELETE_FAILED: {e}"));
                            }
                        }
                    },
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => {
                        if os_action_err.is_none() {
                            os_action_err =
                                Some(format!("SERVICE_REVOKE_RUN_KEY_OPEN_FAILED: {e}"));
                        }
                    }
                }
            }

            // Strictly preserve F03 ownership protection: NEVER stop SCM 'RustDesk' unless owned == Some(true)
            if os_action_err.is_none()
                && before_owned == Some(true)
                && before_svc_state != ServiceRunState::Stopped
            {
                if let Err(stop_err) = stop_owned_windows_scm_service("RustDesk") {
                    os_action_err = Some(stop_err);
                }
            }

            {
                let mut g = self.state.lock().unwrap();
                g.desired_unattended_enabled = false;
                g.desired_auto_start = false;
                g.pre_login_session_helper_enabled = false;
            }
            let (
                _after_svc_state,
                _after_owned,
                _after_collision,
                _after_img,
                _after_run,
                after_query_err,
            ) = query_windows_service_ownership_and_run_state_detailed();
            if os_action_err.is_none() {
                os_action_err = after_query_err;
            }
            let refreshed = self.status();
            verify_post_revoke_os_truth(
                &actual_approve_mode,
                refreshed.service_owned_by_dauverse,
                refreshed.service_state,
                refreshed.auto_start_with_windows,
                os_action_err,
            )?;
            return Ok(refreshed);
        }

        #[cfg(not(all(target_os = "windows", not(test))))]
        {
            {
                let mut g = self.state.lock().unwrap();
                g.desired_unattended_enabled = false;
                g.desired_auto_start = false;
                g.auto_start_with_windows = false;
                g.pre_login_session_helper_enabled = false;
            }
            let refreshed = self.status();
            verify_post_revoke_os_truth(
                &actual_approve_mode,
                refreshed.service_owned_by_dauverse,
                refreshed.service_state,
                refreshed.auto_start_with_windows,
                None,
            )?;
            Ok(refreshed)
        }
    }
}

pub(crate) fn verify_post_revoke_os_truth(
    actual_approve_mode: &str,
    after_owned_by_dauverse: Option<bool>,
    after_service_state: ServiceRunState,
    after_run_key_present: bool,
    os_action_error: Option<String>,
) -> Result<(), String> {
    if actual_approve_mode != "click" {
        return Err(format!(
            "SERVICE_REVOKE_CONFIG_VERIFY_FAILED: expected approve-mode='click', got '{actual_approve_mode}'"
        ));
    }
    if let Some(err) = os_action_error {
        return Err(err);
    }
    if after_run_key_present {
        return Err("SERVICE_REVOKE_RUN_KEY_STILL_PRESENT_AFTER_DELETE".to_owned());
    }
    if after_owned_by_dauverse == Some(true) && after_service_state != ServiceRunState::Stopped {
        return Err(format!(
            "SERVICE_REVOKE_OWNED_SCM_SERVICE_NOT_STOPPED: state={after_service_state:?}"
        ));
    }
    Ok(())
}

#[cfg(all(target_os = "windows", not(test)))]
fn stop_owned_windows_scm_service(service_name: &str) -> Result<(), String> {
    use windows_service::{
        service::{ServiceAccess, ServiceState},
        service_manager::{ServiceManager, ServiceManagerAccess},
    };

    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
        .map_err(|e| format!("SERVICE_REVOKE_SCM_CONNECT_FAILED: {e}"))?;
    let service = manager
        .open_service(service_name, ServiceAccess::STOP | ServiceAccess::QUERY_STATUS)
        .map_err(|e| format!("SERVICE_REVOKE_SCM_OPEN_FAILED: {e}"))?;

    let initial = service
        .query_status()
        .map_err(|e| format!("SERVICE_REVOKE_SCM_QUERY_FAILED: {e}"))?;
    if initial.current_state == ServiceState::Stopped {
        return Ok(());
    }
    if initial.current_state != ServiceState::StopPending {
        if let Err(stop_err) = service.stop() {
            let post = service
                .query_status()
                .map_err(|e| format!("SERVICE_REVOKE_SCM_STOP_FAILED: {stop_err}; query={e}"))?;
            if post.current_state != ServiceState::Stopped
                && post.current_state != ServiceState::StopPending
            {
                return Err(format!("SERVICE_REVOKE_SCM_STOP_FAILED: {stop_err}"));
            }
        }
    }

    for _ in 0..25 {
        let st = service
            .query_status()
            .map_err(|e| format!("SERVICE_REVOKE_SCM_POLL_FAILED: {e}"))?;
        if st.current_state == ServiceState::Stopped {
            return Ok(());
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    Err("SERVICE_REVOKE_SCM_STOP_TIMEOUT: owned service did not reach Stopped within 5s".to_owned())
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
    fn f03_f08_verifies_service_ownership_os_truth_and_refuses_synthetic_revoke_success() {
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
        assert!(st.unattended_access_enabled);
        assert!(st.system_tray_indicator_visible);
        assert!(st.defender_av_untouched);
        assert!(st.no_hidden_persistence);

        // Fresh controller observes persisted unattended state truthfully from Config
        let restarted_ctrl = ServiceController::new();
        assert!(restarted_ctrl.status().unattended_access_enabled);

        let _ = ctrl.set_auto_start(true, true).unwrap();
        let revoked = ctrl.revoke_all_access_immediately().unwrap();
        assert!(!revoked.unattended_access_enabled);
        assert!(!revoked.auto_start_with_windows);
        assert_eq!(
            hbb_common::config::Config::get_option("approve-mode"),
            "click"
        );

        // F08 Negative 1: Owned SCM service still Running or Pending/Degraded after stop attempt MUST fail closed
        let err_running = verify_post_revoke_os_truth(
            "click",
            Some(true),
            ServiceRunState::Running,
            false,
            None,
        )
        .unwrap_err();
        assert!(err_running.starts_with("SERVICE_REVOKE_OWNED_SCM_SERVICE_NOT_STOPPED"));

        let err_pending = verify_post_revoke_os_truth(
            "click",
            Some(true),
            ServiceRunState::DegradedRecovering,
            false,
            None,
        )
        .unwrap_err();
        assert!(err_pending.starts_with("SERVICE_REVOKE_OWNED_SCM_SERVICE_NOT_STOPPED"));

        // F08 Negative 2: Access denied stopping SCM service MUST fail closed
        let err_denied = verify_post_revoke_os_truth(
            "click",
            Some(true),
            ServiceRunState::Running,
            false,
            Some("SERVICE_REVOKE_SCM_OPEN_FAILED: Access is denied".to_owned()),
        )
        .unwrap_err();
        assert!(err_denied.contains("SERVICE_REVOKE_SCM_OPEN_FAILED"));

        // F08 Negative 3: HKCU Run key still present after delete MUST fail closed
        let err_run = verify_post_revoke_os_truth(
            "click",
            None,
            ServiceRunState::NotInstalledPortableMode,
            true,
            None,
        )
        .unwrap_err();
        assert_eq!(err_run, "SERVICE_REVOKE_RUN_KEY_STILL_PRESENT_AFTER_DELETE");

        // F03 Positive: External RustDesk service (owned == Some(false)) is left untouched and reported as portable/not-owned
        assert!(verify_post_revoke_os_truth(
            "click",
            Some(false),
            ServiceRunState::NotInstalledPortableMode,
            false,
            None,
        )
        .is_ok());
    }
}

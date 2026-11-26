pub mod ai_bridge;
pub mod clipboard_guard;
pub mod crypto_util;
pub mod ffi;
pub mod hardware;
pub mod headless;
pub mod notifications;
pub mod performance;
pub mod security;
pub mod service_ctrl;
pub mod session_tools;
pub mod smart_power;
pub mod transfer_guard;
pub mod update_center;

use self::{
    ai_bridge::AiEventBridge,
    clipboard_guard::{ClipboardGuard, ClipboardPolicy},
    hardware::HardwareMonitor,
    headless::HeadlessManager,
    notifications::{NotificationCenter, NotificationPreferences},
    performance::{PerformanceEngine, PerformanceMode},
    security::DeviceShieldSecurityCenter,
    service_ctrl::ServiceController,
    session_tools::SessionToolsManager,
    smart_power::SmartPowerController,
    transfer_guard::TransferQueueManager,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    io::Read,
    path::PathBuf,
    sync::{atomic::AtomicBool, Arc, Mutex, OnceLock},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistedUserSettings {
    pub performance_mode: PerformanceMode,
    pub clipboard_policy: ClipboardPolicy,
    pub notification_preferences: NotificationPreferences,
    pub transfer_bandwidth_limit_kbps: Option<u32>,
    pub shortcuts: HashMap<String, String>,
}

pub struct DauverseRuntime {
    pub data_dir: PathBuf,
    pub performance: PerformanceEngine,
    pub clipboard_guard: ClipboardGuard,
    pub transfer_queue: TransferQueueManager,
    pub smart_power: SmartPowerController,
    pub headless: HeadlessManager,
    pub service_ctrl: ServiceController,
    pub ai_bridge: Arc<AiEventBridge>,
    pub notifications: Arc<NotificationCenter>,
    pub hardware: HardwareMonitor,
    pub security: DeviceShieldSecurityCenter,
    pub session_tools: SessionToolsManager,
    pub bridge_listen_port: u16,
    pub mini_control_minimized: Mutex<bool>,
    pub mini_control_idle: Mutex<bool>,
    pub storage_error: Mutex<Option<String>>,
    _bridge_stop: Arc<AtomicBool>,
}

static GLOBAL_RUNTIME: OnceLock<DauverseRuntime> = OnceLock::new();

impl DauverseRuntime {
    pub fn global() -> &'static Self {
        GLOBAL_RUNTIME.get_or_init(Self::init_default)
    }

    fn init_default() -> Self {
        #[cfg(test)]
        let base_dir = std::env::var("DAUVERSE_DATA_DIR")
            .ok()
            .filter(|s| !s.trim().is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                std::env::temp_dir().join(format!("dauverse_unit_rt_{}", uuid::Uuid::new_v4()))
            });

        #[cfg(not(test))]
        let base_dir = crypto_util::default_durable_app_data_dir();

        Self::init_at_dir(base_dir, true)
    }

    pub fn init_at_dir(base_dir: PathBuf, spawn_gateway: bool) -> Self {
        let mut init_err: Option<String> = None;
        if let Err(e) = crypto_util::ensure_private_dir(&base_dir) {
            init_err = Some(format!("DATA_DIR_INIT_FAILED: {e}"));
        }
        let transfer_root = base_dir.join("received_files");
        if let Err(e) = crypto_util::ensure_private_dir(&transfer_root) {
            if init_err.is_none() {
                init_err = Some(format!("TRANSFER_DIR_INIT_FAILED: {e}"));
            }
        }
        let offline_journal = base_dir.join("offline_notifications.json");
        let audit_log_path = base_dir.join("security_audit_chain.jsonl");
        let replay_journal_path = base_dir.join("bridge_replay_journal.json");
        let settings_path = base_dir.join("dauverse_settings_state.json");
        let vault_path = base_dir.join("bridge_hmac.vault");
        const VAULT_ENTROPY: &[u8] = b"dauverse-bridge-hmac-v1";

        let security = DeviceShieldSecurityCenter::with_audit_log_path(Some(audit_log_path));

        let bridge_secret = match std::env::var("DAUVERSE_EVENT_HMAC_KEY") {
            Ok(s) if s.len() >= 16 => s.into_bytes(),
            _ => match std::fs::symlink_metadata(&vault_path) {
                Ok(_) => match crypto_util::read_sealed_secret_file(&vault_path, VAULT_ENTROPY) {
                    Ok(sec) if sec.len() >= 16 => sec,
                    Err(e) => {
                        let msg = format!("BRIDGE_VAULT_CORRUPTED_FAIL_CLOSED: {e}");
                        security.append_audit(
                            "SYSTEM",
                            "BRIDGE_VAULT_INTEGRITY",
                            "FAILED_CLOSED",
                            &msg,
                        );
                        if init_err.is_none() {
                            init_err = Some(msg);
                        }
                        crypto_util::generate_nonce_hex().into_bytes()
                    }
                    Ok(_) => {
                        let msg = "BRIDGE_VAULT_CORRUPTED_FAIL_CLOSED: truncated key".to_owned();
                        if init_err.is_none() {
                            init_err = Some(msg);
                        }
                        crypto_util::generate_nonce_hex().into_bytes()
                    }
                },
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                    let generated = crypto_util::generate_nonce_hex().into_bytes();
                    if let Err(e) = crypto_util::write_sealed_secret_file(
                        &vault_path,
                        &generated,
                        VAULT_ENTROPY,
                    ) {
                        if init_err.is_none() {
                            init_err = Some(format!("BRIDGE_VAULT_WRITE_FAILED: {e}"));
                        }
                    }
                    generated
                }
                Err(e) => {
                    let msg = format!("BRIDGE_VAULT_STAT_ERROR_FAIL_CLOSED: {e}");
                    security.append_audit(
                        "SYSTEM",
                        "BRIDGE_VAULT_INTEGRITY",
                        "FAILED_CLOSED",
                        &msg,
                    );
                    if init_err.is_none() {
                        init_err = Some(msg);
                    }
                    crypto_util::generate_nonce_hex().into_bytes()
                }
            },
        };

        let ai_bridge = Arc::new(AiEventBridge::with_persistence_and_limits(
            bridge_secret,
            Some(replay_journal_path),
            65_536,
        ));
        if let Some(rj_err) = ai_bridge.replay_journal_error() {
            security.append_audit(
                "SYSTEM",
                "REPLAY_JOURNAL_INTEGRITY",
                "FAILED_CLOSED",
                &rj_err,
            );
            if init_err.is_none() {
                init_err = Some(rj_err);
            }
        }
        let notifications = Arc::new(NotificationCenter::new(Some(offline_journal)));
        if let Some(nj_err) = notifications.journal_error() {
            security.append_audit(
                "SYSTEM",
                "NOTIFICATION_JOURNAL_INTEGRITY",
                "FAILED_CLOSED",
                &nj_err,
            );
            if init_err.is_none() {
                init_err = Some(nj_err);
            }
        }
        let performance = PerformanceEngine::new();
        let clipboard_guard = ClipboardGuard::new();
        let transfer_queue = TransferQueueManager::new(transfer_root);
        let session_tools = SessionToolsManager::new();

        match std::fs::symlink_metadata(&settings_path) {
            Ok(_) => match crypto_util::open_no_follow_regular_file(&settings_path) {
                Ok((mut f, _)) => {
                    let mut raw = String::new();
                    match f.read_to_string(&mut raw).ok().and_then(|_| {
                        serde_json::from_str::<PersistedUserSettings>(&raw).ok()
                    }) {
                        Some(saved) => {
                            performance.set_mode(saved.performance_mode);
                            clipboard_guard.update_policy(saved.clipboard_policy);
                            notifications.update_preferences(saved.notification_preferences);
                            transfer_queue.set_bandwidth_limit_kbps(saved.transfer_bandwidth_limit_kbps);
                            session_tools.set_shortcuts_map(saved.shortcuts);
                        }
                        None => {
                            let msg = "SETTINGS_STATE_CORRUPTED_FAIL_CLOSED: invalid dauverse_settings_state.json".to_owned();
                            security.append_audit("SYSTEM", "LOAD_SETTINGS_STATE", "FAILED_CLOSED", &msg);
                            if init_err.is_none() {
                                init_err = Some(msg);
                            }
                        }
                    }
                }
                Err(e) => {
                    if init_err.is_none() {
                        init_err = Some(format!("SETTINGS_STATE_OPEN_FAILED_FAIL_CLOSED: {e}"));
                    }
                }
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => {
                let msg = format!("SETTINGS_STATE_STAT_ERROR_FAIL_CLOSED: {e}");
                security.append_audit("SYSTEM", "LOAD_SETTINGS_STATE", "FAILED_CLOSED", &msg);
                if init_err.is_none() {
                    init_err = Some(msg);
                }
            }
        }

        let stop_flag = Arc::new(AtomicBool::new(false));
        let bound_port = if spawn_gateway {
            let preferred_port = std::env::var("DAUVERSE_EVENT_BRIDGE_PORT")
                .ok()
                .and_then(|v| v.parse::<u16>().ok())
                .unwrap_or(21188);
            let notif_sink = notifications.clone();
            let cb: Arc<dyn Fn(&ai_bridge::AiEvent, i64) + Send + Sync> =
                Arc::new(move |ev, now_ms| {
                    notif_sink.publish_from_ai_event(ev, now_ms);
                });

            let port = AiEventBridge::spawn_loopback_http_gateway_with_sink(
                ai_bridge.clone(),
                preferred_port,
                stop_flag.clone(),
                Some(cb.clone()),
            )
            .or_else(|_| {
                AiEventBridge::spawn_loopback_http_gateway_with_sink(
                    ai_bridge.clone(),
                    0,
                    stop_flag.clone(),
                    Some(cb),
                )
            })
            .map(|(p, _handle)| p)
            .unwrap_or(0);

            if port > 0 {
                let endpoint_meta = serde_json::json!({
                    "endpoint": format!("http://127.0.0.1:{port}/v1/events"),
                    "health_url": format!("http://127.0.0.1:{port}/v1/health"),
                    "port": port,
                });
                if let Err(e) = crypto_util::write_atomic_bytes(
                    &base_dir.join("bridge_endpoint.json"),
                    endpoint_meta.to_string().as_bytes(),
                    true,
                ) {
                    if init_err.is_none() {
                        init_err = Some(format!("ENDPOINT_METADATA_WRITE_FAILED: {e}"));
                    }
                }
            }
            port
        } else {
            0
        };

        Self {
            data_dir: base_dir,
            performance,
            clipboard_guard,
            transfer_queue,
            smart_power: SmartPowerController::new(),
            headless: HeadlessManager::new(),
            service_ctrl: ServiceController::new(),
            ai_bridge,
            notifications,
            hardware: HardwareMonitor::new(),
            security,
            session_tools,
            bridge_listen_port: bound_port,
            mini_control_minimized: Mutex::new(false),
            mini_control_idle: Mutex::new(false),
            storage_error: Mutex::new(init_err),
            _bridge_stop: stop_flag,
        }
    }

    pub fn persist_user_settings(&self) -> Result<(), String> {
        if let Some(existing_err) = self.storage_error.lock().unwrap().clone() {
            if existing_err.contains("FAIL_CLOSED") {
                return Err(existing_err);
            }
        }
        let state = PersistedUserSettings {
            performance_mode: self.performance.get_mode(),
            clipboard_policy: self.clipboard_guard.get_policy(),
            notification_preferences: self.notifications.preferences(),
            transfer_bandwidth_limit_kbps: self.transfer_queue.get_bandwidth_limit_kbps(),
            shortcuts: self.session_tools.shortcuts(),
        };
        let bytes = serde_json::to_vec_pretty(&state)
            .map_err(|e| format!("SETTINGS_SERIALIZE_ERROR: {e}"))?;
        let path = self.data_dir.join("dauverse_settings_state.json");
        match crypto_util::write_atomic_bytes(&path, &bytes, true) {
            Ok(()) => Ok(()),
            Err(e) => {
                *self.storage_error.lock().unwrap() = Some(e.clone());
                Err(e)
            }
        }
    }

    pub fn dashboard_snapshot(&self) -> serde_json::Value {
        let svc_running = self.service_ctrl.is_service_running();
        let (hw, hw_alerts) = self.hardware.sample_now_with_service_health(svc_running);
        let (ai_running, ai_waiting_approval, comfy_rendering) = self.ai_bridge.active_counts();
        let live_tasks = self.ai_bridge.live_tasks();
        let ai_completed = live_tasks
            .iter()
            .filter(|t| t.status == ai_bridge::AiTaskStatus::Completed)
            .count();

        let mut net_sample = performance::NetworkRuntimeSample::default();
        net_sample.host_cpu_pct = hw.cpu_usage_pct;
        net_sample.host_gpu_pct = hw.gpu_usage_pct.unwrap_or(0.0);
        net_sample.host_vram_pct = hw.vram_usage_pct.unwrap_or(0.0);
        net_sample.ai_workload_active = ai_running > 0;
        net_sample.comfyui_rendering = comfy_rendering;
        net_sample.mini_control_minimized = *self.mini_control_minimized.lock().unwrap();
        net_sample.mini_control_idle = *self.mini_control_idle.lock().unwrap();
        let perf = self.performance.update_runtime_sample(net_sample);

        let local_id = hbb_common::config::Config::get_id();
        let sec_summary = self.security.summary();
        let sec_persist_ok = sec_summary
            .get("persistence_healthy")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let storage_err = self
            .storage_error
            .lock()
            .unwrap()
            .clone()
            .or_else(|| self.ai_bridge.replay_journal_error())
            .or_else(|| self.notifications.journal_error())
            .or_else(|| {
                sec_summary
                    .get("last_persistence_error")
                    .and_then(|v| v.as_str())
                    .map(str::to_owned)
            });
        let storage_healthy = storage_err.is_none()
            && self.ai_bridge.is_replay_journal_healthy()
            && self.notifications.journal_healthy()
            && sec_persist_ok;

        serde_json::json!({
            "product": "DAUVERSE REMOTE DESKTOP",
            "version": update_center::DAUVERSE_PRODUCT_VERSION,
            "engine_base": update_center::UPSTREAM_ENGINE_VERSION,
            "local_peer_id": local_id,
            "data_dir": self.data_dir.to_string_lossy(),
            "storage_healthy": storage_healthy,
            "storage_error": storage_err,
            "bridge_endpoint": if self.bridge_listen_port > 0 {
                format!("http://127.0.0.1:{}/v1/events", self.bridge_listen_port)
            } else {
                "UNBOUND".to_owned()
            },
            "bridge_port": self.bridge_listen_port,
            "hardware": hw,
            "hardware_alerts": hw_alerts,
            "performance": perf,
            "ai_summary": {
                "running": ai_running,
                "waiting_approval": ai_waiting_approval,
                "completed": ai_completed,
                "comfyui_rendering": comfy_rendering,
                "live_tasks": live_tasks,
                "recent_events": self.ai_bridge.recent_events(),
                "rejected_security_count": self.ai_bridge.rejected_security_count(),
                "replay_journal_healthy": self.ai_bridge.is_replay_journal_healthy(),
                "replay_journal_error": self.ai_bridge.replay_journal_error(),
                "sources_catalog": AiEventBridge::supported_sources_catalog(),
            },
            "notifications": {
                "unread_count": self.notifications.unread_count(),
                "active_toasts": self.notifications.active_toasts(),
                "recent_items": self.notifications.query_history(&notifications::NotificationFilter::default()),
                "preferences": self.notifications.preferences(),
                "journal_healthy": self.notifications.journal_healthy(),
                "journal_error": self.notifications.journal_error(),
            },
            "clipboard": self.clipboard_guard.stats(),
            "transfer_queue": {
                "authorized_root": self.transfer_queue.get_authorized_root(),
                "bandwidth_limit_kbps": self.transfer_queue.get_bandwidth_limit_kbps(),
                "active_count": self.transfer_queue.active_transfer_count(),
                "jobs": self.transfer_queue.list_jobs(),
            },
            "smart_power": {
                "host_state": self.smart_power.get_host_state(),
                "smart_plug": self.smart_power.plug_status(),
                "recent_events": self.smart_power.recent_events(),
            },
            "headless": self.headless.get_state(),
            "service": self.service_ctrl.status(),
            "security": {
                "summary": sec_summary,
                "recent_audit": self.security.recent_audit_entries(30),
            },
            "release": update_center::current_release_status(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f07_settings_and_vault_persist_across_restart_and_corrupted_files_fail_closed() {
        let dir = std::env::temp_dir().join(format!("dv_rt_persist_{}", uuid::Uuid::new_v4()));
        {
            let rt1 = DauverseRuntime::init_at_dir(dir.clone(), false);
            rt1.performance.set_mode(PerformanceMode::HighQuality);
            let mut pol = rt1.clipboard_guard.get_policy();
            pol.allow_files = false;
            rt1.clipboard_guard.update_policy(pol);
            let mut prefs = rt1.notifications.preferences();
            prefs.quiet_mode = true;
            rt1.notifications.update_preferences(prefs);
            rt1.transfer_queue.set_bandwidth_limit_kbps(Some(4096));
            rt1.session_tools
                .update_shortcut("toggle_mini_control", "Ctrl+Shift+M")
                .unwrap();
            rt1.persist_user_settings().unwrap();
            rt1.security.set_step_up_passcode("Persist#2026").unwrap();
        }

        {
            let rt2 = DauverseRuntime::init_at_dir(dir.clone(), false);
            assert_eq!(rt2.performance.get_mode(), PerformanceMode::HighQuality);
            assert!(!rt2.clipboard_guard.get_policy().allow_files);
            assert!(rt2.notifications.preferences().quiet_mode);
            assert_eq!(rt2.transfer_queue.get_bandwidth_limit_kbps(), Some(4096));
            assert_eq!(
                rt2.session_tools
                    .shortcuts()
                    .get("toggle_mini_control")
                    .map(String::as_str),
                Some("Ctrl+Shift+M")
            );
            assert!(rt2.security.verify_step_up_passcode("Persist#2026"));
        }

        // Corrupt dauverse_settings_state.json -> runtime detects corruption and fails closed on writes
        std::fs::write(dir.join("dauverse_settings_state.json"), b"{invalid-json").unwrap();
        let rt3 = DauverseRuntime::init_at_dir(dir.clone(), false);
        assert!(rt3.storage_error.lock().unwrap().is_some());
        assert!(rt3.persist_user_settings().is_err());

        std::fs::remove_dir_all(&dir).ok();
    }
}

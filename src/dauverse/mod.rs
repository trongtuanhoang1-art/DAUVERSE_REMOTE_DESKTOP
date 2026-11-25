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
    clipboard_guard::ClipboardGuard,
    hardware::HardwareMonitor,
    headless::HeadlessManager,
    notifications::NotificationCenter,
    performance::PerformanceEngine,
    security::DeviceShieldSecurityCenter,
    service_ctrl::ServiceController,
    session_tools::SessionToolsManager,
    smart_power::SmartPowerController,
    transfer_guard::TransferQueueManager,
};
use std::{
    path::PathBuf,
    sync::{atomic::AtomicBool, Arc, Mutex, OnceLock},
};

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
    _bridge_stop: Arc<AtomicBool>,
}

static GLOBAL_RUNTIME: OnceLock<DauverseRuntime> = OnceLock::new();

impl DauverseRuntime {
    pub fn global() -> &'static Self {
        GLOBAL_RUNTIME.get_or_init(Self::init_default)
    }

    fn init_default() -> Self {
        let base_dir = std::env::var("DAUVERSE_DATA_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let mut p = std::env::temp_dir();
                p.push("dauverse_remote_v1");
                p
            });
        let _ = std::fs::create_dir_all(&base_dir);
        let transfer_root = base_dir.join("received_files");
        let _ = std::fs::create_dir_all(&transfer_root);
        let offline_journal = base_dir.join("offline_notifications.json");
        let audit_log_path = base_dir.join("security_audit_chain.jsonl");
        let vault_path = base_dir.join("bridge_hmac.vault");
        const VAULT_ENTROPY: &[u8] = b"dauverse-bridge-hmac-v1";

        let bridge_secret = match std::env::var("DAUVERSE_EVENT_HMAC_KEY") {
            Ok(s) if s.len() >= 16 => s.into_bytes(),
            _ => match crypto_util::read_sealed_secret_file(&vault_path, VAULT_ENTROPY) {
                Ok(sec) if sec.len() >= 16 => sec,
                _ => {
                    let generated = crypto_util::generate_nonce_hex().into_bytes();
                    let _ = crypto_util::write_sealed_secret_file(
                        &vault_path,
                        &generated,
                        VAULT_ENTROPY,
                    );
                    generated
                }
            },
        };

        let ai_bridge = Arc::new(AiEventBridge::new(bridge_secret));
        let notifications = Arc::new(NotificationCenter::new(Some(offline_journal)));
        let security = DeviceShieldSecurityCenter::with_audit_log_path(Some(audit_log_path));

        let preferred_port = std::env::var("DAUVERSE_EVENT_BRIDGE_PORT")
            .ok()
            .and_then(|v| v.parse::<u16>().ok())
            .unwrap_or(21188);
        let stop_flag = Arc::new(AtomicBool::new(false));
        let notif_sink = notifications.clone();
        let cb: Arc<dyn Fn(&ai_bridge::AiEvent, i64) + Send + Sync> =
            Arc::new(move |ev, now_ms| {
                notif_sink.publish_from_ai_event(ev, now_ms);
            });

        let bound_port = AiEventBridge::spawn_loopback_http_gateway_with_sink(
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

        if bound_port > 0 {
            let endpoint_meta = serde_json::json!({
                "endpoint": format!("http://127.0.0.1:{bound_port}/v1/events"),
                "health_url": format!("http://127.0.0.1:{bound_port}/v1/health"),
                "port": bound_port,
            });
            let _ = std::fs::write(
                base_dir.join("bridge_endpoint.json"),
                endpoint_meta.to_string(),
            );
        }

        Self {
            data_dir: base_dir,
            performance: PerformanceEngine::new(),
            clipboard_guard: ClipboardGuard::new(),
            transfer_queue: TransferQueueManager::new(transfer_root),
            smart_power: SmartPowerController::new(),
            headless: HeadlessManager::new(),
            service_ctrl: ServiceController::new(),
            ai_bridge,
            notifications,
            hardware: HardwareMonitor::new(),
            security,
            session_tools: SessionToolsManager::new(),
            bridge_listen_port: bound_port,
            mini_control_minimized: Mutex::new(false),
            mini_control_idle: Mutex::new(false),
            _bridge_stop: stop_flag,
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

        serde_json::json!({
            "product": "DAUVERSE REMOTE DESKTOP",
            "version": update_center::DAUVERSE_PRODUCT_VERSION,
            "engine_base": update_center::UPSTREAM_ENGINE_VERSION,
            "local_peer_id": local_id,
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
                "sources_catalog": AiEventBridge::supported_sources_catalog(),
            },
            "notifications": {
                "unread_count": self.notifications.unread_count(),
                "active_toasts": self.notifications.active_toasts(),
                "recent_items": self.notifications.query_history(&notifications::NotificationFilter::default()),
                "preferences": self.notifications.preferences(),
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
                "summary": self.security.summary(),
                "recent_audit": self.security.recent_audit_entries(30),
            },
            "release": update_center::current_release_status(),
        })
    }
}

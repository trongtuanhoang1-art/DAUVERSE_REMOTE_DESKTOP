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
use std::{path::PathBuf, sync::{Arc, OnceLock}};

pub struct DauverseRuntime {
    pub data_dir: PathBuf,
    pub performance: PerformanceEngine,
    pub clipboard_guard: ClipboardGuard,
    pub transfer_queue: TransferQueueManager,
    pub smart_power: SmartPowerController,
    pub headless: HeadlessManager,
    pub service_ctrl: ServiceController,
    pub ai_bridge: Arc<AiEventBridge>,
    pub notifications: NotificationCenter,
    pub hardware: HardwareMonitor,
    pub security: DeviceShieldSecurityCenter,
    pub session_tools: SessionToolsManager,
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

        let bridge_secret = std::env::var("DAUVERSE_EVENT_HMAC_KEY")
            .map(|s| s.into_bytes())
            .unwrap_or_else(|_| crypto_util::generate_nonce_hex().into_bytes());

        Self {
            data_dir: base_dir,
            performance: PerformanceEngine::new(),
            clipboard_guard: ClipboardGuard::new(),
            transfer_queue: TransferQueueManager::new(transfer_root),
            smart_power: SmartPowerController::new(),
            headless: HeadlessManager::new(),
            service_ctrl: ServiceController::new(),
            ai_bridge: Arc::new(AiEventBridge::new(bridge_secret)),
            notifications: NotificationCenter::new(Some(offline_journal)),
            hardware: HardwareMonitor::new(),
            security: DeviceShieldSecurityCenter::new(),
            session_tools: SessionToolsManager::new(),
        }
    }

    pub fn dashboard_snapshot(&self) -> serde_json::Value {
        let (hw, hw_alerts) = self.hardware.sample_now();
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
        let perf = self.performance.update_runtime_sample(net_sample);

        serde_json::json!({
            "product": "DAUVERSE REMOTE DESKTOP",
            "version": update_center::DAUVERSE_PRODUCT_VERSION,
            "engine_base": update_center::UPSTREAM_ENGINE_VERSION,
            "hardware": hw,
            "hardware_alerts": hw_alerts,
            "performance": perf,
            "ai_summary": {
                "running": ai_running,
                "waiting_approval": ai_waiting_approval,
                "completed": ai_completed,
                "comfyui_rendering": comfy_rendering,
                "live_tasks": live_tasks,
                "sources_catalog": AiEventBridge::supported_sources_catalog(),
            },
            "notifications": {
                "unread_count": self.notifications.unread_count(),
                "active_toasts": self.notifications.active_toasts(),
                "preferences": self.notifications.preferences(),
            },
            "smart_power": {
                "host_state": self.smart_power.get_host_state(),
                "smart_plug": self.smart_power.plug_status(),
            },
            "headless": self.headless.get_state(),
            "service": self.service_ctrl.status(),
            "security": self.security.summary(),
            "release": update_center::current_release_status(),
        })
    }
}

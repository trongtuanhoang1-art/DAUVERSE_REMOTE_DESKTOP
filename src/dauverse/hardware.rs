use hbb_common::sysinfo::{Components, Disks, Networks, System};
use serde::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    process::Command,
    sync::Mutex,
    time::Instant,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiProcessTelemetry {
    pub pid: u32,
    pub name: String,
    pub category: String,
    pub cpu_pct: f32,
    pub memory_mb: u64,
    pub disk_read_bytes: u64,
    pub disk_written_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareSnapshot {
    pub captured_at_utc: String,
    pub telemetry_scope: String,
    pub cpu_brand: String,
    pub cpu_usage_pct: f32,
    pub cpu_temp_c: Option<f32>,
    pub ram_used_gb: f64,
    pub ram_total_gb: f64,
    pub ram_usage_pct: f32,
    pub gpu_model: Option<String>,
    pub gpu_usage_pct: Option<f32>,
    pub gpu_temp_c: Option<f32>,
    pub vram_used_mb: Option<u64>,
    pub vram_total_mb: Option<u64>,
    pub vram_usage_pct: Option<f32>,
    pub gpu_power_watts: Option<f32>,
    pub disk_used_gb: f64,
    pub disk_free_gb: f64,
    pub disk_total_gb: f64,
    pub disk_usage_pct: f32,
    pub disk_activity_read_bytes: u64,
    pub disk_activity_write_bytes: u64,
    pub net_upload_bps: u64,
    pub net_download_bps: u64,
    pub system_uptime_secs: u64,
    pub remote_service_healthy: bool,
    pub ai_processes: Vec<AiProcessTelemetry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareThresholds {
    pub gpu_temp_max_c: f32,
    pub cpu_temp_max_c: f32,
    pub ram_max_pct: f32,
    pub vram_max_pct: f32,
    pub disk_min_free_gb: f64,
    pub sampling_interval_ms: u64,
    pub allow_ai_process_monitoring: bool,
}

impl Default for HardwareThresholds {
    fn default() -> Self {
        Self {
            gpu_temp_max_c: 83.0,
            cpu_temp_max_c: 88.0,
            ram_max_pct: 90.0,
            vram_max_pct: 92.0,
            disk_min_free_gb: 10.0,
            sampling_interval_ms: 2_000,
            allow_ai_process_monitoring: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HardwareAlert {
    pub code: String,
    pub message: String,
}

struct NetRateTracker {
    last_rx: u64,
    last_tx: u64,
    last_instant: Instant,
    initialized: bool,
}

pub struct HardwareMonitor {
    sys: Mutex<System>,
    networks: Mutex<Networks>,
    net_tracker: Mutex<NetRateTracker>,
    thresholds: Mutex<HardwareThresholds>,
    history: Mutex<VecDeque<HardwareSnapshot>>,
    gpu_cache: Mutex<Option<(Instant, NvidiaGpuReading)>>,
}

impl HardwareMonitor {
    pub fn new() -> Self {
        let mut sys = System::new();
        sys.refresh_cpu();
        sys.refresh_memory();
        Self {
            sys: Mutex::new(sys),
            networks: Mutex::new(Networks::new_with_refreshed_list()),
            net_tracker: Mutex::new(NetRateTracker {
                last_rx: 0,
                last_tx: 0,
                last_instant: Instant::now(),
                initialized: false,
            }),
            thresholds: Mutex::new(HardwareThresholds::default()),
            history: Mutex::new(VecDeque::with_capacity(120)),
            gpu_cache: Mutex::new(None),
        }
    }

    pub fn get_thresholds(&self) -> HardwareThresholds {
        self.thresholds.lock().unwrap().clone()
    }

    pub fn update_thresholds(&self, mut next: HardwareThresholds) -> HardwareThresholds {
        next.sampling_interval_ms = next.sampling_interval_ms.clamp(500, 60_000);
        let mut g = self.thresholds.lock().unwrap();
        *g = next.clone();
        next
    }

    pub fn sample_now(&self) -> (HardwareSnapshot, Vec<HardwareAlert>) {
        #[cfg(target_os = "windows")]
        let svc_ok = crate::platform::windows::is_self_service_running();
        #[cfg(not(target_os = "windows"))]
        let svc_ok = false;
        self.sample_now_with_service_health(svc_ok)
    }

    pub fn sample_now_with_service_health(&self, service_healthy: bool) -> (HardwareSnapshot, Vec<HardwareAlert>) {
        let cfg = self.thresholds.lock().unwrap().clone();
        let (
            cpu_brand,
            cpu_usage_pct,
            ram_used,
            ram_total,
            uptime_secs,
            disk_read_total,
            disk_write_total,
            ai_procs,
        ) = {
            let mut sys = self.sys.lock().unwrap();
            sys.refresh_cpu();
            sys.refresh_memory();
            if cfg.allow_ai_process_monitoring {
                sys.refresh_processes();
            }

            let cpus = sys.cpus();
            let brand = cpus
                .first()
                .map(|c| c.brand().trim().to_owned())
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "System CPU".to_owned());
            let avg_cpu = if cpus.is_empty() {
                0.0
            } else {
                cpus.iter().map(|c| c.cpu_usage()).sum::<f32>() / (cpus.len() as f32)
            };

            let mut total_r = 0u64;
            let mut total_w = 0u64;
            let mut tracked_ai = Vec::new();
            if cfg.allow_ai_process_monitoring {
                for (pid, proc_info) in sys.processes() {
                    let du = proc_info.disk_usage();
                    total_r = total_r.saturating_add(du.read_bytes);
                    total_w = total_w.saturating_add(du.written_bytes);

                    let pname = proc_info.name().to_owned();
                    if let Some(cat) = Self::classify_ai_process_name(&pname) {
                        tracked_ai.push(AiProcessTelemetry {
                            pid: pid.as_u32(),
                            name: pname,
                            category: cat.to_owned(),
                            cpu_pct: proc_info.cpu_usage(),
                            memory_mb: proc_info.memory() / (1024 * 1024),
                            disk_read_bytes: du.total_read_bytes,
                            disk_written_bytes: du.total_written_bytes,
                        });
                    }
                }
                tracked_ai.sort_by(|a, b| b.memory_mb.cmp(&a.memory_mb));
                tracked_ai.truncate(12);
            }

            (
                brand,
                avg_cpu,
                sys.used_memory(),
                sys.total_memory(),
                sys.uptime(),
                total_r,
                total_w,
                tracked_ai,
            )
        };

        let components = Components::new_with_refreshed_list();
        let cpu_temp_c = components
            .iter()
            .filter(|c| {
                let l = c.label().to_ascii_lowercase();
                l.contains("cpu") || l.contains("package") || l.contains("core") || l.contains("tctl")
            })
            .map(|c| c.temperature())
            .find(|t| t.is_finite() && *t > 0.0 && *t < 130.0);

        let disks = Disks::new_with_refreshed_list();
        let mut disk_total = 0u64;
        let mut disk_free = 0u64;
        for d in disks.list() {
            disk_total = disk_total.saturating_add(d.total_space());
            disk_free = disk_free.saturating_add(d.available_space());
        }
        let disk_used = disk_total.saturating_sub(disk_free);

        let (net_down_bps, net_up_bps) = {
            let mut nets = self.networks.lock().unwrap();
            nets.refresh();
            let mut rx_sum = 0u64;
            let mut tx_sum = 0u64;
            for (_if_name, data) in nets.list() {
                rx_sum = rx_sum.saturating_add(data.total_received());
                tx_sum = tx_sum.saturating_add(data.total_transmitted());
            }
            let mut tr = self.net_tracker.lock().unwrap();
            let now = Instant::now();
            if !tr.initialized {
                tr.last_rx = rx_sum;
                tr.last_tx = tx_sum;
                tr.last_instant = now;
                tr.initialized = true;
                (0u64, 0u64)
            } else {
                let dt = now.duration_since(tr.last_instant).as_secs_f64().max(0.05);
                let rx_bps = ((rx_sum.saturating_sub(tr.last_rx)) as f64 / dt) as u64;
                let tx_bps = ((tx_sum.saturating_sub(tr.last_tx)) as f64 / dt) as u64;
                tr.last_rx = rx_sum;
                tr.last_tx = tx_sum;
                tr.last_instant = now;
                (rx_bps, tx_bps)
            }
        };

        let gpu = self.query_nvidia_smi_cached();

        let ram_total_gb = (ram_total as f64) / (1024.0 * 1024.0 * 1024.0);
        let ram_used_gb = (ram_used as f64) / (1024.0 * 1024.0 * 1024.0);
        let ram_pct = if ram_total > 0 {
            ((ram_used as f64 / ram_total as f64) * 100.0) as f32
        } else {
            0.0
        };

        let disk_total_gb = (disk_total as f64) / (1024.0 * 1024.0 * 1024.0);
        let disk_free_gb = (disk_free as f64) / (1024.0 * 1024.0 * 1024.0);
        let disk_used_gb = (disk_used as f64) / (1024.0 * 1024.0 * 1024.0);
        let disk_pct = if disk_total > 0 {
            ((disk_used as f64 / disk_total as f64) * 100.0) as f32
        } else {
            0.0
        };

        let vram_pct = match (gpu.vram_used_mb, gpu.vram_total_mb) {
            (Some(u), Some(t)) if t > 0 => Some(((u as f64 / t as f64) * 100.0) as f32),
            _ => None,
        };

        let snapshot = HardwareSnapshot {
            captured_at_utc: chrono::Utc::now().to_rfc3339(),
            telemetry_scope: "LOCAL_HOST_SENSORS".to_owned(),
            cpu_brand,
            cpu_usage_pct: (cpu_usage_pct * 10.0).round() / 10.0,
            cpu_temp_c,
            ram_used_gb: (ram_used_gb * 100.0).round() / 100.0,
            ram_total_gb: (ram_total_gb * 100.0).round() / 100.0,
            ram_usage_pct: (ram_pct * 10.0).round() / 100.0 * 10.0,
            gpu_model: gpu.model,
            gpu_usage_pct: gpu.util_pct,
            gpu_temp_c: gpu.temp_c,
            vram_used_mb: gpu.vram_used_mb,
            vram_total_mb: gpu.vram_total_mb,
            vram_usage_pct: vram_pct,
            gpu_power_watts: gpu.power_watts,
            disk_used_gb: (disk_used_gb * 100.0).round() / 100.0,
            disk_free_gb: (disk_free_gb * 100.0).round() / 100.0,
            disk_total_gb: (disk_total_gb * 100.0).round() / 100.0,
            disk_usage_pct: (disk_pct * 10.0).round() / 100.0,
            disk_activity_read_bytes: disk_read_total,
            disk_activity_write_bytes: disk_write_total,
            net_upload_bps: net_up_bps,
            net_download_bps: net_down_bps,
            system_uptime_secs: uptime_secs,
            remote_service_healthy: service_healthy,
            ai_processes: ai_procs,
        };

        let alerts = Self::evaluate_thresholds(&snapshot, &cfg);
        {
            let mut hist = self.history.lock().unwrap();
            if hist.len() >= 120 {
                hist.pop_front();
            }
            hist.push_back(snapshot.clone());
        }
        (snapshot, alerts)
    }

    pub fn history(&self) -> Vec<HardwareSnapshot> {
        self.history.lock().unwrap().iter().cloned().collect()
    }

    pub fn evaluate_thresholds(
        snap: &HardwareSnapshot,
        cfg: &HardwareThresholds,
    ) -> Vec<HardwareAlert> {
        let mut alerts = Vec::new();
        if let Some(gt) = snap.gpu_temp_c {
            if gt >= cfg.gpu_temp_max_c {
                alerts.push(HardwareAlert {
                    code: "GPU_OVERHEAT".to_owned(),
                    message: format!("GPU temperature {gt:.1}°C >= threshold {:.1}°C", cfg.gpu_temp_max_c),
                });
            }
        }
        if let Some(ct) = snap.cpu_temp_c {
            if ct >= cfg.cpu_temp_max_c {
                alerts.push(HardwareAlert {
                    code: "CPU_OVERHEAT".to_owned(),
                    message: format!("CPU temperature {ct:.1}°C >= threshold {:.1}°C", cfg.cpu_temp_max_c),
                });
            }
        }
        if snap.ram_usage_pct >= cfg.ram_max_pct {
            alerts.push(HardwareAlert {
                code: "RAM_THRESHOLD_EXCEEDED".to_owned(),
                message: format!("RAM usage {:.1}% >= threshold {:.1}%", snap.ram_usage_pct, cfg.ram_max_pct),
            });
        }
        if let Some(vp) = snap.vram_usage_pct {
            if vp >= cfg.vram_max_pct {
                alerts.push(HardwareAlert {
                    code: "VRAM_THRESHOLD_EXCEEDED".to_owned(),
                    message: format!("VRAM usage {vp:.1}% >= threshold {:.1}%", cfg.vram_max_pct),
                });
            }
        }
        if snap.disk_total_gb > 0.0 && snap.disk_free_gb <= cfg.disk_min_free_gb {
            alerts.push(HardwareAlert {
                code: "DISK_SPACE_LOW".to_owned(),
                message: format!("Free disk {:.2} GB <= threshold {:.2} GB", snap.disk_free_gb, cfg.disk_min_free_gb),
            });
        }
        alerts
    }

    fn classify_ai_process_name(name: &str) -> Option<&'static str> {
        let lower = name.to_ascii_lowercase();
        if lower.contains("claude") {
            Some("Claude")
        } else if lower.contains("codex") {
            Some("Codex")
        } else if lower.contains("antigravity") {
            Some("Antigravity")
        } else if lower.contains("comfy") {
            Some("ComfyUI")
        } else if lower.contains("ollama") {
            Some("Local LLM")
        } else if lower == "rustc" || lower == "cargo" || lower == "dart" {
            Some("Build / QA Toolchain")
        } else {
            None
        }
    }

    fn query_nvidia_smi_cached(&self) -> NvidiaGpuReading {
        {
            let cache = self.gpu_cache.lock().unwrap();
            if let Some((ts, ref cached)) = *cache {
                if ts.elapsed().as_secs() < 4 {
                    return cached.clone();
                }
            }
        }
        let fresh = Self::query_nvidia_smi();
        let mut cache = self.gpu_cache.lock().unwrap();
        *cache = Some((Instant::now(), fresh.clone()));
        fresh
    }

    fn query_nvidia_smi() -> NvidiaGpuReading {
        let mut cmd = Command::new("nvidia-smi");
        cmd.args([
            "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
            "--format=csv,noheader,nounits",
        ]);
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x08000000;
            cmd.creation_flags(CREATE_NO_WINDOW);
        }
        let output = cmd.output();
        let Ok(out) = output else {
            return NvidiaGpuReading::default();
        };
        if !out.status.success() {
            return NvidiaGpuReading::default();
        };
        let line = String::from_utf8_lossy(&out.stdout);
        let Some(first_line) = line.lines().next() else {
            return NvidiaGpuReading::default();
        };
        let parts: Vec<&str> = first_line.split(',').map(|s| s.trim()).collect();
        if parts.len() < 6 {
            return NvidiaGpuReading::default();
        };
        NvidiaGpuReading {
            model: Some(parts[0].to_owned()),
            util_pct: parts[1].parse::<f32>().ok(),
            temp_c: parts[2].parse::<f32>().ok(),
            vram_used_mb: parts[3].parse::<u64>().ok(),
            vram_total_mb: parts[4].parse::<u64>().ok(),
            power_watts: parts[5].parse::<f32>().ok(),
        }
    }
}

#[derive(Default, Clone)]
struct NvidiaGpuReading {
    model: Option<String>,
    util_pct: Option<f32>,
    temp_c: Option<f32>,
    vram_used_mb: Option<u64>,
    vram_total_mb: Option<u64>,
    power_watts: Option<f32>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collects_real_host_hardware_metrics_and_evaluates_thresholds() {
        let mon = HardwareMonitor::new();
        let (mut snap, _) = mon.sample_now();
        assert_eq!(snap.telemetry_scope, "LOCAL_HOST_SENSORS");
        assert!(snap.ram_total_gb > 0.1);
        assert!(snap.system_uptime_secs > 0);
        assert!(!snap.cpu_brand.is_empty());

        snap.gpu_temp_c = Some(89.0);
        snap.vram_usage_pct = Some(95.0);
        snap.disk_total_gb = 500.0;
        snap.disk_free_gb = 4.0;
        let alerts = HardwareMonitor::evaluate_thresholds(&snap, &HardwareThresholds::default());
        assert!(alerts.iter().any(|a| a.code == "GPU_OVERHEAT"));
        assert!(alerts.iter().any(|a| a.code == "VRAM_THRESHOLD_EXCEEDED"));
        assert!(alerts.iter().any(|a| a.code == "DISK_SPACE_LOW"));
    }
}

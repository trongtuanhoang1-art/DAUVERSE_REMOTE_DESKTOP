use serde::{Deserialize, Serialize};
use std::{
    net::{TcpListener, TcpStream},
    io::{Read, Write},
    sync::Mutex,
    time::Instant,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PerformanceMode {
    AutoAdaptive,
    UltraLowLatency,
    Balanced,
    HighQuality,
    LowBandwidth,
    AiWorkloadPriority,
}

impl PerformanceMode {
    pub fn label_vi(&self) -> &'static str {
        match self {
            Self::AutoAdaptive => "Tự động thích ứng (Auto Adaptive)",
            Self::UltraLowLatency => "Độ trễ siêu thấp (Ultra Low Latency)",
            Self::Balanced => "Cân bằng (Balanced)",
            Self::HighQuality => "Chất lượng cao 2K/4K (High Quality)",
            Self::LowBandwidth => "Tiết kiệm băng thông (Low Bandwidth)",
            Self::AiWorkloadPriority => "Ưu tiên tác vụ AI / ComfyUI (AI Workload Priority)",
        }
    }

    pub fn from_key(s: &str) -> Self {
        match s.trim().to_ascii_uppercase().as_str() {
            "ULTRA_LOW_LATENCY" | "ULTRALOWLATENCY" => Self::UltraLowLatency,
            "BALANCED" => Self::Balanced,
            "HIGH_QUALITY" | "HIGHQUALITY" => Self::HighQuality,
            "LOW_BANDWIDTH" | "LOWBANDWIDTH" => Self::LowBandwidth,
            "AI_WORKLOAD_PRIORITY" | "AIWORKLOADPRIORITY" => Self::AiWorkloadPriority,
            _ => Self::AutoAdaptive,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StreamParameters {
    pub mode: PerformanceMode,
    pub target_fps: u32,
    pub idle_fps: u32,
    pub min_bitrate_kbps: u32,
    pub max_bitrate_kbps: u32,
    pub resolution_scale_pct: u32,
    pub preferred_codec: String,
    pub encoder_preference: String,
    pub prioritize_input_latency: bool,
    pub static_frame_decimation: bool,
    pub file_transfer_bw_cap_kbps: u32,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkRuntimeSample {
    pub session_connected: bool,
    pub rtt_ms: u32,
    pub packet_loss_pct: f32,
    pub is_direct_p2p: bool,
    pub host_cpu_pct: f32,
    pub host_gpu_pct: f32,
    pub host_vram_pct: f32,
    pub ai_workload_active: bool,
    pub comfyui_rendering: bool,
    pub mini_control_minimized: bool,
    pub mini_control_idle: bool,
}

impl Default for NetworkRuntimeSample {
    fn default() -> Self {
        Self {
            session_connected: false,
            rtt_ms: 0,
            packet_loss_pct: 0.0,
            is_direct_p2p: false,
            host_cpu_pct: 0.0,
            host_gpu_pct: 0.0,
            host_vram_pct: 0.0,
            ai_workload_active: false,
            comfyui_rendering: false,
            mini_control_minimized: false,
            mini_control_idle: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceTelemetry {
    pub session_connected: bool,
    pub active_mode: PerformanceMode,
    pub fps: u32,
    pub ping_rtt_ms: u32,
    pub bitrate_kbps: u32,
    pub packet_loss_pct: Option<f32>,
    pub codec: String,
    pub encoder: String,
    pub cpu_usage_pct: f32,
    pub gpu_usage_pct: f32,
    pub connection_route: String,
    pub network_quality_score: u8,
    pub network_quality_label: String,
    pub applied_params: StreamParameters,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkReport {
    pub measured_at_utc: String,
    pub benchmark_scope: String,
    pub environment_type: String,
    pub cpu_model: String,
    pub logical_cores: usize,
    pub target_reference_profile: String,
    pub frame_1080p_dirty_scan_ms: f64,
    pub loopback_tcp_rtt_ms: f64,
    pub hmac_event_sign_us: f64,
    pub estimated_1080p_scan_fps_headroom: f64,
    pub notes: String,
}

pub struct PerformanceEngine {
    mode: Mutex<PerformanceMode>,
    last_sample: Mutex<NetworkRuntimeSample>,
}

impl PerformanceEngine {
    pub fn new() -> Self {
        Self {
            mode: Mutex::new(PerformanceMode::AutoAdaptive),
            last_sample: Mutex::new(NetworkRuntimeSample::default()),
        }
    }

    pub fn get_mode(&self) -> PerformanceMode {
        *self.mode.lock().unwrap()
    }

    pub fn set_mode(&self, mode: PerformanceMode) -> StreamParameters {
        {
            let mut guard = self.mode.lock().unwrap();
            *guard = mode;
        }
        let sample = self.last_sample.lock().unwrap().clone();
        let params = Self::compute_parameters(mode, &sample);
        // Apply codec and image-quality preferences directly into upstream RustDesk LocalConfig
        let codec_opt = match params.preferred_codec.as_str() {
            "H265" => "h265",
            "H264" => "h264",
            _ => "auto",
        };
        hbb_common::config::LocalConfig::set_option(
            "codec-preference".to_owned(),
            codec_opt.to_owned(),
        );
        hbb_common::config::LocalConfig::set_option(
            "custom-fps".to_owned(),
            params.target_fps.to_string(),
        );
        params
    }

    pub fn update_runtime_sample(&self, sample: NetworkRuntimeSample) -> PerformanceTelemetry {
        let mode = *self.mode.lock().unwrap();
        {
            let mut guard = self.last_sample.lock().unwrap();
            *guard = sample.clone();
        }
        Self::build_telemetry(mode, &sample)
    }

    pub fn current_telemetry(&self) -> PerformanceTelemetry {
        let mode = *self.mode.lock().unwrap();
        let sample = self.last_sample.lock().unwrap().clone();
        Self::build_telemetry(mode, &sample)
    }

    pub fn compute_parameters(
        mode: PerformanceMode,
        sample: &NetworkRuntimeSample,
    ) -> StreamParameters {
        let mut params = match mode {
            PerformanceMode::UltraLowLatency => StreamParameters {
                mode,
                target_fps: 60,
                idle_fps: 10,
                min_bitrate_kbps: 2_500,
                max_bitrate_kbps: 12_000,
                resolution_scale_pct: 100,
                preferred_codec: "H264".to_owned(),
                encoder_preference: "NVENC_LOW_LATENCY_P1".to_owned(),
                prioritize_input_latency: true,
                static_frame_decimation: true,
                file_transfer_bw_cap_kbps: 40_000,
                rationale: "Low-latency H.264 zero-B-frame NVENC preset prioritizing mouse/keyboard responsiveness (<20ms LAN target).".to_owned(),
            },
            PerformanceMode::Balanced => StreamParameters {
                mode,
                target_fps: 60,
                idle_fps: 5,
                min_bitrate_kbps: 1_500,
                max_bitrate_kbps: 8_000,
                resolution_scale_pct: 100,
                preferred_codec: "H265".to_owned(),
                encoder_preference: "NVENC_BALANCED_P3".to_owned(),
                prioritize_input_latency: true,
                static_frame_decimation: true,
                file_transfer_bw_cap_kbps: 80_000,
                rationale: "Balanced 1080p60 HEVC hardware encode for daily remote desktop and AI coding workflows.".to_owned(),
            },
            PerformanceMode::HighQuality => StreamParameters {
                mode,
                target_fps: 60,
                idle_fps: 10,
                min_bitrate_kbps: 6_000,
                max_bitrate_kbps: 28_000,
                resolution_scale_pct: 100,
                preferred_codec: "H265".to_owned(),
                encoder_preference: "NVENC_HQ_P4".to_owned(),
                prioritize_input_latency: false,
                static_frame_decimation: true,
                file_transfer_bw_cap_kbps: 120_000,
                rationale: "High-bitrate 2K/4K HEVC clarity for inspecting ComfyUI video previews and dense IDE text.".to_owned(),
            },
            PerformanceMode::LowBandwidth => StreamParameters {
                mode,
                target_fps: 24,
                idle_fps: 2,
                min_bitrate_kbps: 400,
                max_bitrate_kbps: 1_800,
                resolution_scale_pct: 75,
                preferred_codec: "H265".to_owned(),
                encoder_preference: "NVENC_LOW_BITRATE".to_owned(),
                prioritize_input_latency: true,
                static_frame_decimation: true,
                file_transfer_bw_cap_kbps: 8_000,
                rationale: "Constrained Internet/Relay profile minimizing bandwidth while keeping input responsive.".to_owned(),
            },
            PerformanceMode::AiWorkloadPriority => StreamParameters {
                mode,
                target_fps: 30,
                idle_fps: 2,
                min_bitrate_kbps: 1_000,
                max_bitrate_kbps: 4_500,
                resolution_scale_pct: 100,
                preferred_codec: "H264".to_owned(),
                encoder_preference: "NVENC_MIN_VRAM_OR_CPU_FALLBACK".to_owned(),
                prioritize_input_latency: true,
                static_frame_decimation: true,
                file_transfer_bw_cap_kbps: 25_000,
                rationale: "Protects RTX 3060 12GB VRAM & CUDA cores for ComfyUI, Claude Code, Codex, and Antigravity tasks.".to_owned(),
            },
            PerformanceMode::AutoAdaptive => {
                if sample.comfyui_rendering
                    || (sample.ai_workload_active && (sample.host_gpu_pct > 75.0 || sample.host_vram_pct > 80.0))
                {
                    let mut p = Self::compute_parameters(PerformanceMode::AiWorkloadPriority, sample);
                    p.mode = PerformanceMode::AutoAdaptive;
                    p.rationale = "Auto-Adaptive detected heavy GPU/VRAM AI workload (ComfyUI/Agent active) -> shifted to AI Workload Priority.".to_owned();
                    p
                } else if !sample.is_direct_p2p || sample.rtt_ms > 110 || sample.packet_loss_pct > 2.5 {
                    let mut p = Self::compute_parameters(PerformanceMode::LowBandwidth, sample);
                    p.mode = PerformanceMode::AutoAdaptive;
                    p.rationale = "Auto-Adaptive detected high RTT / packet loss / Relay path -> shifted to Low Bandwidth resilient profile.".to_owned();
                    p
                } else if sample.rtt_ms <= 22 && sample.packet_loss_pct < 0.3 {
                    let mut p = Self::compute_parameters(PerformanceMode::UltraLowLatency, sample);
                    p.mode = PerformanceMode::AutoAdaptive;
                    p.rationale = "Auto-Adaptive detected fast Direct P2P LAN/low-RTT path -> enabled 60 FPS Ultra Low Latency.".to_owned();
                    p
                } else {
                    let mut p = Self::compute_parameters(PerformanceMode::Balanced, sample);
                    p.mode = PerformanceMode::AutoAdaptive;
                    p
                }
            }
        };

        if sample.mini_control_minimized {
            params.target_fps = params.target_fps.min(5);
            params.idle_fps = 1;
            params.max_bitrate_kbps = params.max_bitrate_kbps.min(800);
            params.resolution_scale_pct = params.resolution_scale_pct.min(50);
            params.rationale.push_str(" [Mini Control minimized: throttled to <=5 FPS].");
        } else if sample.mini_control_idle {
            params.target_fps = params.target_fps.min(12);
            params.idle_fps = 2;
            params.max_bitrate_kbps = params.max_bitrate_kbps.min(1_500);
            params.rationale.push_str(" [Mini Control idle: throttled to <=12 FPS].");
        }

        params
    }

    pub fn compute_network_quality_score(rtt_ms: u32, loss_pct: f32, is_direct: bool) -> (u8, &'static str) {
        let rtt_penalty = (rtt_ms.saturating_sub(10) as f32 * 0.45).min(55.0);
        let loss_penalty = (loss_pct * 12.0).min(40.0);
        let relay_penalty = if is_direct { 0.0 } else { 8.0 };
        let raw = (100.0 - rtt_penalty - loss_penalty - relay_penalty).clamp(5.0, 100.0) as u8;
        let label = match raw {
            85..=100 => "Excellent",
            65..=84 => "Good",
            40..=64 => "Fair",
            _ => "Degraded",
        };
        (raw, label)
    }

    fn build_telemetry(mode: PerformanceMode, sample: &NetworkRuntimeSample) -> PerformanceTelemetry {
        let params = Self::compute_parameters(mode, sample);
        if !sample.session_connected {
            return PerformanceTelemetry {
                session_connected: false,
                active_mode: mode,
                fps: 0,
                ping_rtt_ms: 0,
                bitrate_kbps: 0,
                packet_loss_pct: None,
                codec: params.preferred_codec.clone(),
                encoder: params.encoder_preference.clone(),
                cpu_usage_pct: sample.host_cpu_pct,
                gpu_usage_pct: sample.host_gpu_pct,
                connection_route: "DISCONNECTED (No Active Remote Session)".to_owned(),
                network_quality_score: 0,
                network_quality_label: "Idle (No Session)".to_owned(),
                applied_params: params,
            };
        }
        let (score, label) = Self::compute_network_quality_score(
            sample.rtt_ms,
            sample.packet_loss_pct,
            sample.is_direct_p2p,
        );
        let effective_fps = if sample.mini_control_minimized {
            params.idle_fps
        } else {
            params.target_fps
        };
        let effective_bitrate = ((params.min_bitrate_kbps + params.max_bitrate_kbps) / 2)
            .min(params.max_bitrate_kbps);
        PerformanceTelemetry {
            session_connected: true,
            active_mode: mode,
            fps: effective_fps,
            ping_rtt_ms: sample.rtt_ms,
            bitrate_kbps: effective_bitrate,
            packet_loss_pct: Some(sample.packet_loss_pct),
            codec: params.preferred_codec.clone(),
            encoder: params.encoder_preference.clone(),
            cpu_usage_pct: sample.host_cpu_pct,
            gpu_usage_pct: sample.host_gpu_pct,
            connection_route: if sample.is_direct_p2p {
                "Direct P2P".to_owned()
            } else {
                "Relay Fallback".to_owned()
            },
            network_quality_score: score,
            network_quality_label: label.to_owned(),
            applied_params: params,
        }
    }

    pub fn run_pipeline_benchmark() -> Result<BenchmarkReport, String> {
        let frame_bytes = 1920usize * 1080usize * 4usize;
        let frame_a = vec![0x2Au8; frame_bytes];
        let mut frame_b = frame_a.clone();
        frame_b[frame_bytes / 2] = 0xFF;

        let t0 = Instant::now();
        let mut dirty_blocks = 0usize;
        for (ca, cb) in frame_a.chunks_exact(4096).zip(frame_b.chunks_exact(4096)) {
            if ca != cb {
                dirty_blocks += 1;
            }
        }
        let scan_ms = t0.elapsed().as_secs_f64() * 1000.0;
        if dirty_blocks == 0 {
            return Err("unexpected zero dirty blocks in benchmark".to_owned());
        }

        let listener = TcpListener::bind("127.0.0.1:0")
            .map_err(|e| format!("failed binding loopback socket: {e}"))?;
        let addr = listener
            .local_addr()
            .map_err(|e| format!("failed reading local_addr: {e}"))?;
        let server_handle = std::thread::spawn(move || -> Result<(), String> {
            let (mut conn, _) = listener
                .accept()
                .map_err(|e| format!("accept failed: {e}"))?;
            conn.set_nodelay(true).ok();
            let mut buf = [0u8; 64];
            for _ in 0..20 {
                conn.read_exact(&mut buf)
                    .map_err(|e| format!("server read failed: {e}"))?;
                conn.write_all(&buf)
                    .map_err(|e| format!("server write failed: {e}"))?;
            }
            Ok(())
        });

        let mut client = TcpStream::connect(addr)
            .map_err(|e| format!("loopback connect failed: {e}"))?;
        client.set_nodelay(true).ok();
        let ping_payload = [0x5Au8; 64];
        let mut pong_buf = [0u8; 64];
        let rtt_start = Instant::now();
        for _ in 0..20 {
            client
                .write_all(&ping_payload)
                .map_err(|e| format!("client write failed: {e}"))?;
            client
                .read_exact(&mut pong_buf)
                .map_err(|e| format!("client read failed: {e}"))?;
        }
        let avg_rtt_ms = (rtt_start.elapsed().as_secs_f64() * 1000.0) / 20.0;
        server_handle
            .join()
            .map_err(|_| "loopback server thread panicked".to_owned())??;

        let sign_start = Instant::now();
        for i in 0..200u32 {
            let _ = super::crypto_util::hmac_sha256(b"bench-key", &i.to_le_bytes());
        }
        let sign_us = (sign_start.elapsed().as_secs_f64() * 1_000_000.0) / 200.0;

        let headroom = if scan_ms > 0.001 {
            1000.0 / scan_ms
        } else {
            9999.0
        };

        Ok(BenchmarkReport {
            measured_at_utc: chrono::Utc::now().to_rfc3339(),
            benchmark_scope: "LOCAL_PIPELINE_MICROBENCHMARK_ONLY (NOT End-to-End Remote Desktop Network/NVENC Latency)".to_owned(),
            environment_type: format!("{} ({})", std::env::consts::OS, std::env::consts::ARCH),
            cpu_model: "Measured Host CPU".to_owned(),
            logical_cores: num_cpus::get(),
            target_reference_profile: "Intel Core i5-12400F + NVIDIA RTX 3060 12GB + 16GB RAM + Windows 11 Pro".to_owned(),
            frame_1080p_dirty_scan_ms: (scan_ms * 1000.0).round() / 1000.0,
            loopback_tcp_rtt_ms: (avg_rtt_ms * 1000.0).round() / 1000.0,
            hmac_event_sign_us: (sign_us * 100.0).round() / 100.0,
            estimated_1080p_scan_fps_headroom: (headroom * 10.0).round() / 1000.0 * 100.0,
            notes: "Measures local CPU dirty-tile memory scan, HMAC signing, and 127.0.0.1 socket overhead ONLY. End-to-end Remote Desktop LAN/WAN + RTX 3060 NVENC latency requires 2-PC Windows measurement.".to_owned(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_adaptive_protects_comfyui_and_throttles_mini_control() {
        let mut sample = NetworkRuntimeSample::default();
        sample.comfyui_rendering = true;
        sample.host_gpu_pct = 92.0;
        sample.host_vram_pct = 88.0;

        let p = PerformanceEngine::compute_parameters(PerformanceMode::AutoAdaptive, &sample);
        assert_eq!(p.target_fps, 30);
        assert!(p.max_bitrate_kbps <= 4_500);

        sample.mini_control_minimized = true;
        let p_min = PerformanceEngine::compute_parameters(PerformanceMode::AutoAdaptive, &sample);
        assert!(p_min.target_fps <= 5);
        assert!(p_min.max_bitrate_kbps <= 800);
    }

    #[test]
    fn real_pipeline_benchmark_executes() {
        let report = PerformanceEngine::run_pipeline_benchmark().unwrap();
        assert!(report.frame_1080p_dirty_scan_ms >= 0.0);
        assert!(report.loopback_tcp_rtt_ms >= 0.0);
        assert!(report.hmac_event_sign_us > 0.0);
    }
}

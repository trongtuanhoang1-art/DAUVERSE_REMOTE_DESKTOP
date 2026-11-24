use super::crypto_util::redact_sensitive;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    net::{TcpStream, ToSocketAddrs},
    sync::Mutex,
    time::{Duration, Instant},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionHistoryRecord {
    pub session_id: String,
    pub peer_id: String,
    pub peer_name: String,
    pub route: String,
    pub started_at_utc: String,
    pub ended_at_utc: Option<String>,
    pub duration_secs: u64,
    pub recorded: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingState {
    pub active: bool,
    pub visible_banner_indicator: bool,
    pub started_by_explicit_opt_in: bool,
    pub output_file: Option<String>,
    pub started_at_utc: Option<String>,
}

impl Default for RecordingState {
    fn default() -> Self {
        Self {
            active: false,
            visible_banner_indicator: false,
            started_by_explicit_opt_in: false,
            output_file: None,
            started_at_utc: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkDiagnosticProbe {
    pub target: String,
    pub reachable: bool,
    pub connect_rtt_ms: Option<f64>,
    pub route_recommendation: String,
    pub error: Option<String>,
}

pub struct SessionToolsManager {
    recording: Mutex<RecordingState>,
    history: Mutex<Vec<SessionHistoryRecord>>,
    chat_messages: Mutex<Vec<serde_json::Value>>,
    shortcuts: Mutex<HashMap<String, String>>,
}

impl SessionToolsManager {
    pub fn new() -> Self {
        let mut shortcuts = HashMap::new();
        shortcuts.insert("toggle_fullscreen".to_owned(), "Ctrl+Alt+Enter".to_owned());
        shortcuts.insert("toggle_mini_control".to_owned(), "Ctrl+Alt+M".to_owned());
        shortcuts.insert("open_file_transfer".to_owned(), "Ctrl+Alt+F".to_owned());
        shortcuts.insert("open_ai_live_status".to_owned(), "Ctrl+Alt+A".to_owned());
        shortcuts.insert("take_screenshot".to_owned(), "Ctrl+Alt+S".to_owned());
        shortcuts.insert("switch_monitor".to_owned(), "Ctrl+Alt+Tab".to_owned());
        Self {
            recording: Mutex::new(RecordingState::default()),
            history: Mutex::new(Vec::new()),
            chat_messages: Mutex::new(Vec::new()),
            shortcuts: Mutex::new(shortcuts),
        }
    }

    pub fn start_recording(
        &self,
        has_recording_permission: bool,
        explicit_user_opt_in: bool,
        output_file: &str,
    ) -> Result<RecordingState, String> {
        if !has_recording_permission {
            return Err("SECURITY_DENY_RECORDING_PERMISSION_DISABLED".to_owned());
        }
        if !explicit_user_opt_in {
            return Err("SECURITY_DENY_SILENT_RECORDING_FORBIDDEN".to_owned());
        }
        let mut g = self.recording.lock().unwrap();
        g.active = true;
        g.visible_banner_indicator = true;
        g.started_by_explicit_opt_in = true;
        g.output_file = Some(output_file.to_owned());
        g.started_at_utc = Some(chrono::Utc::now().to_rfc3339());
        Ok(g.clone())
    }

    pub fn stop_recording(&self) -> RecordingState {
        let mut g = self.recording.lock().unwrap();
        *g = RecordingState::default();
        g.clone()
    }

    pub fn recording_state(&self) -> RecordingState {
        let g = self.recording.lock().unwrap();
        let mut out = g.clone();
        if out.active {
            out.visible_banner_indicator = true;
        }
        out
    }

    pub fn record_session_history(&self, rec: SessionHistoryRecord) {
        let mut g = self.history.lock().unwrap();
        if g.len() >= 500 {
            g.remove(0);
        }
        g.push(rec);
    }

    pub fn session_history(&self) -> Vec<SessionHistoryRecord> {
        let mut list = self.history.lock().unwrap().clone();
        list.reverse();
        list
    }

    pub fn post_chat_message(&self, sender: &str, text: &str) -> serde_json::Value {
        let msg = serde_json::json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "sender": sender,
            "text": redact_sensitive(text),
            "timestamp_utc": chrono::Utc::now().to_rfc3339(),
        });
        let mut g = self.chat_messages.lock().unwrap();
        if g.len() >= 200 {
            g.remove(0);
        }
        g.push(msg.clone());
        msg
    }

    pub fn shortcuts(&self) -> HashMap<String, String> {
        self.shortcuts.lock().unwrap().clone()
    }

    pub fn update_shortcut(&self, action: &str, combo: &str) -> Result<(), String> {
        if action.trim().is_empty() || combo.trim().is_empty() {
            return Err("shortcut action and combo must be non-empty".to_owned());
        }
        self.shortcuts
            .lock()
            .unwrap()
            .insert(action.to_owned(), combo.to_owned());
        Ok(())
    }

    pub fn probe_endpoint(host_port: &str, timeout_ms: u64) -> NetworkDiagnosticProbe {
        let Ok(mut addrs) = host_port.to_socket_addrs() else {
            return NetworkDiagnosticProbe {
                target: host_port.to_owned(),
                reachable: false,
                connect_rtt_ms: None,
                route_recommendation: "Relay Fallback / Check DNS or Host".to_owned(),
                error: Some("DNS_OR_ADDRESS_RESOLUTION_FAILED".to_owned()),
            };
        };
        let Some(addr) = addrs.next() else {
            return NetworkDiagnosticProbe {
                target: host_port.to_owned(),
                reachable: false,
                connect_rtt_ms: None,
                route_recommendation: "Relay Fallback".to_owned(),
                error: Some("NO_SOCKET_ADDRS".to_owned()),
            };
        };
        let t0 = Instant::now();
        match TcpStream::connect_timeout(&addr, Duration::from_millis(timeout_ms.clamp(50, 10_000)))
        {
            Ok(_) => {
                let rtt = (t0.elapsed().as_secs_f64() * 1000.0 * 100.0).round() / 100.0;
                let rec = if rtt < 25.0 {
                    "Direct P2P LAN / Ultra Low Latency".to_owned()
                } else if rtt < 90.0 {
                    "Direct P2P Internet / Balanced".to_owned()
                } else {
                    "Relay or Low Bandwidth Adaptive".to_owned()
                };
                NetworkDiagnosticProbe {
                    target: host_port.to_owned(),
                    reachable: true,
                    connect_rtt_ms: Some(rtt),
                    route_recommendation: rec,
                    error: None,
                }
            }
            Err(e) => NetworkDiagnosticProbe {
                target: host_port.to_owned(),
                reachable: false,
                connect_rtt_ms: None,
                route_recommendation: "Check Firewall / Use Relay Server".to_owned(),
                error: Some(e.to_string()),
            },
        }
    }

    pub fn build_redacted_diagnostic_report(&self, extra_notes: &str) -> String {
        let rec = self.recording_state();
        let hist_count = self.history.lock().unwrap().len();
        let clean_notes = redact_sensitive(extra_notes);
        serde_json::to_string_pretty(&serde_json::json!({
            "product": "DAUVERSE REMOTE DESKTOP V1.0",
            "generated_at_utc": chrono::Utc::now().to_rfc3339(),
            "os": std::env::consts::OS,
            "arch": std::env::consts::ARCH,
            "recording_active": rec.active,
            "session_history_count": hist_count,
            "secrets_scrubbed": true,
            "notes": clean_notes,
        }))
        .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_silent_recording_and_redacts_diagnostic_export() {
        let mgr = SessionToolsManager::new();
        assert!(mgr.start_recording(false, true, "out.mp4").is_err());
        assert!(mgr.start_recording(true, false, "out.mp4").is_err());

        let rec = mgr.start_recording(true, true, "session_01.mp4").unwrap();
        assert!(rec.active && rec.visible_banner_indicator);

        let report = mgr.build_redacted_diagnostic_report("debug password=TopSecretValue999 sk-ant-1234567890");
        assert!(!report.contains("TopSecretValue999"));
        assert!(!report.contains("sk-ant-1234567890"));
    }
}

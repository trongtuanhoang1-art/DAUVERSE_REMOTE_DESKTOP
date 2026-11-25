use super::{
    ai_bridge::{AiEvent, AiEventType, AiTaskStatus, EventSeverity},
    crypto_util::{redact_sensitive, sha256_hex, write_atomic_bytes},
};
use serde::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    fs,
    path::PathBuf,
    sync::Mutex,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum NotificationCategory {
    ClaudeCommandCompleted,
    ClaudeTaskCompleted,
    CodexCommandCompleted,
    CodexQaCompleted,
    AntigravityCommandCompleted,
    AntigravityTaskCompleted,
    AiWaitingBossApproval,
    AiWaitingUserInput,
    AiError,
    BuildSucceeded,
    BuildFailed,
    QaPass,
    QaFail,
    ComfyUiRenderCompleted,
    FileTransferCompleted,
    DeviceOnline,
    DeviceOffline,
    NetworkLost,
    GpuOverheat,
    RamThresholdExceeded,
    VramThresholdExceeded,
    DiskSpaceLow,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum NotificationActionKind {
    OpenRemote,
    ViewStatus,
    ViewReport,
    MarkRead,
    CloseToast,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationItem {
    pub notification_id: String,
    pub category: NotificationCategory,
    pub title: String,
    pub ai_source: String,
    pub project_name: String,
    pub device_id: String,
    pub status: AiTaskStatus,
    pub severity: EventSeverity,
    pub body: String,
    pub verified_evidence_line: Option<String>,
    pub artifact_reference: Option<String>,
    pub created_at_utc: String,
    pub is_read: bool,
    pub priority_alert: bool,
    pub auto_hide_seconds: u8,
    pub steal_focus: bool,
    pub severity_color_hex: String,
    pub available_actions: Vec<NotificationActionKind>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationPreferences {
    pub enabled: bool,
    pub quiet_mode: bool,
    pub do_not_disturb: bool,
    pub play_sound: bool,
    pub auto_hide_seconds: u8,
    pub dedup_window_ms: i64,
    pub max_history_items: usize,
    pub max_offline_buffered_events: usize,
    pub hide_sensitive_by_default: bool,
}

impl Default for NotificationPreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            quiet_mode: false,
            do_not_disturb: false,
            play_sound: false,
            auto_hide_seconds: 6,
            dedup_window_ms: 10_000,
            max_history_items: 500,
            max_offline_buffered_events: 250,
            hide_sensitive_by_default: true,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct NotificationFilter {
    pub ai_source: Option<String>,
    pub project_name: Option<String>,
    pub status: Option<AiTaskStatus>,
    pub unread_only: bool,
}

#[derive(Debug, Clone)]
struct DedupRecord {
    fingerprint: String,
    timestamp_ms: i64,
}

pub struct NotificationCenter {
    prefs: Mutex<NotificationPreferences>,
    history: Mutex<VecDeque<NotificationItem>>,
    active_toasts: Mutex<VecDeque<NotificationItem>>,
    offline_buffer: Mutex<VecDeque<NotificationItem>>,
    dedup_cache: Mutex<VecDeque<DedupRecord>>,
    is_online: Mutex<bool>,
    offline_journal_path: Mutex<Option<PathBuf>>,
}

impl NotificationCenter {
    pub fn new(offline_journal_path: Option<PathBuf>) -> Self {
        let center = Self {
            prefs: Mutex::new(NotificationPreferences::default()),
            history: Mutex::new(VecDeque::with_capacity(256)),
            active_toasts: Mutex::new(VecDeque::with_capacity(16)),
            offline_buffer: Mutex::new(VecDeque::with_capacity(128)),
            dedup_cache: Mutex::new(VecDeque::with_capacity(128)),
            is_online: Mutex::new(true),
            offline_journal_path: Mutex::new(offline_journal_path),
        };
        center.load_persisted_offline_journal();
        center
    }

    pub fn preferences(&self) -> NotificationPreferences {
        self.prefs.lock().unwrap().clone()
    }

    pub fn update_preferences(&self, mut next: NotificationPreferences) -> NotificationPreferences {
        next.auto_hide_seconds = next.auto_hide_seconds.clamp(5, 8);
        next.max_offline_buffered_events = next.max_offline_buffered_events.clamp(10, 1_000);
        next.max_history_items = next.max_history_items.clamp(50, 2_000);
        let mut g = self.prefs.lock().unwrap();
        *g = next.clone();
        next
    }

    pub fn set_network_online(&self, online: bool) -> usize {
        {
            let mut g = self.is_online.lock().unwrap();
            *g = online;
        }
        if online {
            self.flush_offline_buffer()
        } else {
            0
        }
    }

    pub fn publish_from_ai_event(
        &self,
        ev: &AiEvent,
        now_ms: i64,
    ) -> Option<NotificationItem> {
        let category = Self::classify_ai_event(ev);
        let title = Self::build_vietnamese_title(category, &ev.source);
        let priority = matches!(
            ev.severity,
            EventSeverity::High | EventSeverity::Critical
        ) || ev.status == AiTaskStatus::WaitingApproval;

        let verified_line = if ev.provenance.evidence_verified {
            ev.provenance.evidence_badge.clone()
        } else {
            None
        };

        self.publish_raw(
            category,
            &title,
            &ev.source,
            &ev.project_id,
            &ev.device_id,
            ev.status,
            ev.severity,
            &ev.summary,
            verified_line,
            ev.artifact_reference.clone(),
            priority,
            now_ms,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn publish_raw(
        &self,
        category: NotificationCategory,
        title: &str,
        ai_source: &str,
        project_name: &str,
        device_id: &str,
        status: AiTaskStatus,
        severity: EventSeverity,
        raw_body: &str,
        verified_evidence_line: Option<String>,
        artifact_reference: Option<String>,
        priority_alert: bool,
        now_ms: i64,
    ) -> Option<NotificationItem> {
        let prefs = self.prefs.lock().unwrap().clone();
        if !prefs.enabled {
            return None;
        }

        let clean_body = if prefs.hide_sensitive_by_default {
            redact_sensitive(raw_body)
        } else {
            raw_body.to_owned()
        };

        let fp_input = format!(
            "{:?}|{}|{}|{}|{:?}|{}",
            category, ai_source, project_name, device_id, status, clean_body
        );
        let fp = sha256_hex(fp_input.as_bytes());
        {
            let mut dedup = self.dedup_cache.lock().unwrap();
            while let Some(front) = dedup.front() {
                if now_ms - front.timestamp_ms > prefs.dedup_window_ms {
                    dedup.pop_front();
                } else {
                    break;
                }
            }
            if dedup.iter().any(|r| r.fingerprint == fp) {
                return None;
            }
            if dedup.len() >= 256 {
                dedup.pop_front();
            }
            dedup.push_back(DedupRecord {
                fingerprint: fp,
                timestamp_ms: now_ms,
            });
        }

        let color_hex = match severity {
            EventSeverity::Success => "#10B981",
            EventSeverity::Info => "#06B6D4",
            EventSeverity::Warning => "#F59E0B",
            EventSeverity::High => "#F97316",
            EventSeverity::Critical => "#EF4444",
        }
        .to_owned();

        let item = NotificationItem {
            notification_id: uuid::Uuid::new_v4().to_string(),
            category,
            title: title.to_owned(),
            ai_source: ai_source.to_owned(),
            project_name: project_name.to_owned(),
            device_id: device_id.to_owned(),
            status,
            severity,
            body: clean_body,
            verified_evidence_line,
            artifact_reference,
            created_at_utc: chrono::Utc::now().to_rfc3339(),
            is_read: false,
            priority_alert,
            auto_hide_seconds: prefs.auto_hide_seconds.clamp(5, 8),
            steal_focus: false,
            severity_color_hex: color_hex,
            available_actions: vec![
                NotificationActionKind::OpenRemote,
                NotificationActionKind::ViewStatus,
                NotificationActionKind::ViewReport,
                NotificationActionKind::MarkRead,
                NotificationActionKind::CloseToast,
            ],
        };

        let online = *self.is_online.lock().unwrap();
        if !online {
            let mut buf = self.offline_buffer.lock().unwrap();
            if buf.len() >= prefs.max_offline_buffered_events {
                buf.pop_front();
            }
            buf.push_back(item.clone());
            drop(buf);
            self.persist_offline_journal();
            return Some(item);
        }

        self.deliver_item(item.clone(), &prefs);
        Some(item)
    }

    fn deliver_item(&self, item: NotificationItem, prefs: &NotificationPreferences) {
        {
            let mut hist = self.history.lock().unwrap();
            if hist.len() >= prefs.max_history_items {
                hist.pop_front();
            }
            hist.push_back(item.clone());
        }

        let show_toast = if prefs.do_not_disturb {
            false
        } else if prefs.quiet_mode {
            item.priority_alert
        } else {
            true
        };

        if show_toast {
            let mut toasts = self.active_toasts.lock().unwrap();
            if toasts.len() >= 8 {
                toasts.pop_front();
            }
            toasts.push_back(item);
        }
        self.persist_offline_journal();
    }

    fn flush_offline_buffer(&self) -> usize {
        let prefs = self.prefs.lock().unwrap().clone();
        let drained: Vec<NotificationItem> = {
            let mut buf = self.offline_buffer.lock().unwrap();
            buf.drain(..).collect()
        };
        let count = drained.len();
        for item in drained {
            self.deliver_item(item, &prefs);
        }
        self.persist_offline_journal();
        count
    }

    pub fn unread_count(&self) -> usize {
        self.history
            .lock()
            .unwrap()
            .iter()
            .filter(|i| !i.is_read)
            .count()
    }

    pub fn mark_read(&self, notification_id: &str) -> bool {
        let mut found = false;
        for item in self.history.lock().unwrap().iter_mut() {
            if item.notification_id == notification_id {
                item.is_read = true;
                found = true;
            }
        }
        self.active_toasts
            .lock()
            .unwrap()
            .retain(|t| t.notification_id != notification_id);
        if found {
            self.persist_offline_journal();
        }
        found
    }

    pub fn mark_all_read(&self) {
        for item in self.history.lock().unwrap().iter_mut() {
            item.is_read = true;
        }
        self.active_toasts.lock().unwrap().clear();
        self.persist_offline_journal();
    }

    pub fn dismiss_toast(&self, notification_id: &str) {
        self.active_toasts
            .lock()
            .unwrap()
            .retain(|t| t.notification_id != notification_id);
    }

    pub fn active_toasts(&self) -> Vec<NotificationItem> {
        self.active_toasts.lock().unwrap().iter().cloned().collect()
    }

    pub fn query_history(&self, filter: &NotificationFilter) -> Vec<NotificationItem> {
        let hist = self.history.lock().unwrap();
        let mut out: Vec<NotificationItem> = hist
            .iter()
            .filter(|item| {
                if filter.unread_only && item.is_read {
                    return false;
                }
                if let Some(src) = &filter.ai_source {
                    if !src.is_empty() && !item.ai_source.eq_ignore_ascii_case(src) {
                        return false;
                    }
                }
                if let Some(proj) = &filter.project_name {
                    if !proj.is_empty() && !item.project_name.eq_ignore_ascii_case(proj) {
                        return false;
                    }
                }
                if let Some(st) = filter.status {
                    if item.status != st {
                        return false;
                    }
                }
                true
            })
            .cloned()
            .collect();
        out.reverse();
        out
    }

    pub fn attempt_ai_approval_via_notification(&self, _notification_id: &str) -> Result<(), String> {
        Err("SECURITY_POLICY_VIOLATION: Approving AI actions directly from notifications is strictly prohibited by DAUVERSE V1 security policy.".to_owned())
    }

    fn classify_ai_event(ev: &AiEvent) -> NotificationCategory {
        let src_lower = ev.source.to_ascii_lowercase();
        match ev.event_type {
            AiEventType::ApprovalRequired => NotificationCategory::AiWaitingBossApproval,
            AiEventType::WaitingUserInput => NotificationCategory::AiWaitingUserInput,
            AiEventType::BuildSucceeded => NotificationCategory::BuildSucceeded,
            AiEventType::BuildFailed => NotificationCategory::BuildFailed,
            AiEventType::QaPassed => {
                if src_lower.contains("codex") {
                    NotificationCategory::CodexQaCompleted
                } else {
                    NotificationCategory::QaPass
                }
            }
            AiEventType::QaFailed => NotificationCategory::QaFail,
            AiEventType::RenderCompleted => NotificationCategory::ComfyUiRenderCompleted,
            AiEventType::Error => NotificationCategory::AiError,
            AiEventType::CommandCompleted => {
                if src_lower.contains("claude") {
                    NotificationCategory::ClaudeCommandCompleted
                } else if src_lower.contains("codex") {
                    NotificationCategory::CodexCommandCompleted
                } else {
                    NotificationCategory::AntigravityCommandCompleted
                }
            }
            AiEventType::TaskCompleted => {
                if src_lower.contains("claude") {
                    NotificationCategory::ClaudeTaskCompleted
                } else if src_lower.contains("codex") {
                    NotificationCategory::CodexQaCompleted
                } else if src_lower.contains("comfy") {
                    NotificationCategory::ComfyUiRenderCompleted
                } else {
                    NotificationCategory::AntigravityTaskCompleted
                }
            }
            _ => {
                if ev.status == AiTaskStatus::WaitingApproval {
                    NotificationCategory::AiWaitingBossApproval
                } else if ev.status == AiTaskStatus::Failed {
                    NotificationCategory::AiError
                } else {
                    NotificationCategory::AntigravityCommandCompleted
                }
            }
        }
    }

    fn build_vietnamese_title(cat: NotificationCategory, source: &str) -> String {
        match cat {
            NotificationCategory::ClaudeCommandCompleted => "Claude đã hoàn thành câu lệnh".to_owned(),
            NotificationCategory::ClaudeTaskCompleted => "Claude đã hoàn thành nhiệm vụ".to_owned(),
            NotificationCategory::CodexCommandCompleted => "Codex đã hoàn thành câu lệnh".to_owned(),
            NotificationCategory::CodexQaCompleted => "Codex đã hoàn thành kiểm thử QA".to_owned(),
            NotificationCategory::AntigravityCommandCompleted => {
                format!("{source} đã cập nhật trạng thái")
            }
            NotificationCategory::AntigravityTaskCompleted => {
                "Antigravity đã hoàn thành nhiệm vụ".to_owned()
            }
            NotificationCategory::AiWaitingBossApproval => "AI yêu cầu Boss phê duyệt".to_owned(),
            NotificationCategory::AiWaitingUserInput => "AI đang chờ nhập dữ liệu".to_owned(),
            NotificationCategory::AiError => "Tác vụ AI gặp lỗi".to_owned(),
            NotificationCategory::BuildSucceeded => "Build thành công".to_owned(),
            NotificationCategory::BuildFailed => "Build thất bại".to_owned(),
            NotificationCategory::QaPass => "Kiểm thử QA PASS".to_owned(),
            NotificationCategory::QaFail => "Kiểm thử QA FAIL".to_owned(),
            NotificationCategory::ComfyUiRenderCompleted => "ComfyUI đã render xong".to_owned(),
            NotificationCategory::FileTransferCompleted => "Truyền file hoàn tất".to_owned(),
            NotificationCategory::DeviceOnline => "Máy tính đã Online".to_owned(),
            NotificationCategory::DeviceOffline => "Máy tính đã Offline".to_owned(),
            NotificationCategory::NetworkLost => "Mất kết nối mạng tới máy đích".to_owned(),
            NotificationCategory::GpuOverheat => "Cảnh báo: GPU vượt ngưỡng nhiệt độ".to_owned(),
            NotificationCategory::RamThresholdExceeded => "Cảnh báo: RAM vượt ngưỡng an toàn".to_owned(),
            NotificationCategory::VramThresholdExceeded => "Cảnh báo: VRAM vượt ngưỡng an toàn".to_owned(),
            NotificationCategory::DiskSpaceLow => "Cảnh báo: Dung lượng ổ đĩa thấp".to_owned(),
        }
    }

    fn persist_offline_journal(&self) {
        let Some(path) = self.offline_journal_path.lock().unwrap().clone() else {
            return;
        };
        let state = PersistedNotificationJournal {
            history: self.history.lock().unwrap().iter().cloned().collect(),
            offline_buffer: self.offline_buffer.lock().unwrap().iter().cloned().collect(),
        };
        match serde_json::to_vec(&state) {
            Ok(bytes) => {
                if let Err(e) = write_atomic_bytes(&path, &bytes, true) {
                    hbb_common::log::warn!("DAUVERSE failed persisting notification journal: {}", e);
                }
            }
            Err(e) => {
                hbb_common::log::warn!("DAUVERSE failed serializing notification journal: {}", e);
            }
        }
    }

    fn load_persisted_offline_journal(&self) {
        let Some(path) = self.offline_journal_path.lock().unwrap().clone() else {
            return;
        };
        let Ok(raw) = fs::read_to_string(&path) else {
            return;
        };
        if let Ok(state) = serde_json::from_str::<PersistedNotificationJournal>(&raw) {
            {
                let mut hist = self.history.lock().unwrap();
                for item in state.history {
                    hist.push_back(item);
                }
            }
            {
                let mut buf = self.offline_buffer.lock().unwrap();
                for item in state.offline_buffer {
                    buf.push_back(item);
                }
            }
        } else if let Ok(items) = serde_json::from_str::<Vec<NotificationItem>>(&raw) {
            let mut buf = self.offline_buffer.lock().unwrap();
            for item in items {
                buf.push_back(item);
            }
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct PersistedNotificationJournal {
    #[serde(default)]
    history: Vec<NotificationItem>,
    #[serde(default)]
    offline_buffer: Vec<NotificationItem>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dauverse::ai_bridge::{EventProvenance, SourceSupportStatus};

    #[test]
    fn dedup_offline_replay_redaction_and_no_auto_approve() {
        let journal = std::env::temp_dir().join(format!("dv_notif_{}.json", uuid::Uuid::new_v4()));
        let center = NotificationCenter::new(Some(journal.clone()));

        let ev = AiEvent {
            event_id: "e1".to_owned(),
            timestamp: "2026-11-24T16:26:00Z".to_owned(),
            source: "Antigravity".to_owned(),
            device_id: "HOME-PC".to_owned(),
            project_id: "DAUVERSE FT004".to_owned(),
            task_id: "FT004".to_owned(),
            task_name: "FT004".to_owned(),
            event_type: AiEventType::TaskCompleted,
            status: AiTaskStatus::Completed,
            severity: EventSeverity::Success,
            progress: Some(100.0),
            summary: "Finished with token sk-ant-secret987654321".to_owned(),
            artifact_reference: None,
            confidence: 1.0,
            provenance: EventProvenance {
                adapter_type: SourceSupportStatus::OfficialHook,
                evidence_verified: true,
                exit_code: Some(0),
                evidence_badge: Some("128/128 tests PASS".to_owned()),
            },
        };

        center.set_network_online(false);
        let n1 = center.publish_from_ai_event(&ev, 10_000).unwrap();
        assert!(!n1.steal_focus);
        assert!((5..=8).contains(&n1.auto_hide_seconds));
        assert!(!n1.body.contains("secret987654321"));
        assert_eq!(n1.verified_evidence_line.as_deref(), Some("128/128 tests PASS"));
        assert_eq!(center.unread_count(), 0);

        assert!(center.publish_from_ai_event(&ev, 12_000).is_none());

        let flushed = center.set_network_online(true);
        assert_eq!(flushed, 1);
        assert_eq!(center.unread_count(), 1);
        assert_eq!(center.active_toasts().len(), 1);

        assert!(center
            .attempt_ai_approval_via_notification(&n1.notification_id)
            .is_err());

        fs::remove_file(&journal).ok();
    }
}

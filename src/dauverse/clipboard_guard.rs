use super::crypto_util::sha256_hex;
use serde::{Deserialize, Serialize};
use std::{collections::VecDeque, sync::Mutex};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ClipboardSyncDirection {
    Bidirectional,
    HostToClientOnly,
    ClientToHostOnly,
    Disabled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ClipboardPayloadKind {
    PlainTextUtf8,
    RichTextHtml,
    ImageBytes,
    FileList,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardPolicy {
    pub enabled: bool,
    pub direction: ClipboardSyncDirection,
    pub allow_text_unicode: bool,
    pub allow_rich_html: bool,
    pub allow_images: bool,
    pub allow_files: bool,
    pub max_text_bytes: usize,
    pub max_binary_bytes: usize,
    pub loop_window_ms: u64,
    pub never_log_content: bool,
    pub never_auto_execute: bool,
}

impl Default for ClipboardPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            direction: ClipboardSyncDirection::Bidirectional,
            allow_text_unicode: true,
            allow_rich_html: true,
            allow_images: true,
            allow_files: true,
            max_text_bytes: 8 * 1024 * 1024,
            max_binary_bytes: 64 * 1024 * 1024,
            loop_window_ms: 1_500,
            never_log_content: true,
            never_auto_execute: true,
        }
    }
}

#[derive(Debug, Clone)]
struct SeenDigest {
    digest_hex: String,
    origin_peer: String,
    timestamp_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardCheckDecision {
    pub allowed: bool,
    pub reason: String,
    pub payload_sha256_prefix: String,
    pub byte_len: usize,
    pub auto_execute_blocked: bool,
}

pub struct ClipboardGuard {
    policy: Mutex<ClipboardPolicy>,
    recent_digests: Mutex<VecDeque<SeenDigest>>,
    blocked_loops_count: Mutex<u64>,
    synced_items_count: Mutex<u64>,
}

impl ClipboardGuard {
    pub fn new() -> Self {
        Self {
            policy: Mutex::new(ClipboardPolicy::default()),
            recent_digests: Mutex::new(VecDeque::with_capacity(64)),
            blocked_loops_count: Mutex::new(0),
            synced_items_count: Mutex::new(0),
        }
    }

    pub fn get_policy(&self) -> ClipboardPolicy {
        self.policy.lock().unwrap().clone()
    }

    pub fn update_policy(&self, mut next: ClipboardPolicy) -> ClipboardPolicy {
        next.never_log_content = true;
        next.never_auto_execute = true;
        let mut guard = self.policy.lock().unwrap();
        *guard = next.clone();
        next
    }

    pub fn stats(&self) -> serde_json::Value {
        let policy = self.policy.lock().unwrap().clone();
        let loops = *self.blocked_loops_count.lock().unwrap();
        let synced = *self.synced_items_count.lock().unwrap();
        serde_json::json!({
            "policy": policy,
            "blocked_loops_count": loops,
            "synced_items_count": synced,
        })
    }

    pub fn inspect_and_record(
        &self,
        origin_peer: &str,
        is_incoming_from_host: bool,
        kind: ClipboardPayloadKind,
        payload: &[u8],
        now_ms: u64,
    ) -> ClipboardCheckDecision {
        let policy = self.policy.lock().unwrap().clone();
        let full_hash = sha256_hex(payload);
        let prefix = full_hash.chars().take(12).collect::<String>();

        if !policy.enabled || policy.direction == ClipboardSyncDirection::Disabled {
            return ClipboardCheckDecision {
                allowed: false,
                reason: "CLIPBOARD_SYNC_DISABLED".to_owned(),
                payload_sha256_prefix: prefix,
                byte_len: payload.len(),
                auto_execute_blocked: true,
            };
        }

        match (policy.direction, is_incoming_from_host) {
            (ClipboardSyncDirection::HostToClientOnly, false)
            | (ClipboardSyncDirection::ClientToHostOnly, true) => {
                return ClipboardCheckDecision {
                    allowed: false,
                    reason: "DIRECTION_NOT_PERMITTED_FOR_SESSION".to_owned(),
                    payload_sha256_prefix: prefix,
                    byte_len: payload.len(),
                    auto_execute_blocked: true,
                };
            }
            _ => {}
        }

        match kind {
            ClipboardPayloadKind::PlainTextUtf8 => {
                if !policy.allow_text_unicode {
                    return Self::deny("TEXT_CLIPBOARD_DISABLED", prefix, payload.len());
                }
                if payload.len() > policy.max_text_bytes {
                    return Self::deny("TEXT_EXCEEDS_MAX_SIZE", prefix, payload.len());
                }
                if std::str::from_utf8(payload).is_err() {
                    return Self::deny("INVALID_UTF8_TEXT", prefix, payload.len());
                }
            }
            ClipboardPayloadKind::RichTextHtml => {
                if !policy.allow_rich_html {
                    return Self::deny("RICH_HTML_CLIPBOARD_DISABLED", prefix, payload.len());
                }
                if payload.len() > policy.max_text_bytes {
                    return Self::deny("RICH_HTML_EXCEEDS_MAX_SIZE", prefix, payload.len());
                }
            }
            ClipboardPayloadKind::ImageBytes => {
                if !policy.allow_images {
                    return Self::deny("IMAGE_CLIPBOARD_DISABLED", prefix, payload.len());
                }
                if payload.len() > policy.max_binary_bytes {
                    return Self::deny("IMAGE_EXCEEDS_MAX_SIZE", prefix, payload.len());
                }
            }
            ClipboardPayloadKind::FileList => {
                if !policy.allow_files {
                    return Self::deny("FILE_CLIPBOARD_DISABLED", prefix, payload.len());
                }
                if payload.len() > policy.max_binary_bytes {
                    return Self::deny("FILE_CLIPBOARD_EXCEEDS_MAX_SIZE", prefix, payload.len());
                }
            }
        }

        let mut digests = self.recent_digests.lock().unwrap();
        while let Some(front) = digests.front() {
            if now_ms.saturating_sub(front.timestamp_ms) > policy.loop_window_ms {
                digests.pop_front();
            } else {
                break;
            }
        }

        if digests
            .iter()
            .any(|d| d.digest_hex == full_hash && d.origin_peer != origin_peer)
        {
            let mut loops = self.blocked_loops_count.lock().unwrap();
            *loops += 1;
            return Self::deny("CLIPBOARD_ECHO_LOOP_SUPPRESSED", prefix, payload.len());
        }

        if digests.len() >= 64 {
            digests.pop_front();
        }
        digests.push_back(SeenDigest {
            digest_hex: full_hash,
            origin_peer: origin_peer.to_owned(),
            timestamp_ms: now_ms,
        });

        let mut synced = self.synced_items_count.lock().unwrap();
        *synced += 1;

        ClipboardCheckDecision {
            allowed: true,
            reason: "ALLOWED_INERT_DATA_ONLY".to_owned(),
            payload_sha256_prefix: prefix,
            byte_len: payload.len(),
            auto_execute_blocked: true,
        }
    }

    fn deny(reason: &str, prefix: String, byte_len: usize) -> ClipboardCheckDecision {
        ClipboardCheckDecision {
            allowed: false,
            reason: reason.to_owned(),
            payload_sha256_prefix: prefix,
            byte_len,
            auto_execute_blocked: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vietnamese_unicode_and_code_prompt_allowed_and_loop_blocked() {
        let guard = ClipboardGuard::new();
        let vn_prompt = "Xin chào Boss! Hãy kiểm tra tiến độ DAUVERSE AI:\n```powershell\nGet-Process | Where-Object {$_.CPU -gt 10}\n```\nKết quả tiếng Việt chuẩn UTF-8: Đặng Tuấn — 100% chính xác.";
        let d1 = guard.inspect_and_record(
            "peer-office",
            false,
            ClipboardPayloadKind::PlainTextUtf8,
            vn_prompt.as_bytes(),
            1_000,
        );
        assert!(d1.allowed);
        assert!(d1.auto_execute_blocked);

        let echo = guard.inspect_and_record(
            "peer-home",
            true,
            ClipboardPayloadKind::PlainTextUtf8,
            vn_prompt.as_bytes(),
            1_400,
        );
        assert!(!echo.allowed);
        assert_eq!(echo.reason, "CLIPBOARD_ECHO_LOOP_SUPPRESSED");

        let after_window = guard.inspect_and_record(
            "peer-home",
            true,
            ClipboardPayloadKind::PlainTextUtf8,
            vn_prompt.as_bytes(),
            3_000,
        );
        assert!(after_window.allowed);
    }

    #[test]
    fn oversize_and_disabled_direction_rejected() {
        let guard = ClipboardGuard::new();
        let mut p = guard.get_policy();
        p.max_text_bytes = 32;
        guard.update_policy(p);

        let decision = guard.inspect_and_record(
            "peer-a",
            true,
            ClipboardPayloadKind::PlainTextUtf8,
            b"0123456789012345678901234567890123456789",
            5_000,
        );
        assert!(!decision.allowed);
        assert_eq!(decision.reason, "TEXT_EXCEEDS_MAX_SIZE");
    }
}

use super::crypto_util::{active_vault_backend, constant_time_eq, redact_sensitive, sha256_hex};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, VecDeque},
    sync::Mutex,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Capability {
    RemoteControl,
    ViewOnly,
    Clipboard,
    FileTransfer,
    Audio,
    PowerControl,
    HardwareMonitoring,
    AiNotification,
    AiStatus,
    Recording,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PermissionProfile {
    pub remote_control: bool,
    pub view_only: bool,
    pub clipboard: bool,
    pub file_transfer: bool,
    pub audio: bool,
    pub power_control: bool,
    pub hardware_monitoring: bool,
    pub ai_notification: bool,
    pub ai_status: bool,
    pub recording: bool,
}

impl PermissionProfile {
    pub fn least_privilege_default() -> Self {
        Self {
            remote_control: false,
            view_only: true,
            clipboard: false,
            file_transfer: false,
            audio: false,
            power_control: false,
            hardware_monitoring: true,
            ai_notification: true,
            ai_status: true,
            recording: false,
        }
    }

    pub fn boss_trusted_workstation_preset() -> Self {
        Self {
            remote_control: true,
            view_only: true,
            clipboard: true,
            file_transfer: true,
            audio: true,
            power_control: true,
            hardware_monitoring: true,
            ai_notification: true,
            ai_status: true,
            recording: false,
        }
    }

    pub fn has(&self, cap: Capability) -> bool {
        match cap {
            Capability::RemoteControl => self.remote_control,
            Capability::ViewOnly => self.view_only || self.remote_control,
            Capability::Clipboard => self.clipboard,
            Capability::FileTransfer => self.file_transfer,
            Capability::Audio => self.audio,
            Capability::PowerControl => self.power_control,
            Capability::HardwareMonitoring => self.hardware_monitoring,
            Capability::AiNotification => self.ai_notification,
            Capability::AiStatus => self.ai_status,
            Capability::Recording => self.recording,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrustedDeviceEntry {
    pub device_id: String,
    pub display_name: String,
    pub public_key_fingerprint: String,
    pub paired_at_utc: String,
    pub revoked: bool,
    pub permissions: PermissionProfile,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActiveSessionBinding {
    pub session_id: String,
    pub device_id: String,
    pub channel_binding_hash: String,
    pub created_at_ms: i64,
    pub last_activity_ms: i64,
    pub idle_timeout_ms: i64,
    pub absolute_timeout_ms: i64,
    pub revoked: bool,
    pub permissions: PermissionProfile,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditLogEntry {
    pub seq: u64,
    pub timestamp_utc: String,
    pub actor: String,
    pub action: String,
    pub outcome: String,
    pub detail: String,
    pub prev_hash: String,
    pub entry_hash: String,
}

#[derive(Debug, Clone, Default)]
struct AuthAttemptState {
    failed_timestamps_ms: VecDeque<i64>,
    locked_until_ms: i64,
}

pub struct DeviceShieldSecurityCenter {
    allowlist_enforced: Mutex<bool>,
    mfa_required_for_unattended: Mutex<bool>,
    telemetry_disabled_by_default: bool,
    trusted_devices: Mutex<HashMap<String, TrustedDeviceEntry>>,
    sessions: Mutex<HashMap<String, ActiveSessionBinding>>,
    rate_limiter: Mutex<HashMap<String, AuthAttemptState>>,
    seen_auth_nonces: Mutex<VecDeque<String>>,
    audit_chain: Mutex<Vec<AuditLogEntry>>,
    audit_log_path: Option<std::path::PathBuf>,
}

const MAX_FAILED_ATTEMPTS_PER_MIN: usize = 5;
const AUTH_WINDOW_MS: i64 = 60_000;
const BASE_LOCKOUT_MS: i64 = 120_000;

impl DeviceShieldSecurityCenter {
    pub fn new() -> Self {
        Self::with_audit_log_path(None)
    }

    pub fn with_audit_log_path(audit_path: Option<std::path::PathBuf>) -> Self {
        let mut loaded_chain: Vec<AuditLogEntry> = Vec::new();
        if let Some(ref p) = audit_path {
            if let Ok(raw) = std::fs::read_to_string(p) {
                for line in raw.lines() {
                    if let Ok(entry) = serde_json::from_str::<AuditLogEntry>(line) {
                        loaded_chain.push(entry);
                    }
                }
            }
        }
        let had_existing = !loaded_chain.is_empty();
        let center = Self {
            allowlist_enforced: Mutex::new(true),
            mfa_required_for_unattended: Mutex::new(false),
            telemetry_disabled_by_default: true,
            trusted_devices: Mutex::new(HashMap::new()),
            sessions: Mutex::new(HashMap::new()),
            rate_limiter: Mutex::new(HashMap::new()),
            seen_auth_nonces: Mutex::new(VecDeque::with_capacity(512)),
            audit_chain: Mutex::new(loaded_chain),
            audit_log_path: audit_path,
        };
        if !had_existing {
            center.append_audit(
                "SYSTEM",
                "SECURITY_CENTER_INIT",
                "OK",
                &format!(
                    "Initialized Device Shield (vault={}, allowlist=true, telemetry=false)",
                    active_vault_backend().as_str()
                ),
            );
        }
        center
    }

    pub fn summary(&self) -> serde_json::Value {
        let allowlist = *self.allowlist_enforced.lock().unwrap();
        let mfa = *self.mfa_required_for_unattended.lock().unwrap();
        let devices: Vec<TrustedDeviceEntry> =
            self.trusted_devices.lock().unwrap().values().cloned().collect();
        let active_sessions = self
            .sessions
            .lock()
            .unwrap()
            .values()
            .filter(|s| !s.revoked)
            .count();
        let chain_ok = self.verify_audit_chain().is_ok();
        serde_json::json!({
            "encryption": "End-to-End NaCl/Curve25519 + XSalsa20-Poly1305 (RustDesk Protocol) + HMAC-SHA256 IPC/Events",
            "credential_vault": active_vault_backend().as_str(),
            "allowlist_enforced": allowlist,
            "mfa_required": mfa,
            "telemetry_enabled": !self.telemetry_disabled_by_default,
            "trusted_devices_count": devices.iter().filter(|d| !d.revoked).count(),
            "revoked_devices_count": devices.iter().filter(|d| d.revoked).count(),
            "active_sessions_count": active_sessions,
            "audit_chain_intact": chain_ok,
            "step_up_pin_configured": self.is_step_up_passcode_configured(),
            "trusted_devices": devices,
        })
    }

    fn step_up_vault_path(&self) -> std::path::PathBuf {
        self.audit_log_path
            .as_ref()
            .and_then(|p| p.parent().map(|dir| dir.join("step_up_pin.vault")))
            .unwrap_or_else(|| std::env::temp_dir().join("dauverse_step_up_pin.vault"))
    }

    pub fn is_step_up_passcode_configured(&self) -> bool {
        if self.step_up_vault_path().is_file() {
            return true;
        }
        std::env::var("DAUVERSE_BOSS_STEP_UP_PIN")
            .map(|s| s.trim().len() >= 6)
            .unwrap_or(false)
    }

    pub fn set_step_up_passcode(&self, new_pin: &str) -> Result<(), String> {
        let trimmed = new_pin.trim();
        if trimmed.len() < 6 {
            return Err("STEP_UP_PIN_TOO_SHORT: Minimum 6 characters required".to_owned());
        }
        let vp = self.step_up_vault_path();
        super::crypto_util::write_sealed_secret_file(
            &vp,
            trimmed.as_bytes(),
            b"dauverse-boss-step-up-pin-v1",
        )?;
        self.append_audit("BOSS", "SET_STEP_UP_PIN", "OK", "Sealed Step-Up PIN updated in vault");
        Ok(())
    }

    pub fn verify_step_up_passcode(&self, candidate: &str) -> bool {
        let cand = candidate.trim().as_bytes();
        if cand.len() < 6 {
            self.append_audit("BOSS", "VERIFY_STEP_UP_PIN", "DENIED", "Empty or short Step-Up PIN");
            return false;
        }
        let vp = self.step_up_vault_path();
        if let Ok(expected) =
            super::crypto_util::read_sealed_secret_file(&vp, b"dauverse-boss-step-up-pin-v1")
        {
            let ok = super::crypto_util::constant_time_eq(&expected, cand);
            self.append_audit(
                "BOSS",
                "VERIFY_STEP_UP_PIN",
                if ok { "ALLOWED" } else { "DENIED" },
                "Verified against sealed step_up_pin.vault",
            );
            return ok;
        }
        if let Ok(env_pin) = std::env::var("DAUVERSE_BOSS_STEP_UP_PIN") {
            let trimmed = env_pin.trim().as_bytes();
            if trimmed.len() >= 6 {
                let ok = super::crypto_util::constant_time_eq(trimmed, cand);
                self.append_audit(
                    "BOSS",
                    "VERIFY_STEP_UP_PIN",
                    if ok { "ALLOWED" } else { "DENIED" },
                    "Verified against DAUVERSE_BOSS_STEP_UP_PIN",
                );
                return ok;
            }
        }
        self.append_audit(
            "BOSS",
            "VERIFY_STEP_UP_PIN",
            "DENIED",
            "No Step-Up PIN enrolled in vault",
        );
        false
    }

    pub fn pair_trusted_device(
        &self,
        device_id: &str,
        display_name: &str,
        public_key_fingerprint: &str,
        permissions: PermissionProfile,
        owner_authenticated: bool,
    ) -> Result<TrustedDeviceEntry, String> {
        if !owner_authenticated {
            self.append_audit(device_id, "PAIR_DEVICE", "DENIED", "Missing owner step-up authentication");
            return Err("SECURITY_DENY_PAIRING_REQUIRES_OWNER_AUTH".to_owned());
        }
        if device_id.trim().is_empty() || public_key_fingerprint.trim().len() < 16 {
            return Err("SECURITY_DENY_INVALID_DEVICE_IDENTITY".to_owned());
        }
        let entry = TrustedDeviceEntry {
            device_id: device_id.to_owned(),
            display_name: display_name.to_owned(),
            public_key_fingerprint: public_key_fingerprint.to_owned(),
            paired_at_utc: chrono::Utc::now().to_rfc3339(),
            revoked: false,
            permissions,
        };
        self.trusted_devices
            .lock()
            .unwrap()
            .insert(device_id.to_owned(), entry.clone());
        self.append_audit(device_id, "PAIR_DEVICE", "ALLOWED", display_name);
        Ok(entry)
    }

    pub fn revoke_device(&self, device_id: &str, owner_authenticated: bool) -> Result<(), String> {
        if !owner_authenticated {
            return Err("SECURITY_DENY_REVOKE_REQUIRES_OWNER_AUTH".to_owned());
        }
        {
            let mut devs = self.trusted_devices.lock().unwrap();
            let dev = devs
                .get_mut(device_id)
                .ok_or_else(|| "device not found".to_owned())?;
            dev.revoked = true;
        }
        for sess in self.sessions.lock().unwrap().values_mut() {
            if sess.device_id == device_id {
                sess.revoked = true;
            }
        }
        self.append_audit(device_id, "REVOKE_DEVICE_AND_SESSIONS", "OK", "Device and active sessions revoked");
        Ok(())
    }

    pub fn authenticate_and_open_session(
        &self,
        device_id: &str,
        expected_peer_fingerprint: &str,
        channel_binding_hash: &str,
        auth_nonce: &str,
        credentials_valid: bool,
        now_ms: i64,
    ) -> Result<ActiveSessionBinding, String> {
        if auth_nonce.trim().len() < 8 || channel_binding_hash.trim().len() < 16 {
            return Err("SECURITY_DENY_WEAK_NONCE_OR_CHANNEL_BINDING".to_owned());
        }

        {
            let mut limiter = self.rate_limiter.lock().unwrap();
            let st = limiter.entry(device_id.to_owned()).or_default();
            if now_ms < st.locked_until_ms {
                self.append_audit(device_id, "SESSION_AUTH", "LOCKED_OUT", "Rate limit / brute-force lockout active");
                return Err("SECURITY_DENY_RATE_LIMITED_LOCKOUT".to_owned());
            }
            while let Some(&front) = st.failed_timestamps_ms.front() {
                if now_ms - front > AUTH_WINDOW_MS {
                    st.failed_timestamps_ms.pop_front();
                } else {
                    break;
                }
            }
        }

        {
            let mut nonces = self.seen_auth_nonces.lock().unwrap();
            if nonces.iter().any(|n| n == auth_nonce) {
                self.append_audit(device_id, "SESSION_AUTH", "DENIED_REPLAY", "Replayed auth nonce");
                return Err("SECURITY_DENY_AUTH_REPLAY".to_owned());
            }
            if nonces.len() >= 1_024 {
                nonces.pop_front();
            }
            nonces.push_back(auth_nonce.to_owned());
        }

        if !credentials_valid {
            let mut limiter = self.rate_limiter.lock().unwrap();
            let st = limiter.entry(device_id.to_owned()).or_default();
            st.failed_timestamps_ms.push_back(now_ms);
            if st.failed_timestamps_ms.len() >= MAX_FAILED_ATTEMPTS_PER_MIN {
                st.locked_until_ms = now_ms + BASE_LOCKOUT_MS;
            }
            drop(limiter);
            self.append_audit(device_id, "SESSION_AUTH", "DENIED_BAD_CREDENTIALS", "Invalid credentials");
            return Err("SECURITY_DENY_INVALID_CREDENTIALS".to_owned());
        }

        let allowlist = *self.allowlist_enforced.lock().unwrap();
        let perms = {
            let devs = self.trusted_devices.lock().unwrap();
            match devs.get(device_id) {
                Some(d) => {
                    if d.revoked {
                        self.append_audit(device_id, "SESSION_AUTH", "DENIED_REVOKED", "Device is revoked");
                        return Err("SECURITY_DENY_DEVICE_REVOKED".to_owned());
                    }
                    if !constant_time_eq(
                        d.public_key_fingerprint.as_bytes(),
                        expected_peer_fingerprint.as_bytes(),
                    ) {
                        self.append_audit(device_id, "SESSION_AUTH", "DENIED_MITM_KEY_MISMATCH", "Peer public key mismatch");
                        return Err("SECURITY_DENY_MITM_PEER_KEY_MISMATCH".to_owned());
                    }
                    d.permissions.clone()
                }
                None => {
                    if allowlist {
                        self.append_audit(device_id, "SESSION_AUTH", "DENIED_NOT_IN_ALLOWLIST", "Untrusted device");
                        return Err("SECURITY_DENY_UNTRUSTED_DEVICE_ALLOWLIST".to_owned());
                    }
                    PermissionProfile::least_privilege_default()
                }
            }
        };

        let binding = ActiveSessionBinding {
            session_id: uuid::Uuid::new_v4().to_string(),
            device_id: device_id.to_owned(),
            channel_binding_hash: channel_binding_hash.to_owned(),
            created_at_ms: now_ms,
            last_activity_ms: now_ms,
            idle_timeout_ms: 30 * 60 * 1_000,
            absolute_timeout_ms: 12 * 60 * 60 * 1_000,
            revoked: false,
            permissions: perms,
        };
        self.sessions
            .lock()
            .unwrap()
            .insert(binding.session_id.clone(), binding.clone());
        self.append_audit(device_id, "SESSION_OPEN", "ALLOWED", &binding.session_id);
        Ok(binding)
    }

    pub fn authorize_session_capability(
        &self,
        session_id: &str,
        device_id: &str,
        channel_binding_hash: &str,
        capability: Capability,
        now_ms: i64,
    ) -> Result<(), String> {
        let mut sessions = self.sessions.lock().unwrap();
        let Some(sess) = sessions.get_mut(session_id) else {
            return Err("SECURITY_DENY_UNKNOWN_SESSION".to_owned());
        };
        if sess.revoked {
            return Err("SECURITY_DENY_SESSION_REVOKED".to_owned());
        }
        if sess.device_id != device_id
            || !constant_time_eq(
                sess.channel_binding_hash.as_bytes(),
                channel_binding_hash.as_bytes(),
            )
        {
            sess.revoked = true;
            return Err("SECURITY_DENY_SESSION_HIJACK_OR_MITM_DETECTED".to_owned());
        }
        if now_ms - sess.last_activity_ms > sess.idle_timeout_ms
            || now_ms - sess.created_at_ms > sess.absolute_timeout_ms
        {
            sess.revoked = true;
            return Err("SECURITY_DENY_SESSION_EXPIRED".to_owned());
        }
        if !sess.permissions.has(capability) {
            return Err(format!("SECURITY_DENY_MISSING_CAPABILITY_{capability:?}"));
        }
        sess.last_activity_ms = now_ms;
        Ok(())
    }

    pub fn revoke_session(&self, session_id: &str) -> Result<(), String> {
        let mut sessions = self.sessions.lock().unwrap();
        let sess = sessions
            .get_mut(session_id)
            .ok_or_else(|| "session not found".to_owned())?;
        sess.revoked = true;
        drop(sessions);
        self.append_audit("OWNER", "REVOKE_SESSION", "OK", session_id);
        Ok(())
    }

    pub fn append_audit(&self, actor: &str, action: &str, outcome: &str, detail: &str) {
        let clean_detail = redact_sensitive(detail);
        let mut chain = self.audit_chain.lock().unwrap();
        let seq = chain.last().map(|e| e.seq + 1).unwrap_or(1);
        let prev_hash = chain
            .last()
            .map(|e| e.entry_hash.clone())
            .unwrap_or_else(|| "0000000000000000000000000000000000000000000000000000000000000000".to_owned());
        let ts = chrono::Utc::now().to_rfc3339();
        let material = format!("{seq}|{ts}|{actor}|{action}|{outcome}|{clean_detail}|{prev_hash}");
        let entry_hash = sha256_hex(material.as_bytes());
        let entry = AuditLogEntry {
            seq,
            timestamp_utc: ts,
            actor: actor.to_owned(),
            action: action.to_owned(),
            outcome: outcome.to_owned(),
            detail: clean_detail,
            prev_hash,
            entry_hash,
        };
        if let Some(ref p) = self.audit_log_path {
            if let Ok(line) = serde_json::to_string(&entry) {
                use std::io::Write;
                #[cfg(unix)]
                {
                    use std::os::unix::fs::OpenOptionsExt;
                    if let Ok(mut f) = std::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .mode(0o600)
                        .open(p)
                    {
                        let _ = writeln!(f, "{line}");
                    }
                }
                #[cfg(not(unix))]
                {
                    if let Ok(mut f) = std::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(p)
                    {
                        let _ = writeln!(f, "{line}");
                    }
                }
            }
        }
        if chain.len() >= 2_000 {
            chain.remove(0);
        }
        chain.push(entry);
    }

    pub fn verify_audit_chain(&self) -> Result<usize, String> {
        let chain = self.audit_chain.lock().unwrap();
        for (idx, entry) in chain.iter().enumerate() {
            if idx > 0 && entry.prev_hash != chain[idx - 1].entry_hash {
                return Err(format!("AUDIT_CHAIN_BROKEN_PREV_HASH_AT_SEQ_{}", entry.seq));
            }
            let material = format!(
                "{}|{}|{}|{}|{}|{}|{}",
                entry.seq,
                entry.timestamp_utc,
                entry.actor,
                entry.action,
                entry.outcome,
                entry.detail,
                entry.prev_hash
            );
            let expected = sha256_hex(material.as_bytes());
            if expected != entry.entry_hash {
                return Err(format!("AUDIT_CHAIN_TAMPERED_AT_SEQ_{}", entry.seq));
            }
        }
        Ok(chain.len())
    }

    pub fn recent_audit_entries(&self, limit: usize) -> Vec<AuditLogEntry> {
        let chain = self.audit_chain.lock().unwrap();
        chain.iter().rev().take(limit).cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn negative_security_matrix_unauthorized_mitm_hijack_bruteforce_revocation_and_audit() {
        let sec = DeviceShieldSecurityCenter::new();

        assert!(sec
            .pair_trusted_device(
                "OFFICE-PC",
                "Boss Office PC",
                "ed25519:abcdef0123456789abcdef0123456789",
                PermissionProfile::least_privilege_default(),
                false
            )
            .is_err());

        assert!(sec
            .authenticate_and_open_session(
                "STRANGER-PC",
                "ed25519:11111111111111111111",
                "tls-bind-0000000000000001",
                "nonce-stranger-1",
                true,
                10_000,
            )
            .is_err());

        sec.pair_trusted_device(
            "OFFICE-PC",
            "Boss Office PC",
            "ed25519:abcdef0123456789abcdef0123456789",
            PermissionProfile::least_privilege_default(),
            true,
        )
        .unwrap();

        let mitm = sec.authenticate_and_open_session(
            "OFFICE-PC",
            "ed25519:attacker_substituted_key_99999999",
            "tls-bind-0000000000000001",
            "nonce-mitm-1",
            true,
            11_000,
        );
        assert_eq!(mitm.unwrap_err(), "SECURITY_DENY_MITM_PEER_KEY_MISMATCH");

        for i in 0..5 {
            let _ = sec.authenticate_and_open_session(
                "BRUTE-PEER",
                "ed25519:00000000000000000000",
                "tls-bind-0000000000000002",
                &format!("nonce-bf-{i}"),
                false,
                20_000 + i * 100,
            );
        }
        let locked = sec.authenticate_and_open_session(
            "BRUTE-PEER",
            "ed25519:00000000000000000000",
            "tls-bind-0000000000000002",
            "nonce-bf-6",
            true,
            21_000,
        );
        assert_eq!(locked.unwrap_err(), "SECURITY_DENY_RATE_LIMITED_LOCKOUT");

        let sess = sec
            .authenticate_and_open_session(
                "OFFICE-PC",
                "ed25519:abcdef0123456789abcdef0123456789",
                "tls-bind-valid-channel-0001",
                "nonce-ok-0001",
                true,
                30_000,
            )
            .unwrap();

        let replay = sec.authenticate_and_open_session(
            "OFFICE-PC",
            "ed25519:abcdef0123456789abcdef0123456789",
            "tls-bind-valid-channel-0001",
            "nonce-ok-0001",
            true,
            30_100,
        );
        assert_eq!(replay.unwrap_err(), "SECURITY_DENY_AUTH_REPLAY");

        assert!(sec
            .authorize_session_capability(
                &sess.session_id,
                "OFFICE-PC",
                "tls-bind-valid-channel-0001",
                Capability::ViewOnly,
                31_000
            )
            .is_ok());

        assert!(sec
            .authorize_session_capability(
                &sess.session_id,
                "OFFICE-PC",
                "tls-bind-valid-channel-0001",
                Capability::PowerControl,
                31_500
            )
            .is_err());

        let hijack = sec.authorize_session_capability(
            &sess.session_id,
            "OFFICE-PC",
            "tls-bind-hijacked-channel-9999",
            Capability::ViewOnly,
            32_000,
        );
        assert_eq!(
            hijack.unwrap_err(),
            "SECURITY_DENY_SESSION_HIJACK_OR_MITM_DETECTED"
        );

        sec.revoke_device("OFFICE-PC", true).unwrap();
        assert!(sec
            .authenticate_and_open_session(
                "OFFICE-PC",
                "ed25519:abcdef0123456789abcdef0123456789",
                "tls-bind-valid-channel-0002",
                "nonce-after-revoke",
                true,
                40_000,
            )
            .is_err());

        assert!(sec.verify_audit_chain().unwrap() >= 6);
    }
}

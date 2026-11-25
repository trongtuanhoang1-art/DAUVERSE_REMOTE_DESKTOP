use super::crypto_util::{
    active_vault_backend, check_no_symlink_or_reparse_component, constant_time_eq,
    open_no_follow_regular_file, read_sealed_secret_file, redact_sensitive, sha256_hex,
    write_atomic_bytes, write_sealed_secret_file,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, VecDeque},
    io::Read,
    path::PathBuf,
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
pub struct StepUpAuthGrant {
    pub token_id: String,
    pub action_scope: String,
    pub issued_at_ms: i64,
    pub expires_at_ms: i64,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PersistedSecurityState {
    allowlist_enforced: bool,
    mfa_required_for_unattended: bool,
    trusted_devices: HashMap<String, TrustedDeviceEntry>,
    step_up_locked_until_ms: i64,
    step_up_failed_timestamps_ms: Vec<i64>,
}

pub struct DeviceShieldSecurityCenter {
    allowlist_enforced: Mutex<bool>,
    mfa_required_for_unattended: Mutex<bool>,
    telemetry_disabled_by_default: bool,
    trusted_devices: Mutex<HashMap<String, TrustedDeviceEntry>>,
    sessions: Mutex<HashMap<String, ActiveSessionBinding>>,
    step_up_tokens: Mutex<HashMap<String, StepUpAuthGrant>>,
    rate_limiter: Mutex<HashMap<String, AuthAttemptState>>,
    seen_auth_nonces: Mutex<VecDeque<String>>,
    audit_chain: Mutex<Vec<AuditLogEntry>>,
    audit_log_path: Option<PathBuf>,
    state_corrupted_fail_closed: Mutex<bool>,
    last_persistence_error: Mutex<Option<String>>,
}

const MAX_FAILED_ATTEMPTS_PER_MIN: usize = 5;
const AUTH_WINDOW_MS: i64 = 60_000;
const BASE_LOCKOUT_MS: i64 = 120_000;
pub const STEP_UP_TOKEN_TTL_MS: i64 = 300_000;
const STEP_UP_PIN_PRINCIPAL: &str = "STEP_UP_PIN_OWNER";
const STEP_UP_PIN_ENTROPY: &[u8] = b"dauverse-boss-step-up-pin-v1";

impl DeviceShieldSecurityCenter {
    pub fn new() -> Self {
        Self::with_audit_log_path(None)
    }

    pub fn with_audit_log_path(audit_path: Option<PathBuf>) -> Self {
        let mut loaded_chain: Vec<AuditLogEntry> = Vec::new();
        let mut corrupted_state = false;
        let mut init_err: Option<String> = None;

        if let Some(ref p) = audit_path {
            if std::fs::symlink_metadata(p).is_ok() {
                match open_no_follow_regular_file(p) {
                    Ok((mut f, _)) => {
                        let mut raw = String::new();
                        if f.read_to_string(&mut raw).is_ok() {
                            for line in raw.lines() {
                                let trimmed = line.trim();
                                if trimmed.is_empty() {
                                    continue;
                                }
                                match serde_json::from_str::<AuditLogEntry>(trimmed) {
                                    Ok(entry) => loaded_chain.push(entry),
                                    Err(e) => {
                                        corrupted_state = true;
                                        init_err = Some(format!("AUDIT_LOG_PARSE_ERROR: {e}"));
                                        break;
                                    }
                                }
                            }
                        } else {
                            corrupted_state = true;
                            init_err = Some("AUDIT_LOG_READ_ERROR".to_owned());
                        }
                    }
                    Err(e) => {
                        corrupted_state = true;
                        init_err = Some(e);
                    }
                }
            }
        }

        let mut allowlist = true;
        let mut mfa = false;
        let mut devices = HashMap::new();
        let mut limiter = HashMap::new();

        if let Some(state_path) = audit_path
            .as_ref()
            .and_then(|p| p.parent().map(|dir| dir.join("security_state.json")))
        {
            if std::fs::symlink_metadata(&state_path).is_ok() {
                match open_no_follow_regular_file(&state_path) {
                    Ok((mut f, _)) => {
                        let mut raw = String::new();
                        match f.read_to_string(&mut raw).ok().and_then(|_| {
                            serde_json::from_str::<PersistedSecurityState>(&raw).ok()
                        }) {
                            Some(saved) => {
                                allowlist = saved.allowlist_enforced;
                                mfa = saved.mfa_required_for_unattended;
                                devices = saved.trusted_devices;
                                if saved.step_up_locked_until_ms > 0
                                    || !saved.step_up_failed_timestamps_ms.is_empty()
                                {
                                    limiter.insert(
                                        STEP_UP_PIN_PRINCIPAL.to_owned(),
                                        AuthAttemptState {
                                            failed_timestamps_ms: saved
                                                .step_up_failed_timestamps_ms
                                                .into_iter()
                                                .collect(),
                                            locked_until_ms: saved.step_up_locked_until_ms,
                                        },
                                    );
                                }
                            }
                            None => {
                                corrupted_state = true;
                                allowlist = true;
                                init_err = Some("SECURITY_STATE_CORRUPTED_FAIL_CLOSED".to_owned());
                            }
                        }
                    }
                    Err(e) => {
                        corrupted_state = true;
                        allowlist = true;
                        init_err = Some(e);
                    }
                }
            }
        }

        let had_existing = !loaded_chain.is_empty();
        let center = Self {
            allowlist_enforced: Mutex::new(allowlist),
            mfa_required_for_unattended: Mutex::new(mfa),
            telemetry_disabled_by_default: true,
            trusted_devices: Mutex::new(devices),
            sessions: Mutex::new(HashMap::new()),
            step_up_tokens: Mutex::new(HashMap::new()),
            rate_limiter: Mutex::new(limiter),
            seen_auth_nonces: Mutex::new(VecDeque::with_capacity(512)),
            audit_chain: Mutex::new(loaded_chain),
            audit_log_path: audit_path,
            state_corrupted_fail_closed: Mutex::new(corrupted_state),
            last_persistence_error: Mutex::new(init_err),
        };
        if !had_existing && !corrupted_state {
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

    fn security_state_path(&self) -> Option<PathBuf> {
        self.audit_log_path
            .as_ref()
            .and_then(|p| p.parent().map(|dir| dir.join("security_state.json")))
    }

    fn persist_security_state(&self) -> Result<(), String> {
        let Some(path) = self.security_state_path() else {
            return Ok(());
        };
        let allowlist = *self.allowlist_enforced.lock().unwrap();
        let mfa = *self.mfa_required_for_unattended.lock().unwrap();
        let devices = self.trusted_devices.lock().unwrap().clone();
        let (locked_until_ms, failed_vec) = {
            let lim = self.rate_limiter.lock().unwrap();
            match lim.get(STEP_UP_PIN_PRINCIPAL) {
                Some(st) => (
                    st.locked_until_ms,
                    st.failed_timestamps_ms.iter().copied().collect(),
                ),
                None => (0, Vec::new()),
            }
        };
        let state = PersistedSecurityState {
            allowlist_enforced: allowlist,
            mfa_required_for_unattended: mfa,
            trusted_devices: devices,
            step_up_locked_until_ms: locked_until_ms,
            step_up_failed_timestamps_ms: failed_vec,
        };
        let bytes = serde_json::to_vec_pretty(&state)
            .map_err(|e| format!("failed serializing security_state.json: {e}"))?;
        if let Err(e) = write_atomic_bytes(&path, &bytes, true) {
            *self.last_persistence_error.lock().unwrap() = Some(e.clone());
            return Err(e);
        }
        Ok(())
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
        let now_ms = chrono::Utc::now().timestamp_millis();
        let step_up_locked_out = self
            .rate_limiter
            .lock()
            .unwrap()
            .get(STEP_UP_PIN_PRINCIPAL)
            .map(|st| now_ms < st.locked_until_ms)
            .unwrap_or(false);
        let vault_corrupted = self.is_step_up_vault_corrupted();
        let state_corrupted = *self.state_corrupted_fail_closed.lock().unwrap();
        let chain_ok = !state_corrupted && self.verify_audit_chain().is_ok();
        let last_err = self.last_persistence_error.lock().unwrap().clone();
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
            "step_up_locked_out": step_up_locked_out,
            "vault_healthy": !vault_corrupted && !state_corrupted,
            "persistence_healthy": last_err.is_none() && !state_corrupted,
            "last_persistence_error": last_err,
            "trusted_devices": devices,
        })
    }

    fn step_up_vault_path(&self) -> PathBuf {
        self.audit_log_path
            .as_ref()
            .and_then(|p| p.parent().map(|dir| dir.join("step_up_pin.vault")))
            .unwrap_or_else(|| {
                super::crypto_util::default_durable_app_data_dir().join("step_up_pin.vault")
            })
    }

    pub fn is_step_up_vault_corrupted(&self) -> bool {
        let vp = self.step_up_vault_path();
        if std::fs::symlink_metadata(&vp).is_err() {
            return false;
        }
        match read_sealed_secret_file(&vp, STEP_UP_PIN_ENTROPY) {
            Ok(bytes) => bytes.len() < 6,
            Err(_) => true,
        }
    }

    pub fn is_step_up_passcode_configured(&self) -> bool {
        let vp = self.step_up_vault_path();
        if std::fs::symlink_metadata(&vp).is_ok() {
            return true;
        }
        std::env::var("DAUVERSE_BOSS_STEP_UP_PIN")
            .map(|s| s.trim().len() >= 6)
            .unwrap_or(false)
    }

    pub fn set_step_up_passcode(&self, new_pin: &str) -> Result<(), String> {
        if *self.state_corrupted_fail_closed.lock().unwrap() || self.is_step_up_vault_corrupted() {
            self.append_audit(
                "BOSS",
                "ENROLL_STEP_UP_PIN",
                "DENIED_CORRUPTED_VAULT",
                "Refused unauthenticated overwrite of corrupted vault",
            );
            return Err("SECURITY_VAULT_CORRUPTED_FAIL_CLOSED: Existing vault/state failed integrity verification".to_owned());
        }
        if self.is_step_up_passcode_configured() {
            self.append_audit(
                "BOSS",
                "ENROLL_STEP_UP_PIN",
                "DENIED_ALREADY_ENROLLED",
                "Step-Up PIN already enrolled; current_pin required to replace",
            );
            return Err("SECURITY_DENY_CURRENT_PIN_REQUIRED: Step-Up PIN is already enrolled; use change_step_up_pin with current_pin".to_owned());
        }
        let trimmed = new_pin.trim();
        if trimmed.len() < 6 {
            return Err("STEP_UP_PIN_TOO_SHORT: Minimum 6 characters required".to_owned());
        }
        let vp = self.step_up_vault_path();
        write_sealed_secret_file(&vp, trimmed.as_bytes(), STEP_UP_PIN_ENTROPY)?;
        self.append_audit(
            "BOSS",
            "ENROLL_STEP_UP_PIN",
            "OK",
            "Initial Step-Up PIN enrolled in encrypted vault",
        );
        Ok(())
    }

    pub fn change_step_up_passcode(&self, current_pin: &str, new_pin: &str) -> Result<(), String> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        self.change_step_up_passcode_at(current_pin, new_pin, now_ms)
    }

    pub fn change_step_up_passcode_at(
        &self,
        current_pin: &str,
        new_pin: &str,
        now_ms: i64,
    ) -> Result<(), String> {
        if *self.state_corrupted_fail_closed.lock().unwrap() || self.is_step_up_vault_corrupted() {
            self.append_audit(
                "BOSS",
                "CHANGE_STEP_UP_PIN",
                "DENIED_CORRUPTED_VAULT",
                "Vault integrity check failed before PIN replacement",
            );
            return Err("SECURITY_VAULT_CORRUPTED_FAIL_CLOSED: Existing vault failed integrity verification".to_owned());
        }
        if !self.is_step_up_passcode_configured() {
            return Err("SECURITY_DENY_NO_EXISTING_PIN_ENROLLED".to_owned());
        }
        self.verify_step_up_passcode_at(current_pin, now_ms)?;

        let trimmed_new = new_pin.trim();
        if trimmed_new.len() < 6 {
            return Err("STEP_UP_PIN_TOO_SHORT: Minimum 6 characters required".to_owned());
        }
        if constant_time_eq(current_pin.trim().as_bytes(), trimmed_new.as_bytes()) {
            return Err("STEP_UP_PIN_UNCHANGED: New PIN must differ from current PIN".to_owned());
        }

        let vp = self.step_up_vault_path();
        write_sealed_secret_file(&vp, trimmed_new.as_bytes(), STEP_UP_PIN_ENTROPY)?;
        self.step_up_tokens.lock().unwrap().clear();
        self.append_audit(
            "BOSS",
            "CHANGE_STEP_UP_PIN",
            "OK",
            "Authenticated Step-Up PIN rotation sealed in vault and active tokens invalidated",
        );
        Ok(())
    }

    pub fn verify_step_up_passcode_at(&self, candidate: &str, now_ms: i64) -> Result<(), String> {
        {
            let mut limiter = self.rate_limiter.lock().unwrap();
            let st = limiter
                .entry(STEP_UP_PIN_PRINCIPAL.to_owned())
                .or_default();
            if now_ms < st.locked_until_ms {
                drop(limiter);
                self.append_audit(
                    "BOSS",
                    "VERIFY_STEP_UP_PIN",
                    "LOCKED_OUT",
                    "Step-Up PIN brute-force lockout active",
                );
                return Err("SECURITY_DENY_STEP_UP_PIN_LOCKED_OUT".to_owned());
            }
            while let Some(&front) = st.failed_timestamps_ms.front() {
                if now_ms - front > AUTH_WINDOW_MS {
                    st.failed_timestamps_ms.pop_front();
                } else {
                    break;
                }
            }
        }

        if *self.state_corrupted_fail_closed.lock().unwrap() {
            self.append_audit(
                "BOSS",
                "VERIFY_STEP_UP_PIN",
                "DENIED_CORRUPTED_STATE",
                "Security state file corrupted; failing closed",
            );
            return Err("SECURITY_STATE_CORRUPTED_FAIL_CLOSED".to_owned());
        }

        let vp = self.step_up_vault_path();
        let expected_secret: Vec<u8> = if std::fs::symlink_metadata(&vp).is_ok() {
            match read_sealed_secret_file(&vp, STEP_UP_PIN_ENTROPY) {
                Ok(bytes) if bytes.len() >= 6 => bytes,
                _ => {
                    self.append_audit(
                        "BOSS",
                        "VERIFY_STEP_UP_PIN",
                        "DENIED_CORRUPTED_VAULT",
                        "step_up_pin.vault failed decryption or MAC check",
                    );
                    return Err("SECURITY_VAULT_CORRUPTED_FAIL_CLOSED".to_owned());
                }
            }
        } else if let Ok(env_pin) = std::env::var("DAUVERSE_BOSS_STEP_UP_PIN") {
            let trimmed = env_pin.trim().as_bytes().to_vec();
            if trimmed.len() < 6 {
                self.append_audit(
                    "BOSS",
                    "VERIFY_STEP_UP_PIN",
                    "DENIED",
                    "No valid Step-Up PIN enrolled",
                );
                return Err("SECURITY_DENY_STEP_UP_PIN_NOT_ENROLLED".to_owned());
            }
            trimmed
        } else {
            self.append_audit(
                "BOSS",
                "VERIFY_STEP_UP_PIN",
                "DENIED",
                "No Step-Up PIN enrolled in vault",
            );
            return Err("SECURITY_DENY_STEP_UP_PIN_NOT_ENROLLED".to_owned());
        };

        let cand = candidate.trim().as_bytes();
        let ok = cand.len() >= 6 && constant_time_eq(&expected_secret, cand);
        if !ok {
            let locked_now = {
                let mut limiter = self.rate_limiter.lock().unwrap();
                let st = limiter
                    .entry(STEP_UP_PIN_PRINCIPAL.to_owned())
                    .or_default();
                st.failed_timestamps_ms.push_back(now_ms);
                if st.failed_timestamps_ms.len() >= MAX_FAILED_ATTEMPTS_PER_MIN {
                    st.locked_until_ms = now_ms + BASE_LOCKOUT_MS;
                    true
                } else {
                    false
                }
            };
            let _ = self.persist_security_state();
            self.append_audit(
                "BOSS",
                "VERIFY_STEP_UP_PIN",
                if locked_now { "LOCKED_OUT" } else { "DENIED" },
                "Invalid Step-Up PIN candidate",
            );
            return if locked_now {
                Err("SECURITY_DENY_STEP_UP_PIN_LOCKED_OUT".to_owned())
            } else {
                Err("SECURITY_DENY_INVALID_STEP_UP_PIN".to_owned())
            };
        }

        {
            let mut limiter = self.rate_limiter.lock().unwrap();
            if let Some(st) = limiter.get_mut(STEP_UP_PIN_PRINCIPAL) {
                st.failed_timestamps_ms.clear();
            }
        }
        let _ = self.persist_security_state();
        self.append_audit(
            "BOSS",
            "VERIFY_STEP_UP_PIN",
            "ALLOWED",
            "Verified Step-Up PIN against sealed vault",
        );
        Ok(())
    }

    pub fn verify_step_up_passcode(&self, candidate: &str) -> bool {
        let now_ms = chrono::Utc::now().timestamp_millis();
        self.verify_step_up_passcode_at(candidate, now_ms).is_ok()
    }

    pub fn issue_step_up_token_at(
        &self,
        pin: &str,
        action_scope: &str,
        now_ms: i64,
    ) -> Result<StepUpAuthGrant, String> {
        self.verify_step_up_passcode_at(pin, now_ms)?;
        let scope = if action_scope.trim().is_empty() {
            "*"
        } else {
            action_scope.trim()
        };
        let grant = StepUpAuthGrant {
            token_id: super::crypto_util::generate_nonce_hex(),
            action_scope: scope.to_owned(),
            issued_at_ms: now_ms,
            expires_at_ms: now_ms + STEP_UP_TOKEN_TTL_MS,
        };
        let mut tokens = self.step_up_tokens.lock().unwrap();
        tokens.retain(|_, g| now_ms <= g.expires_at_ms);
        tokens.insert(grant.token_id.clone(), grant.clone());
        Ok(grant)
    }

    pub fn verify_step_up_token_at(
        &self,
        token_id: &str,
        expected_scope: &str,
        now_ms: i64,
    ) -> Result<(), String> {
        if *self.state_corrupted_fail_closed.lock().unwrap() || self.is_step_up_vault_corrupted() {
            return Err("SECURITY_VAULT_CORRUPTED_FAIL_CLOSED".to_owned());
        }
        let trimmed = token_id.trim();
        if trimmed.len() < 16 {
            return Err("SECURITY_DENY_UNKNOWN_STEP_UP_TOKEN".to_owned());
        }
        let mut tokens = self.step_up_tokens.lock().unwrap();
        let Some(grant) = tokens.get(trimmed).cloned() else {
            return Err("SECURITY_DENY_UNKNOWN_STEP_UP_TOKEN".to_owned());
        };
        if now_ms > grant.expires_at_ms || now_ms < grant.issued_at_ms {
            tokens.remove(trimmed);
            drop(tokens);
            self.append_audit(
                "BOSS",
                "VERIFY_STEP_UP_TOKEN",
                "DENIED_EXPIRED",
                "Step-Up authentication grant expired",
            );
            return Err("SECURITY_DENY_STEP_UP_AUTH_EXPIRED".to_owned());
        }
        if expected_scope != "*"
            && grant.action_scope != "*"
            && grant.action_scope != expected_scope
        {
            return Err("SECURITY_DENY_STEP_UP_SCOPE_MISMATCH".to_owned());
        }
        Ok(())
    }

    pub fn verify_owner_step_up_or_token(
        &self,
        step_up_pin: &str,
        step_up_token: &str,
        scope: &str,
        now_ms: i64,
    ) -> Result<(), String> {
        if !step_up_token.trim().is_empty() {
            return self.verify_step_up_token_at(step_up_token, scope, now_ms);
        }
        self.verify_step_up_passcode_at(step_up_pin, now_ms)
    }

    pub fn pair_trusted_device(
        &self,
        device_id: &str,
        display_name: &str,
        public_key_fingerprint: &str,
        permissions: PermissionProfile,
        owner_authenticated: bool,
    ) -> Result<TrustedDeviceEntry, String> {
        if *self.state_corrupted_fail_closed.lock().unwrap() {
            return Err("SECURITY_STATE_CORRUPTED_FAIL_CLOSED".to_owned());
        }
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
        self.persist_security_state()?;
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
        self.persist_security_state()?;
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
            let persist_res: Result<(), String> = (|| {
                if let Some(parent) = p.parent() {
                    super::crypto_util::ensure_private_dir(parent)?;
                }
                check_no_symlink_or_reparse_component(p)?;
                let line = serde_json::to_string(&entry)
                    .map_err(|e| format!("failed serializing audit entry: {e}"))?;
                use std::io::Write;
                #[cfg(unix)]
                {
                    use std::os::unix::fs::OpenOptionsExt;
                    let mut f = std::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .mode(0o600)
                        .custom_flags(hbb_common::libc::O_NOFOLLOW)
                        .open(p)
                        .map_err(|e| format!("failed opening audit log: {e}"))?;
                    writeln!(f, "{line}")
                        .map_err(|e| format!("failed writing audit log: {e}"))?;
                    f.sync_all()
                        .map_err(|e| format!("failed syncing audit log: {e}"))?;
                }
                #[cfg(not(unix))]
                {
                    let mut f = std::fs::OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(p)
                        .map_err(|e| format!("failed opening audit log: {e}"))?;
                    writeln!(f, "{line}")
                        .map_err(|e| format!("failed writing audit log: {e}"))?;
                    f.sync_all()
                        .map_err(|e| format!("failed syncing audit log: {e}"))?;
                }
                Ok(())
            })();
            if let Err(err) = persist_res {
                *self.last_persistence_error.lock().unwrap() = Some(err);
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

    #[test]
    fn f05_f07_step_up_pin_blocks_unauthenticated_overwrite_enforces_lockout_expiry_and_corrupted_vault_fail_closed() {
        let dir = std::env::temp_dir().join(format!("dv_sec_f05_{}", uuid::Uuid::new_v4()));
        let audit_path = dir.join("security_audit_chain.jsonl");
        let sec = DeviceShieldSecurityCenter::with_audit_log_path(Some(audit_path.clone()));

        // 1. Initial enrollment succeeds once
        sec.set_step_up_passcode("Initial#2026").unwrap();
        assert!(sec.verify_step_up_passcode_at("Initial#2026", 10_000).is_ok());

        // 2. Unauthenticated overwrite is strictly denied (F05)
        let overwrite_err = sec.set_step_up_passcode("Attacker#9999").unwrap_err();
        assert!(overwrite_err.starts_with("SECURITY_DENY_CURRENT_PIN_REQUIRED"));
        assert!(sec.verify_step_up_passcode_at("Attacker#9999", 10_100).is_err());
        assert!(sec.verify_step_up_passcode_at("Initial#2026", 10_200).is_ok());

        // 3. Authenticated rotation with wrong current_pin fails; with right current_pin succeeds & invalidates old tokens
        let grant_before = sec
            .issue_step_up_token_at("Initial#2026", "POWER_CONTROL", 11_000)
            .unwrap();
        assert!(sec
            .verify_step_up_token_at(&grant_before.token_id, "POWER_CONTROL", 12_000)
            .is_ok());
        assert_eq!(
            sec.verify_step_up_token_at(
                &grant_before.token_id,
                "POWER_CONTROL",
                11_000 + STEP_UP_TOKEN_TTL_MS + 1
            )
            .unwrap_err(),
            "SECURITY_DENY_STEP_UP_AUTH_EXPIRED"
        );

        let grant2 = sec
            .issue_step_up_token_at("Initial#2026", "POWER_CONTROL", 15_000)
            .unwrap();
        assert_eq!(
            sec.change_step_up_passcode_at("WrongCurrent#1", "Rotated#2027", 15_500)
                .unwrap_err(),
            "SECURITY_DENY_INVALID_STEP_UP_PIN"
        );
        sec.change_step_up_passcode_at("Initial#2026", "Rotated#2027", 16_000)
            .unwrap();
        assert!(sec
            .verify_step_up_token_at(&grant2.token_id, "POWER_CONTROL", 16_100)
            .is_err());
        assert!(sec.verify_step_up_passcode_at("Rotated#2027", 16_200).is_ok());

        // 4. 5 wrong PIN attempts trigger lockout and lockout persists across restart (F05 + F07)
        sec.pair_trusted_device(
            "PERSIST-DEV",
            "Persisted Workstation",
            "ed25519:1234567890abcdef1234567890abcdef",
            PermissionProfile::least_privilege_default(),
            true,
        )
        .unwrap();

        for i in 0..5 {
            let _ = sec.verify_step_up_passcode_at("BadGuess#000", 50_000 + i * 100);
        }
        assert_eq!(
            sec.verify_step_up_passcode_at("Rotated#2027", 51_000)
                .unwrap_err(),
            "SECURITY_DENY_STEP_UP_PIN_LOCKED_OUT"
        );

        let restarted = DeviceShieldSecurityCenter::with_audit_log_path(Some(audit_path.clone()));
        assert_eq!(restarted.summary()["trusted_devices_count"], 1);
        assert_eq!(
            restarted
                .verify_step_up_passcode_at("Rotated#2027", 52_000)
                .unwrap_err(),
            "SECURITY_DENY_STEP_UP_PIN_LOCKED_OUT"
        );
        // After lockout window expires (50_400 + 120_000), valid PIN succeeds again
        assert!(restarted
            .verify_step_up_passcode_at("Rotated#2027", 200_000)
            .is_ok());

        // 5. Corrupted vault fails closed and blocks overwrite or verification
        let vp = dir.join("step_up_pin.vault");
        std::fs::write(&vp, b"CORRUPTED_TAMPERED_VAULT_BYTES").unwrap();
        assert_eq!(
            restarted
                .verify_step_up_passcode_at("Rotated#2027", 201_000)
                .unwrap_err(),
            "SECURITY_VAULT_CORRUPTED_FAIL_CLOSED"
        );
        assert!(restarted
            .set_step_up_passcode("TryOverwrite#1")
            .unwrap_err()
            .starts_with("SECURITY_VAULT_CORRUPTED_FAIL_CLOSED"));

        std::fs::remove_dir_all(&dir).ok();
    }
}

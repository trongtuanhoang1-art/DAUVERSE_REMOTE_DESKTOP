use super::crypto_util::{
    check_no_symlink_or_reparse_component, constant_time_eq, hmac_sha256,
    open_no_follow_regular_file, redact_sensitive, write_atomic_bytes,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

pub const AI_EVENT_SCHEMA_V3: u8 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum AiTaskStatus {
    Queued,
    Running,
    WaitingInput,
    WaitingApproval,
    Completed,
    Failed,
    Cancelled,
    Blocked,
    Disconnected,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum AiEventType {
    CommandCompleted,
    TaskCompleted,
    ProcessExited,
    BuildSucceeded,
    BuildFailed,
    QaPassed,
    QaFailed,
    RenderCompleted,
    WaitingUserInput,
    ApprovalRequired,
    TaskProgress,
    Error,
    UnknownState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EventSeverity {
    Info,
    Success,
    Warning,
    High,
    Critical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SourceSupportStatus {
    OfficialHook,
    OfficialLocalHttpReadOnly,
    ExistingControllerEventsReadOnly,
    StructuredLogsReadOnly,
    ReadOnlyProcessMonitor,
    ApprovedWrapperAdapter,
    Unknown,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EventProvenance {
    pub adapter_type: SourceSupportStatus,
    pub evidence_verified: bool,
    pub exit_code: Option<i32>,
    pub evidence_badge: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AiEvent {
    pub event_id: String,
    pub timestamp: String,
    pub source: String,
    pub device_id: String,
    pub project_id: String,
    pub task_id: String,
    pub task_name: String,
    pub event_type: AiEventType,
    pub status: AiTaskStatus,
    pub severity: EventSeverity,
    pub progress: Option<f32>,
    pub summary: String,
    pub artifact_reference: Option<String>,
    pub confidence: f32,
    pub provenance: EventProvenance,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SignedAiEventEnvelope {
    pub schema_version: u8,
    pub event: AiEvent,
    pub issued_at_ms: i64,
    pub nonce: String,
    pub signature_hex: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiLiveTaskState {
    pub source: String,
    pub support_status: SourceSupportStatus,
    pub device_id: String,
    pub project_id: String,
    pub task_id: String,
    pub task_name: String,
    pub status: AiTaskStatus,
    pub started_at_utc: String,
    pub updated_at_utc: String,
    pub elapsed_seconds: u64,
    pub verified_progress: Option<f32>,
    pub latest_event_summary: String,
    pub latest_error: Option<String>,
    pub approval_requested: bool,
    pub verified_test_evidence: Option<String>,
    pub artifact_reference: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiSourceDescriptor {
    pub source_id: String,
    pub display_name: String,
    pub support_status: SourceSupportStatus,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ReplayRecord {
    event_id: String,
    nonce: String,
    issued_at_ms: i64,
    seen_at_ms: i64,
}

#[derive(Default)]
struct ReplayGuardState {
    records: VecDeque<ReplayRecord>,
    seen_event_ids: HashSet<String>,
    seen_nonces: HashSet<String>,
}

const MAX_CLOCK_SKEW_MS: i64 = 300_000;
const REPLAY_RETENTION_MS: i64 = MAX_CLOCK_SKEW_MS * 2 + 60_000;
const DEFAULT_MAX_ACTIVE_REPLAY_ENTRIES: usize = 65_536;

pub fn encode_canonical_f32_checked(
    val: f32,
    min_val: f32,
    max_val: f32,
    field: &str,
) -> Result<String, String> {
    if !val.is_finite() {
        return Err(format!("EVENT_REJECT_NON_FINITE_{field}"));
    }
    let bits = val.to_bits();
    if bits == 0x8000_0000 {
        return Err(format!("EVENT_REJECT_NEGATIVE_ZERO_{field}"));
    }
    if !(min_val..=max_val).contains(&val) {
        return Err(format!("EVENT_REJECT_OUT_OF_RANGE_{field}"));
    }
    Ok(format!("f32:{bits:08x}"))
}

fn build_canonical_v3_json_bytes(
    event: &AiEvent,
    schema_version: u8,
    issued_at_ms: i64,
    nonce: &str,
    progress_tag: Option<String>,
    confidence_tag: String,
) -> Result<Vec<u8>, String> {
    let canonical = serde_json::json!([
        "DAUVERSE_AI_EVENT_V3",
        schema_version,
        issued_at_ms,
        nonce,
        &event.event_id,
        &event.timestamp,
        &event.source,
        &event.device_id,
        &event.project_id,
        &event.task_id,
        &event.task_name,
        &event.event_type,
        &event.status,
        &event.severity,
        progress_tag,
        &event.summary,
        &event.artifact_reference,
        confidence_tag,
        [
            &event.provenance.adapter_type,
            event.provenance.evidence_verified,
            event.provenance.exit_code,
            &event.provenance.evidence_badge,
        ],
    ]);
    serde_json::to_vec(&canonical).map_err(|e| format!("CANONICAL_SERIALIZE_ERROR: {e}"))
}

pub fn canonical_signing_bytes_checked(
    event: &AiEvent,
    schema_version: u8,
    issued_at_ms: i64,
    nonce: &str,
) -> Result<Vec<u8>, String> {
    if schema_version != AI_EVENT_SCHEMA_V3 {
        return Err("EVENT_REJECT_UNSUPPORTED_SCHEMA_VERSION".to_owned());
    }
    let progress_tag = match event.progress {
        Some(p) => Some(encode_canonical_f32_checked(p, 0.0, 100.0, "PROGRESS")?),
        None => None,
    };
    let confidence_tag = encode_canonical_f32_checked(event.confidence, 0.0, 1.0, "CONFIDENCE")?;
    build_canonical_v3_json_bytes(
        event,
        schema_version,
        issued_at_ms,
        nonce,
        progress_tag,
        confidence_tag,
    )
}

pub fn canonical_signing_bytes(event: &AiEvent, issued_at_ms: i64, nonce: &str) -> Vec<u8> {
    let progress_tag = event.progress.map(|p| format!("f32:{:08x}", p.to_bits()));
    let confidence_tag = format!("f32:{:08x}", event.confidence.to_bits());
    build_canonical_v3_json_bytes(
        event,
        AI_EVENT_SCHEMA_V3,
        issued_at_ms,
        nonce,
        progress_tag,
        confidence_tag,
    )
    .unwrap_or_default()
}

pub fn sign_event_envelope(
    event: AiEvent,
    secret_key: &[u8],
    issued_at_ms: i64,
    nonce: String,
) -> SignedAiEventEnvelope {
    let payload = canonical_signing_bytes(&event, issued_at_ms, &nonce);
    let sig = hex::encode(hmac_sha256(secret_key, &payload));
    SignedAiEventEnvelope {
        schema_version: AI_EVENT_SCHEMA_V3,
        event,
        issued_at_ms,
        nonce,
        signature_hex: sig,
    }
}

pub fn validate_source_adapter_policy(ev: &AiEvent) -> Result<(), String> {
    let src = ev.source.trim().to_ascii_lowercase();
    let allowed = match src.as_str() {
        "claude_code" | "codex_cli" => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::OfficialHook | SourceSupportStatus::StructuredLogsReadOnly
        ),
        "build_qa_powershell" | "powershell_job" | "antigravity_cli" => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::ApprovedWrapperAdapter
                | SourceSupportStatus::StructuredLogsReadOnly
        ),
        "antigravity_desktop" | "antigravity_remote" | "antigravity" => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::StructuredLogsReadOnly
                | SourceSupportStatus::ApprovedWrapperAdapter
        ),
        "dauverse_ai_controller" => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::ExistingControllerEventsReadOnly
        ),
        "comfyui" => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::OfficialLocalHttpReadOnly
        ),
        "codex_desktop" => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::ReadOnlyProcessMonitor | SourceSupportStatus::Unknown
        ),
        "claude_desktop" => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::Unknown | SourceSupportStatus::StructuredLogsReadOnly
        ),
        _ => matches!(
            ev.provenance.adapter_type,
            SourceSupportStatus::Unknown | SourceSupportStatus::Unsupported
        ),
    };
    if !allowed {
        return Err(format!(
            "EVENT_REJECT_UNTRUSTED_SOURCE_ADAPTER_CLAIM: source '{}' cannot claim adapter {:?}",
            ev.source, ev.provenance.adapter_type
        ));
    }
    Ok(())
}

pub fn normalize_event_truthfulness(mut ev: AiEvent) -> AiEvent {
    ev.summary = redact_sensitive(&ev.summary);
    ev.confidence = ev.confidence.clamp(0.0, 1.0);

    if matches!(
        ev.provenance.adapter_type,
        SourceSupportStatus::Unknown
            | SourceSupportStatus::Unsupported
            | SourceSupportStatus::ReadOnlyProcessMonitor
    ) {
        ev.provenance.evidence_verified = false;
    }

    if matches!(
        ev.provenance.adapter_type,
        SourceSupportStatus::ApprovedWrapperAdapter
    ) && ev.status == AiTaskStatus::Completed
        && ev.provenance.exit_code != Some(0)
    {
        ev.provenance.evidence_verified = false;
    }

    if let Some(p) = ev.progress {
        if !p.is_finite() || !(0.0..=100.0).contains(&p) || !ev.provenance.evidence_verified {
            ev.progress = None;
        }
    }

    if !ev.provenance.evidence_verified {
        ev.provenance.evidence_badge = None;
    }

    if ev.event_type == AiEventType::ProcessExited {
        match ev.provenance.exit_code {
            Some(0) if !ev.provenance.evidence_verified => {
                ev.status = AiTaskStatus::Unknown;
                ev.severity = EventSeverity::Info;
                if !ev.summary.contains("[Unverified process exit]") {
                    ev.summary = format!(
                        "{} [Unverified process exit: exit=0 does not prove task completion]",
                        ev.summary
                    );
                }
            }
            Some(code) if code != 0 => {
                ev.status = AiTaskStatus::Failed;
                ev.severity = EventSeverity::High;
            }
            None => {
                ev.status = AiTaskStatus::Unknown;
            }
            _ => {}
        }
    }

    if ev.status == AiTaskStatus::Completed && !ev.provenance.evidence_verified {
        ev.status = AiTaskStatus::Unknown;
        ev.progress = None;
    }

    ev
}

fn load_replay_journal_strict(path: &Path) -> Result<ReplayGuardState, String> {
    match std::fs::symlink_metadata(path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            if let Some(parent) = path.parent() {
                check_no_symlink_or_reparse_component(parent)?;
                if parent.exists() {
                    std::fs::read_dir(parent).map_err(|dir_err| {
                        format!(
                            "REPLAY_JOURNAL_PARENT_UNREADABLE '{}': {dir_err}",
                            parent.display()
                        )
                    })?;
                }
            }
            return Ok(ReplayGuardState::default());
        }
        Err(e) => {
            return Err(format!(
                "REPLAY_JOURNAL_STAT_FAILED '{}': {e}",
                path.display()
            ));
        }
        Ok(_) => {}
    }

    let (mut file, expected_len) = open_no_follow_regular_file(path)?;
    let mut raw_bytes = Vec::with_capacity(expected_len as usize);
    file.read_to_end(&mut raw_bytes).map_err(|e| {
        format!(
            "REPLAY_JOURNAL_READ_FAILED '{}': {e}",
            path.display()
        )
    })?;
    let raw_str = std::str::from_utf8(&raw_bytes).map_err(|e| {
        format!(
            "REPLAY_JOURNAL_INVALID_UTF8 '{}': {e}",
            path.display()
        )
    })?;
    let records: Vec<ReplayRecord> = serde_json::from_str(raw_str).map_err(|e| {
        format!(
            "REPLAY_JOURNAL_PARSE_FAILED '{}': {e}",
            path.display()
        )
    })?;

    let mut guard = ReplayGuardState::default();
    let now_ms = chrono::Utc::now().timestamp_millis();
    for rec in records {
        if rec.event_id.trim().is_empty() || rec.nonce.trim().len() < 8 {
            return Err("REPLAY_JOURNAL_INVALID_RECORD: empty event_id or weak nonce".to_owned());
        }
        if now_ms.saturating_sub(rec.seen_at_ms) <= REPLAY_RETENTION_MS
            || (now_ms - rec.issued_at_ms).abs() <= MAX_CLOCK_SKEW_MS
        {
            if !guard.seen_event_ids.insert(rec.event_id.clone())
                || !guard.seen_nonces.insert(rec.nonce.clone())
            {
                return Err("REPLAY_JOURNAL_DUPLICATE_ACTIVE_RECORD".to_owned());
            }
            guard.records.push_back(rec);
        }
    }
    Ok(guard)
}

pub struct AiEventBridge {
    hmac_secret: Mutex<Vec<u8>>,
    replay_guard: Mutex<ReplayGuardState>,
    replay_journal_path: Option<PathBuf>,
    journal_corrupted_fail_closed: AtomicBool,
    journal_error_detail: Mutex<Option<String>>,
    max_active_replay_entries: usize,
    event_log: Mutex<VecDeque<AiEvent>>,
    live_tasks: Mutex<HashMap<String, AiLiveTaskState>>,
    rejected_spoof_or_replay: Mutex<u64>,
}

impl AiEventBridge {
    pub fn new(hmac_secret: Vec<u8>) -> Self {
        Self::with_persistence_and_limits(hmac_secret, None, DEFAULT_MAX_ACTIVE_REPLAY_ENTRIES)
    }

    pub fn with_persistence_and_limits(
        hmac_secret: Vec<u8>,
        replay_journal_path: Option<PathBuf>,
        max_active_replay_entries: usize,
    ) -> Self {
        let mut guard = ReplayGuardState::default();
        let mut corrupted = false;
        let mut err_detail = None;

        if let Some(ref p) = replay_journal_path {
            match load_replay_journal_strict(p) {
                Ok(loaded) => {
                    guard = loaded;
                }
                Err(e) => {
                    corrupted = true;
                    err_detail = Some(e);
                }
            }
        }

        Self {
            hmac_secret: Mutex::new(hmac_secret),
            replay_guard: Mutex::new(guard),
            replay_journal_path,
            journal_corrupted_fail_closed: AtomicBool::new(corrupted),
            journal_error_detail: Mutex::new(err_detail),
            max_active_replay_entries: max_active_replay_entries.max(1),
            event_log: Mutex::new(VecDeque::with_capacity(512)),
            live_tasks: Mutex::new(HashMap::new()),
            rejected_spoof_or_replay: Mutex::new(0),
        }
    }

    pub fn is_replay_journal_healthy(&self) -> bool {
        !self.journal_corrupted_fail_closed.load(Ordering::SeqCst)
    }

    pub fn replay_journal_error(&self) -> Option<String> {
        self.journal_error_detail.lock().unwrap().clone()
    }

    pub fn supported_sources_catalog() -> Vec<AiSourceDescriptor> {
        vec![
            AiSourceDescriptor {
                source_id: "claude_code".to_owned(),
                display_name: "Claude Code CLI".to_owned(),
                support_status: SourceSupportStatus::OfficialHook,
                notes: "Official Claude Code Stop/Notification/SubagentStop JSON hook adapter.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "claude_desktop".to_owned(),
                display_name: "Claude Desktop".to_owned(),
                support_status: SourceSupportStatus::Unknown,
                notes: "No official completion webhook; reported UNKNOWN unless read-only MCP/log adapter is configured (never reads cookies/tokens).".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "codex_cli".to_owned(),
                display_name: "Codex CLI".to_owned(),
                support_status: SourceSupportStatus::OfficialHook,
                notes: "Official Codex CLI notify hook adapter.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "codex_desktop".to_owned(),
                display_name: "Codex Desktop".to_owned(),
                support_status: SourceSupportStatus::ReadOnlyProcessMonitor,
                notes: "Read-only process/log observer; reports UNKNOWN when structured completion event is absent.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "antigravity_desktop".to_owned(),
                display_name: "Antigravity Desktop".to_owned(),
                support_status: SourceSupportStatus::StructuredLogsReadOnly,
                notes: "Strictly read-only status interface; zero modification or workspace contention with DAUVERSE AI.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "antigravity_cli".to_owned(),
                display_name: "Antigravity CLI".to_owned(),
                support_status: SourceSupportStatus::ApprovedWrapperAdapter,
                notes: "Supported via approved read-only wrapper / structured output.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "antigravity_remote".to_owned(),
                display_name: "Antigravity Remote Agent".to_owned(),
                support_status: SourceSupportStatus::StructuredLogsReadOnly,
                notes: "Structured checkpoint/status reader.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "dauverse_ai_controller".to_owned(),
                display_name: "DAUVERSE AI Controller".to_owned(),
                support_status: SourceSupportStatus::ExistingControllerEventsReadOnly,
                notes: "Consumes existing Controller events read-only; never creates a second Controller.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "comfyui".to_owned(),
                display_name: "ComfyUI Render Engine".to_owned(),
                support_status: SourceSupportStatus::OfficialLocalHttpReadOnly,
                notes: "Read-only localhost /queue and /history observer for video/image render jobs.".to_owned(),
            },
            AiSourceDescriptor {
                source_id: "build_qa_powershell".to_owned(),
                display_name: "Build / QA / Render / PowerShell Jobs".to_owned(),
                support_status: SourceSupportStatus::ApprovedWrapperAdapter,
                notes: "Signed wrapper scripts emitting verified exit codes and test counts.".to_owned(),
            },
        ]
    }

    pub fn rotate_secret(&self, new_secret: Vec<u8>) -> Result<(), String> {
        if new_secret.len() < 16 {
            return Err("HMAC secret must be at least 16 bytes".to_owned());
        }
        let mut g = self.hmac_secret.lock().unwrap();
        *g = new_secret;
        Ok(())
    }

    pub fn sign_with_runtime_secret(
        &self,
        event: AiEvent,
        issued_at_ms: i64,
        nonce: String,
    ) -> SignedAiEventEnvelope {
        let secret = self.hmac_secret.lock().unwrap();
        sign_event_envelope(event, &secret, issued_at_ms, nonce)
    }

    pub fn ingest_signed_envelope(
        &self,
        envelope: SignedAiEventEnvelope,
        now_ms: i64,
    ) -> Result<AiEvent, String> {
        if self.journal_corrupted_fail_closed.load(Ordering::SeqCst) {
            self.bump_rejected();
            let detail = self
                .journal_error_detail
                .lock()
                .unwrap()
                .clone()
                .unwrap_or_else(|| "corrupted or unreadable replay journal".to_owned());
            return Err(format!(
                "EVENT_REJECT_REPLAY_JOURNAL_CORRUPTED_FAIL_CLOSED: {detail}"
            ));
        }
        if envelope.schema_version != AI_EVENT_SCHEMA_V3 {
            self.bump_rejected();
            return Err("EVENT_REJECT_UNSUPPORTED_SCHEMA_VERSION".to_owned());
        }
        if envelope.event.event_id.trim().is_empty() || envelope.nonce.trim().len() < 8 {
            self.bump_rejected();
            return Err("EVENT_REJECT_EMPTY_ID_OR_WEAK_NONCE".to_owned());
        }
        if (now_ms - envelope.issued_at_ms).abs() > MAX_CLOCK_SKEW_MS {
            self.bump_rejected();
            return Err("EVENT_REJECT_TIMESTAMP_OUTSIDE_WINDOW".to_owned());
        }

        let payload = match canonical_signing_bytes_checked(
            &envelope.event,
            envelope.schema_version,
            envelope.issued_at_ms,
            &envelope.nonce,
        ) {
            Ok(bytes) => bytes,
            Err(e) => {
                self.bump_rejected();
                return Err(e);
            }
        };

        let Ok(provided_sig) = hex::decode(envelope.signature_hex.trim()) else {
            self.bump_rejected();
            return Err("EVENT_REJECT_MALFORMED_SIGNATURE".to_owned());
        };
        let expected_sig = {
            let secret = self.hmac_secret.lock().unwrap();
            hmac_sha256(&secret, &payload)
        };
        if !constant_time_eq(&expected_sig, &provided_sig) {
            self.bump_rejected();
            return Err("EVENT_REJECT_INVALID_HMAC_SPOOFED".to_owned());
        }

        if let Err(policy_err) = validate_source_adapter_policy(&envelope.event) {
            self.bump_rejected();
            return Err(policy_err);
        }

        {
            let mut guard = self.replay_guard.lock().unwrap();
            while let Some(front) = guard.records.front() {
                if now_ms.saturating_sub(front.seen_at_ms) > REPLAY_RETENTION_MS
                    && (now_ms - front.issued_at_ms).abs() > MAX_CLOCK_SKEW_MS
                {
                    if let Some(expired) = guard.records.pop_front() {
                        guard.seen_event_ids.remove(&expired.event_id);
                        guard.seen_nonces.remove(&expired.nonce);
                    }
                } else {
                    break;
                }
            }

            if guard.seen_event_ids.contains(&envelope.event.event_id)
                || guard.seen_nonces.contains(&envelope.nonce)
            {
                self.bump_rejected();
                return Err("EVENT_REJECT_REPLAY_DETECTED".to_owned());
            }

            if guard.records.len() >= self.max_active_replay_entries {
                self.bump_rejected();
                return Err("EVENT_REJECT_REPLAY_CACHE_SATURATED".to_owned());
            }

            let rec = ReplayRecord {
                event_id: envelope.event.event_id.clone(),
                nonce: envelope.nonce.clone(),
                issued_at_ms: envelope.issued_at_ms,
                seen_at_ms: now_ms,
            };
            guard.seen_event_ids.insert(rec.event_id.clone());
            guard.seen_nonces.insert(rec.nonce.clone());
            guard.records.push_back(rec);

            if let Some(ref path) = self.replay_journal_path {
                let snapshot: Vec<&ReplayRecord> = guard.records.iter().collect();
                let bytes = match serde_json::to_vec(&snapshot) {
                    Ok(b) => b,
                    Err(e) => {
                        if let Some(rolled) = guard.records.pop_back() {
                            guard.seen_event_ids.remove(&rolled.event_id);
                            guard.seen_nonces.remove(&rolled.nonce);
                        }
                        self.bump_rejected();
                        return Err(format!("EVENT_REJECT_REPLAY_SERIALIZE_FAILED: {e}"));
                    }
                };
                if let Err(e) = write_atomic_bytes(path, &bytes, true) {
                    if let Some(rolled) = guard.records.pop_back() {
                        guard.seen_event_ids.remove(&rolled.event_id);
                        guard.seen_nonces.remove(&rolled.nonce);
                    }
                    *self.journal_error_detail.lock().unwrap() = Some(e.clone());
                    self.bump_rejected();
                    return Err(format!("EVENT_REJECT_REPLAY_PERSIST_FAILED: {e}"));
                }
            }
        }

        let normalized = normalize_event_truthfulness(envelope.event);
        self.record_verified_event(&normalized);
        Ok(normalized)
    }

    pub fn ingest_structured_jsonl_file_readonly(&self, path: &Path) -> Result<usize, String> {
        let (mut file, _len) = open_no_follow_regular_file(path)?;
        let mut content = String::new();
        file.read_to_string(&mut content)
            .map_err(|e| format!("failed reading structured event log: {e}"))?;
        let mut count = 0usize;
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let mut parsed: AiEvent = serde_json::from_str(trimmed)
                .map_err(|e| format!("invalid AiEvent JSONL line: {e}"))?;
            if matches!(
                parsed.provenance.adapter_type,
                SourceSupportStatus::OfficialHook | SourceSupportStatus::ApprovedWrapperAdapter
            ) {
                parsed.provenance.adapter_type = SourceSupportStatus::StructuredLogsReadOnly;
                parsed.provenance.evidence_verified = false;
            }
            let normalized = normalize_event_truthfulness(parsed);
            self.record_verified_event(&normalized);
            count += 1;
        }
        Ok(count)
    }

    fn record_verified_event(&self, ev: &AiEvent) {
        {
            let mut log = self.event_log.lock().unwrap();
            if log.len() >= 512 {
                log.pop_front();
            }
            log.push_back(ev.clone());
        }

        let task_key = format!("{}::{}::{}", ev.device_id, ev.source, ev.task_id);
        let mut tasks = self.live_tasks.lock().unwrap();
        let entry = tasks.entry(task_key).or_insert_with(|| AiLiveTaskState {
            source: ev.source.clone(),
            support_status: ev.provenance.adapter_type,
            device_id: ev.device_id.clone(),
            project_id: ev.project_id.clone(),
            task_id: ev.task_id.clone(),
            task_name: ev.task_name.clone(),
            status: ev.status,
            started_at_utc: ev.timestamp.clone(),
            updated_at_utc: ev.timestamp.clone(),
            elapsed_seconds: 0,
            verified_progress: ev.progress,
            latest_event_summary: ev.summary.clone(),
            latest_error: None,
            approval_requested: false,
            verified_test_evidence: None,
            artifact_reference: ev.artifact_reference.clone(),
        });

        entry.status = ev.status;
        entry.support_status = ev.provenance.adapter_type;
        entry.updated_at_utc = ev.timestamp.clone();
        if let (Ok(start), Ok(now)) = (
            chrono::DateTime::parse_from_rfc3339(&entry.started_at_utc),
            chrono::DateTime::parse_from_rfc3339(&ev.timestamp),
        ) {
            let diff = (now - start).num_seconds();
            if diff >= 0 {
                entry.elapsed_seconds = diff as u64;
            }
        }
        entry.verified_progress = ev.progress;
        entry.latest_event_summary = ev.summary.clone();
        entry.approval_requested = ev.status == AiTaskStatus::WaitingApproval
            || ev.event_type == AiEventType::ApprovalRequired;
        if matches!(
            ev.event_type,
            AiEventType::Error | AiEventType::BuildFailed | AiEventType::QaFailed
        ) || ev.status == AiTaskStatus::Failed
        {
            entry.latest_error = Some(ev.summary.clone());
        }
        if ev.provenance.evidence_verified {
            if let Some(badge) = &ev.provenance.evidence_badge {
                entry.verified_test_evidence = Some(badge.clone());
            }
        }
        if ev.artifact_reference.is_some() {
            entry.artifact_reference = ev.artifact_reference.clone();
        }
    }

    pub fn live_tasks(&self) -> Vec<AiLiveTaskState> {
        let map = self.live_tasks.lock().unwrap();
        let mut list: Vec<AiLiveTaskState> = map.values().cloned().collect();
        list.sort_by(|a, b| b.updated_at_utc.cmp(&a.updated_at_utc));
        list
    }

    pub fn recent_events(&self) -> Vec<AiEvent> {
        self.event_log.lock().unwrap().iter().cloned().collect()
    }

    pub fn active_counts(&self) -> (usize, usize, bool) {
        let map = self.live_tasks.lock().unwrap();
        let running = map
            .values()
            .filter(|t| t.status == AiTaskStatus::Running)
            .count();
        let waiting_approval = map
            .values()
            .filter(|t| t.status == AiTaskStatus::WaitingApproval || t.approval_requested)
            .count();
        let comfy_rendering = map.values().any(|t| {
            t.source.eq_ignore_ascii_case("comfyui") && t.status == AiTaskStatus::Running
        });
        (running, waiting_approval, comfy_rendering)
    }

    pub fn rejected_security_count(&self) -> u64 {
        *self.rejected_spoof_or_replay.lock().unwrap()
    }

    fn bump_rejected(&self) {
        let mut g = self.rejected_spoof_or_replay.lock().unwrap();
        *g += 1;
    }

    pub fn spawn_loopback_http_gateway(
        bridge: Arc<Self>,
        bind_port: u16,
        stop_flag: Arc<AtomicBool>,
    ) -> Result<(u16, std::thread::JoinHandle<()>), String> {
        Self::spawn_loopback_http_gateway_with_sink(bridge, bind_port, stop_flag, None)
    }

    pub fn spawn_loopback_http_gateway_with_sink(
        bridge: Arc<Self>,
        bind_port: u16,
        stop_flag: Arc<AtomicBool>,
        on_accepted: Option<Arc<dyn Fn(&AiEvent, i64) + Send + Sync>>,
    ) -> Result<(u16, std::thread::JoinHandle<()>), String> {
        let listener = TcpListener::bind(("127.0.0.1", bind_port))
            .map_err(|e| format!("failed binding loopback AI Event Bridge: {e}"))?;
        listener
            .set_nonblocking(true)
            .map_err(|e| format!("failed setting nonblocking listener: {e}"))?;
        let actual_port = listener
            .local_addr()
            .map_err(|e| format!("failed reading local_addr: {e}"))?
            .port();

        let handle = std::thread::spawn(move || {
            while !stop_flag.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _peer)) => {
                        let _ = Self::handle_http_conn(stream, &bridge, on_accepted.as_deref());
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        std::thread::sleep(Duration::from_millis(15));
                    }
                    Err(_) => break,
                }
            }
        });

        Ok((actual_port, handle))
    }

    fn read_full_http_request(stream: &mut TcpStream) -> Result<(String, Vec<u8>), String> {
        let mut raw = Vec::with_capacity(4096);
        let mut chunk = [0u8; 4096];
        let mut header_end: Option<usize> = None;
        let mut content_len: Option<usize> = None;

        for _ in 0..32 {
            match stream.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => {
                    raw.extend_from_slice(&chunk[..n]);
                    if raw.len() > 256 * 1024 {
                        return Err("PAYLOAD_TOO_LARGE".to_owned());
                    }
                    if header_end.is_none() {
                        if let Some(pos) = raw.windows(4).position(|w| w == b"\r\n\r\n") {
                            header_end = Some(pos);
                            let hdr_str = std::str::from_utf8(&raw[..pos])
                                .map_err(|_| "INVALID_UTF8_HTTP_HEADERS".to_owned())?;
                            for line in hdr_str.lines() {
                                if let Some((k, v)) = line.split_once(':') {
                                    if k.trim().eq_ignore_ascii_case("content-length") {
                                        let parsed = v
                                            .trim()
                                            .parse::<usize>()
                                            .map_err(|_| "INVALID_CONTENT_LENGTH".to_owned())?;
                                        content_len = Some(parsed);
                                    }
                                }
                            }
                        }
                    }
                    if let Some(pos) = header_end {
                        let expected_body = content_len.unwrap_or(0);
                        if raw.len() >= pos + 4 + expected_body {
                            break;
                        }
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(5));
                }
                Err(e) => return Err(format!("read error: {e}")),
            }
        }

        let Some(pos) = header_end else {
            return Err("BAD_HTTP_HEADERS".to_owned());
        };
        let header_part = std::str::from_utf8(&raw[..pos])
            .map_err(|_| "INVALID_UTF8_HTTP_HEADERS".to_owned())?
            .to_owned();
        let body_start = pos + 4;
        let body_bytes = if let Some(expected_len) = content_len {
            if raw.len() < body_start + expected_len {
                return Err("TRUNCATED_HTTP_BODY".to_owned());
            }
            raw[body_start..body_start + expected_len].to_vec()
        } else {
            raw[body_start..].to_vec()
        };
        Ok((header_part, body_bytes))
    }

    fn handle_http_conn(
        mut stream: TcpStream,
        bridge: &Self,
        on_accepted: Option<&(dyn Fn(&AiEvent, i64) + Send + Sync)>,
    ) -> Result<(), String> {
        stream.set_nonblocking(false).ok();
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .ok();
        let (header_part, body_bytes) = match Self::read_full_http_request(&mut stream) {
            Ok(v) => v,
            Err(e) => {
                return Self::write_json_resp(
                    &mut stream,
                    400,
                    &serde_json::json!({"ok": false, "error": e}).to_string(),
                );
            }
        };

        if header_part.starts_with("GET /v1/health") {
            let (running, waiting, comfy) = bridge.active_counts();
            let healthy = bridge.is_replay_journal_healthy();
            return Self::write_json_resp(
                &mut stream,
                if healthy { 200 } else { 503 },
                &serde_json::json!({
                    "ok": healthy,
                    "service": "DAUVERSE_AI_EVENT_BRIDGE",
                    "replay_journal_healthy": healthy,
                    "running": running,
                    "waiting_approval": waiting,
                    "comfyui_rendering": comfy,
                })
                .to_string(),
            );
        }

        if !header_part.starts_with("POST /v1/events") {
            return Self::write_json_resp(&mut stream, 404, r#"{"ok":false,"error":"NOT_FOUND"}"#);
        }

        let body_str = match std::str::from_utf8(&body_bytes) {
            Ok(s) => s,
            Err(e) => {
                bridge.bump_rejected();
                return Self::write_json_resp(
                    &mut stream,
                    400,
                    &serde_json::json!({"ok": false, "error": format!("INVALID_UTF8_PAYLOAD: {e}")})
                        .to_string(),
                );
            }
        };
        let env: SignedAiEventEnvelope = match serde_json::from_str(body_str.trim()) {
            Ok(v) => v,
            Err(e) => {
                bridge.bump_rejected();
                return Self::write_json_resp(
                    &mut stream,
                    400,
                    &serde_json::json!({"ok": false, "error": format!("INVALID_JSON: {e}")})
                        .to_string(),
                );
            }
        };

        let now_ms = chrono::Utc::now().timestamp_millis();
        match bridge.ingest_signed_envelope(env, now_ms) {
            Ok(ev) => {
                if let Some(cb) = on_accepted {
                    cb(&ev, now_ms);
                }
                Self::write_json_resp(
                    &mut stream,
                    200,
                    &serde_json::json!({"ok": true, "event_id": ev.event_id, "status": ev.status})
                        .to_string(),
                )
            }
            Err(err) => {
                let code = if err.starts_with("EVENT_REJECT_REPLAY_CACHE_SATURATED") {
                    429
                } else if err.starts_with("EVENT_REJECT_REPLAY_JOURNAL_CORRUPTED_FAIL_CLOSED")
                    || err.starts_with("EVENT_REJECT_REPLAY_PERSIST_FAILED")
                {
                    503
                } else {
                    401
                };
                Self::write_json_resp(
                    &mut stream,
                    code,
                    &serde_json::json!({"ok": false, "error": err}).to_string(),
                )
            }
        }
    }

    fn write_json_resp(stream: &mut TcpStream, code: u16, body: &str) -> Result<(), String> {
        let status_text = match code {
            200 => "OK",
            400 => "Bad Request",
            401 => "Unauthorized",
            429 => "Too Many Requests",
            503 => "Service Unavailable",
            _ => "Not Found",
        };
        let resp = format!(
            "HTTP/1.1 {code} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream
            .write_all(resp.as_bytes())
            .map_err(|e| format!("write error: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_event(
        event_id: &str,
        event_type: AiEventType,
        status: AiTaskStatus,
        verified: bool,
    ) -> AiEvent {
        AiEvent {
            event_id: event_id.to_owned(),
            timestamp: "2026-11-26T00:00:00Z".to_owned(),
            source: "codex_cli".to_owned(),
            device_id: "HOME-RTX3060".to_owned(),
            project_id: "DAUVERSE-FT004".to_owned(),
            task_id: "FT004".to_owned(),
            task_name: "Fast Track 004 Verification".to_owned(),
            event_type,
            status,
            severity: EventSeverity::Success,
            progress: Some(100.0),
            summary: "Completed FT004 test suite".to_owned(),
            artifact_reference: Some("REPORTS/ft004.json".to_owned()),
            confidence: 1.0,
            provenance: EventProvenance {
                adapter_type: SourceSupportStatus::OfficialHook,
                evidence_verified: verified,
                exit_code: Some(0),
                evidence_badge: Some("128/128 tests PASS".to_owned()),
            },
        }
    }

    #[test]
    fn rejects_spoofing_replay_and_fake_completion_on_process_exit() {
        let secret = b"dauverse-event-bridge-hmac-secret-key-2026".to_vec();
        let bridge = AiEventBridge::new(secret.clone());
        let now_ms = 1_795_537_500_000i64;

        let ev = sample_event("evt-001", AiEventType::QaPassed, AiTaskStatus::Completed, true);
        let signed = sign_event_envelope(ev, &secret, now_ms, "nonce-0001".to_owned());
        assert_eq!(signed.schema_version, AI_EVENT_SCHEMA_V3);
        let accepted = bridge.ingest_signed_envelope(signed.clone(), now_ms).unwrap();
        assert_eq!(accepted.status, AiTaskStatus::Completed);
        assert_eq!(
            accepted.provenance.evidence_badge.as_deref(),
            Some("128/128 tests PASS")
        );

        let replay_err = bridge.ingest_signed_envelope(signed, now_ms).unwrap_err();
        assert_eq!(replay_err, "EVENT_REJECT_REPLAY_DETECTED");

        let spoof_ev = sample_event("evt-002", AiEventType::TaskCompleted, AiTaskStatus::Completed, true);
        let bad_env = sign_event_envelope(
            spoof_ev,
            b"wrong-attacker-key-00000000",
            now_ms,
            "nonce-0002".to_owned(),
        );
        let spoof_err = bridge.ingest_signed_envelope(bad_env, now_ms).unwrap_err();
        assert_eq!(spoof_err, "EVENT_REJECT_INVALID_HMAC_SPOOFED");

        let unverified_exit = sample_event(
            "evt-003",
            AiEventType::ProcessExited,
            AiTaskStatus::Completed,
            false,
        );
        let exit_env = sign_event_envelope(unverified_exit, &secret, now_ms, "nonce-0003".to_owned());
        let normalized = bridge.ingest_signed_envelope(exit_env, now_ms).unwrap();
        assert_eq!(normalized.status, AiTaskStatus::Unknown);
        assert!(normalized.progress.is_none());
        assert!(normalized.provenance.evidence_badge.is_none());
    }

    #[test]
    fn f01_mutating_any_envelope_or_provenance_field_breaks_hmac_and_blocks_fake_completion() {
        let secret = b"f01-complete-field-coverage-hmac-key-2026".to_vec();
        let bridge = AiEventBridge::new(secret.clone());
        let now_ms = 1_795_540_000_000i64;

        let base_ev = sample_event("f01-base", AiEventType::TaskProgress, AiTaskStatus::Unknown, false);
        let base_signed = sign_event_envelope(base_ev, &secret, now_ms, "nonce-f01-base".to_owned());

        for legacy_ver in [0u8, 1u8, 2u8] {
            let mut legacy = base_signed.clone();
            legacy.schema_version = legacy_ver;
            assert_eq!(
                bridge.ingest_signed_envelope(legacy, now_ms).unwrap_err(),
                "EVENT_REJECT_UNSUPPORTED_SCHEMA_VERSION"
            );
        }

        let mutators: Vec<(&str, Box<dyn Fn(&mut SignedAiEventEnvelope)>)> = vec![
            ("task_name", Box::new(|e| e.event.task_name = "Hijacked Task Name".to_owned())),
            ("severity", Box::new(|e| e.event.severity = EventSeverity::Critical)),
            ("progress", Box::new(|e| e.event.progress = Some(50.0))),
            (
                "progress_same_4dec_bucket_below_100",
                Box::new(|e| e.event.progress = Some(f32::from_bits(100.0_f32.to_bits() - 1))),
            ),
            ("summary", Box::new(|e| e.event.summary = "Tampered summary text".to_owned())),
            ("artifact_reference", Box::new(|e| e.event.artifact_reference = Some("evil.exe".to_owned()))),
            ("confidence", Box::new(|e| e.event.confidence = 0.25)),
            (
                "confidence_same_4dec_bucket_neighbor",
                Box::new(|e| e.event.confidence = f32::from_bits(1.0_f32.to_bits() - 1)),
            ),
            ("provenance.adapter_type", Box::new(|e| e.event.provenance.adapter_type = SourceSupportStatus::Unknown)),
            ("provenance.evidence_verified", Box::new(|e| e.event.provenance.evidence_verified = true)),
            ("provenance.exit_code", Box::new(|e| e.event.provenance.exit_code = Some(1))),
            ("provenance.evidence_badge", Box::new(|e| e.event.provenance.evidence_badge = Some("FORGED PASS".to_owned()))),
            ("event_id", Box::new(|e| e.event.event_id = "f01-other-id".to_owned())),
            ("project_id", Box::new(|e| e.event.project_id = "OTHER-PROJ".to_owned())),
            ("status", Box::new(|e| e.event.status = AiTaskStatus::Completed)),
            ("issued_at_ms", Box::new(|e| e.issued_at_ms += 1)),
            ("nonce", Box::new(|e| e.nonce = "nonce-f01-tampered".to_owned())),
        ];

        for (field_name, mutate) in mutators {
            let mut tampered = base_signed.clone();
            mutate(&mut tampered);
            let err = bridge.ingest_signed_envelope(tampered, now_ms).unwrap_err();
            assert_eq!(
                err, "EVENT_REJECT_INVALID_HMAC_SPOOFED",
                "mutation on {field_name} was not rejected by HMAC"
            );
        }

        // Exact Codex Re-QA F01 counterexample: 100.0_f32 (0x42c80000) vs 100.000008_f32 (0x42c80001)
        let ev_100 = sample_event("f01-100", AiEventType::TaskCompleted, AiTaskStatus::Completed, true);
        let mut ev_over_100 = ev_100.clone();
        ev_over_100.progress = Some(f32::from_bits(100.0_f32.to_bits() + 1));
        assert_ne!(
            canonical_signing_bytes(&ev_100, now_ms, "nonce-f01-100"),
            canonical_signing_bytes(&ev_over_100, now_ms, "nonce-f01-100")
        );
        let mut swapped_over_100 = sign_event_envelope(ev_100, &secret, now_ms, "nonce-f01-100".to_owned());
        swapped_over_100.event.progress = Some(f32::from_bits(100.0_f32.to_bits() + 1));
        assert_eq!(
            bridge.ingest_signed_envelope(swapped_over_100, now_ms).unwrap_err(),
            "EVENT_REJECT_OUT_OF_RANGE_PROGRESS"
        );

        // Negative zero (-0.0_f32), NaN, Inf, and out-of-range floats are rejected even with valid key
        let mut neg_zero = sample_event("f01-neg0", AiEventType::TaskProgress, AiTaskStatus::Running, true);
        neg_zero.progress = Some(-0.0_f32);
        let neg_zero_env = sign_event_envelope(neg_zero, &secret, now_ms, "nonce-neg0-001".to_owned());
        assert_eq!(
            bridge.ingest_signed_envelope(neg_zero_env, now_ms).unwrap_err(),
            "EVENT_REJECT_NEGATIVE_ZERO_PROGRESS"
        );

        let mut bad_conf = sample_event("f01-conf", AiEventType::TaskProgress, AiTaskStatus::Running, true);
        bad_conf.confidence = 1.0001_f32;
        let bad_conf_env = sign_event_envelope(bad_conf, &secret, now_ms, "nonce-conf-001".to_owned());
        assert_eq!(
            bridge.ingest_signed_envelope(bad_conf_env, now_ms).unwrap_err(),
            "EVENT_REJECT_OUT_OF_RANGE_CONFIDENCE"
        );

        // Unknown / injected JSON fields and missing schema_version must fail deserialization
        let mut val_json = serde_json::to_value(&base_signed).unwrap();
        val_json["injected_extra"] = serde_json::json!(true);
        assert!(serde_json::from_value::<SignedAiEventEnvelope>(val_json).is_err());

        let mut missing_ver = serde_json::to_value(&base_signed).unwrap();
        missing_ver.as_object_mut().unwrap().remove("schema_version");
        assert!(serde_json::from_value::<SignedAiEventEnvelope>(missing_ver).is_err());

        // Unicode (Vietnamese + Emoji + quotes + delimiters) round-trips deterministically
        let mut uni_ev = sample_event("f01-unicode", AiEventType::QaPassed, AiTaskStatus::Completed, true);
        uni_ev.summary = "Kiểm thử Tiếng Việt chuẩn 🚀 | \"quoted\" \\ backslash".to_owned();
        let uni_env = sign_event_envelope(uni_ev, &secret, now_ms, "nonce-unicode-01".to_owned());
        let uni_out = bridge.ingest_signed_envelope(uni_env, now_ms).unwrap();
        assert!(uni_out.summary.contains("Kiểm thử Tiếng Việt chuẩn 🚀"));

        let mut ev_delim_a = sample_event("delim-1", AiEventType::TaskCompleted, AiTaskStatus::Completed, true);
        ev_delim_a.project_id = "proj|alpha".to_owned();
        ev_delim_a.task_id = "task\"1".to_owned();
        let mut ev_delim_b = ev_delim_a.clone();
        ev_delim_b.project_id = "proj".to_owned();
        ev_delim_b.task_id = "alpha|task\"1".to_owned();
        assert_ne!(
            canonical_signing_bytes(&ev_delim_a, now_ms, "nonce-delim-01"),
            canonical_signing_bytes(&ev_delim_b, now_ms, "nonce-delim-01")
        );

        let mut rogue_src = sample_event("f01-rogue-src", AiEventType::TaskCompleted, AiTaskStatus::Completed, true);
        rogue_src.source = "claude_desktop".to_owned();
        rogue_src.provenance.adapter_type = SourceSupportStatus::OfficialHook;
        let rogue_env = sign_event_envelope(rogue_src, &secret, now_ms, "nonce-rogue-src".to_owned());
        assert!(bridge
            .ingest_signed_envelope(rogue_env, now_ms)
            .unwrap_err()
            .starts_with("EVENT_REJECT_UNTRUSTED_SOURCE_ADAPTER_CLAIM"));
    }

    #[test]
    fn f09_replay_protection_survives_above_2048_burst_restart_corrupt_journal_and_write_faults() {
        let secret = b"f09-replay-window-and-ceiling-secret-2026".to_vec();
        let now_ms = chrono::Utc::now().timestamp_millis();

        let burst_bridge = AiEventBridge::new(secret.clone());
        let first_ev = sample_event("burst-0", AiEventType::CommandCompleted, AiTaskStatus::Completed, true);
        let first_env = sign_event_envelope(first_ev, &secret, now_ms, "nonce-burst-0000".to_owned());
        burst_bridge.ingest_signed_envelope(first_env.clone(), now_ms).unwrap();
        for i in 1..2_300 {
            let ev = sample_event(&format!("burst-{i}"), AiEventType::TaskProgress, AiTaskStatus::Running, true);
            let env = sign_event_envelope(ev, &secret, now_ms + 10, format!("nonce-burst-{i:05}"));
            burst_bridge.ingest_signed_envelope(env, now_ms + 10).unwrap();
        }
        assert_eq!(
            burst_bridge.ingest_signed_envelope(first_env, now_ms + 1_000).unwrap_err(),
            "EVENT_REJECT_REPLAY_DETECTED"
        );

        let journal_dir = std::env::temp_dir().join(format!("dv_replay_dir_{}", uuid::Uuid::new_v4()));
        let journal = journal_dir.join("bridge_replay_journal.json");
        let capped = AiEventBridge::with_persistence_and_limits(secret.clone(), Some(journal.clone()), 3);
        let mut first_capped_env = None;
        for i in 0..3 {
            let ev = sample_event(&format!("cap-{i}"), AiEventType::CommandCompleted, AiTaskStatus::Completed, true);
            let env = sign_event_envelope(ev, &secret, now_ms, format!("nonce-cap-{i:04}"));
            if i == 0 {
                first_capped_env = Some(env.clone());
            }
            capped.ingest_signed_envelope(env, now_ms).unwrap();
        }
        let fourth_ev = sample_event("cap-overflow", AiEventType::CommandCompleted, AiTaskStatus::Completed, true);
        let fourth_env = sign_event_envelope(fourth_ev, &secret, now_ms, "nonce-cap-over".to_owned());
        assert_eq!(
            capped.ingest_signed_envelope(fourth_env, now_ms + 500).unwrap_err(),
            "EVENT_REJECT_REPLAY_CACHE_SATURATED"
        );

        let captured_first = first_capped_env.unwrap();
        let restarted = AiEventBridge::with_persistence_and_limits(secret.clone(), Some(journal.clone()), 3);
        assert_eq!(
            restarted
                .ingest_signed_envelope(captured_first.clone(), now_ms + 1_000)
                .unwrap_err(),
            "EVENT_REJECT_REPLAY_DETECTED"
        );

        // Corrupt existing journal on disk -> restarted bridge MUST fail closed and reject replay + new events!
        std::fs::write(&journal, b"{corrupted-json").unwrap();
        let corrupted_bridge = AiEventBridge::with_persistence_and_limits(secret.clone(), Some(journal.clone()), 16);
        assert!(!corrupted_bridge.is_replay_journal_healthy());
        assert!(corrupted_bridge
            .ingest_signed_envelope(captured_first, now_ms + 2_000)
            .unwrap_err()
            .starts_with("EVENT_REJECT_REPLAY_JOURNAL_CORRUPTED_FAIL_CLOSED"));

        // Invalid UTF-8 in existing journal -> fail closed!
        std::fs::write(&journal, [0xFFu8, 0xFE, 0xFD]).unwrap();
        let bad_utf8_bridge = AiEventBridge::with_persistence_and_limits(secret.clone(), Some(journal.clone()), 16);
        assert!(!bad_utf8_bridge.is_replay_journal_healthy());

        // Write failure during ingest (journal path replaced by directory) -> fail closed and rollback in-memory record!
        let write_fault_dir = std::env::temp_dir().join(format!("dv_replay_wf_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&write_fault_dir).unwrap();
        let wf_journal = write_fault_dir.join("bridge_replay_journal.json");
        let wf_bridge = AiEventBridge::with_persistence_and_limits(secret.clone(), Some(wf_journal.clone()), 16);
        assert!(wf_bridge.is_replay_journal_healthy());
        std::fs::create_dir_all(&wf_journal).unwrap();
        let wf_ev = sample_event("wf-1", AiEventType::CommandCompleted, AiTaskStatus::Completed, true);
        let wf_env = sign_event_envelope(wf_ev, &secret, now_ms, "nonce-wf-0001".to_owned());
        assert!(wf_bridge
            .ingest_signed_envelope(wf_env, now_ms)
            .unwrap_err()
            .starts_with("EVENT_REJECT_REPLAY_PERSIST_FAILED"));
        assert!(wf_bridge.live_tasks().is_empty());

        std::fs::remove_dir_all(&journal_dir).ok();
        std::fs::remove_dir_all(&write_fault_dir).ok();
    }

    #[test]
    fn loopback_http_gateway_accepts_signed_and_rejects_forged_and_invalid_utf8() {
        let secret = b"loopback-gateway-secret-key-32bytes!".to_vec();
        let bridge = Arc::new(AiEventBridge::new(secret.clone()));
        let stop = Arc::new(AtomicBool::new(false));
        let (port, handle) = AiEventBridge::spawn_loopback_http_gateway(bridge.clone(), 0, stop.clone()).unwrap();

        let now_ms = chrono::Utc::now().timestamp_millis();
        let ev = sample_event("http-evt-1", AiEventType::BuildSucceeded, AiTaskStatus::Completed, true);
        let signed = sign_event_envelope(ev, &secret, now_ms, "http-nonce-0001".to_owned());
        let body = serde_json::to_string(&signed).unwrap();

        let mut conn = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let req = format!(
            "POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        );
        conn.write_all(req.as_bytes()).unwrap();
        let mut resp = String::new();
        conn.read_to_string(&mut resp).unwrap();
        assert!(resp.contains("200 OK"));
        assert_eq!(bridge.live_tasks().len(), 1);

        // Invalid UTF-8 HTTP body must return 400 Bad Request, never lossy U+FFFD substitution
        let mut bad_conn = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let bad_bytes = [0x7Bu8, 0x22, 0xFF, 0xFE, 0x22, 0x7D];
        let bad_hdr = format!(
            "POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n",
            bad_bytes.len()
        );
        bad_conn.write_all(bad_hdr.as_bytes()).unwrap();
        bad_conn.write_all(&bad_bytes).unwrap();
        let mut bad_resp = String::new();
        bad_conn.read_to_string(&mut bad_resp).unwrap();
        assert!(bad_resp.contains("400 Bad Request"));
        assert!(bad_resp.contains("INVALID_UTF8_PAYLOAD"));

        stop.store(true, Ordering::Relaxed);
        handle.join().unwrap();
    }
}

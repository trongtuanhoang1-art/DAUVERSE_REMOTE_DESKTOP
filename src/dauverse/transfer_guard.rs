use super::crypto_util::{sha256_file_confined_no_follow, sha256_hex};
use base::message_proto::FileEntry;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs,
    path::{Component, Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    },
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DuplicateFileStrategy {
    RequireConfirmation,
    AutoRename,
    OverwriteConfirmed,
    Skip,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TransferDirection {
    UploadToRemote,
    DownloadToLocal,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct EngineTransferIdentity {
    pub session_scope: String,
    pub conn_id: i32,
    pub direction: TransferDirection,
    pub engine_job_id: i32,
}

impl EngineTransferIdentity {
    pub fn new(
        session_scope: impl Into<String>,
        conn_id: i32,
        direction: TransferDirection,
        engine_job_id: i32,
    ) -> Self {
        Self {
            session_scope: session_scope.into(),
            conn_id,
            direction,
            engine_job_id,
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.session_scope.trim().is_empty() {
            return Err("INTEGRITY_INVALID_IDENTITY: session_scope must be non-empty".to_owned());
        }
        if self.conn_id <= 0 {
            return Err(format!(
                "INTEGRITY_INVALID_IDENTITY: conn_id must be > 0 (got {}); shared connection-0 is forbidden",
                self.conn_id
            ));
        }
        if self.engine_job_id < 0 {
            return Err(format!(
                "INTEGRITY_INVALID_IDENTITY: engine_job_id must be >= 0 (got {})",
                self.engine_job_id
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TransferStatus {
    Queued,
    Active,
    Paused,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExpectedFileIntegritySpec {
    pub relative_path: String,
    pub expected_bytes: u64,
    pub expected_sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferJob {
    pub job_id: String,
    #[serde(default)]
    pub engine_identity: Option<EngineTransferIdentity>,
    #[serde(default)]
    pub generation: u64,
    pub peer_id: String,
    pub direction: TransferDirection,
    pub relative_path: String,
    pub resolved_target_path: String,
    #[serde(default)]
    pub dest_root_dir: Option<String>,
    #[serde(default)]
    pub expected_relative_files: Vec<String>,
    #[serde(default)]
    pub expected_file_specs: Vec<ExpectedFileIntegritySpec>,
    pub total_bytes: u64,
    pub transferred_bytes: u64,
    pub resume_offset: u64,
    pub expected_sha256: Option<String>,
    pub verified_sha256: Option<String>,
    #[serde(default)]
    pub computed_sha256: Option<String>,
    #[serde(default)]
    pub file_sha256_map: HashMap<String, String>,
    #[serde(default)]
    pub integrity_state: String,
    pub status: TransferStatus,
    pub speed_bytes_per_sec: u64,
    pub eta_seconds: Option<u64>,
    pub error_message: Option<String>,
    pub created_at_utc: String,
    pub updated_at_utc: String,
    pub auto_open_disabled: bool,
}

impl TransferJob {
    pub fn progress_pct(&self) -> f32 {
        if self.total_bytes == 0 {
            if self.status == TransferStatus::Completed {
                100.0
            } else {
                0.0
            }
        } else {
            ((self.transferred_bytes as f64 / self.total_bytes as f64) * 100.0).clamp(0.0, 100.0)
                as f32
        }
    }
}

fn is_valid_sha256_hex(digest: &str) -> bool {
    let trimmed = digest.trim();
    trimmed.len() == 64 && trimmed.bytes().all(|b| b.is_ascii_hexdigit())
}

fn constant_time_eq_sha256_hex(expected: &str, actual: &str) -> bool {
    let exp = expected.trim();
    let act = actual.trim();
    if !is_valid_sha256_hex(exp) || !is_valid_sha256_hex(act) {
        return false;
    }
    let mut diff = 0u8;
    for (eb, ab) in exp.bytes().zip(act.bytes()) {
        diff |= eb.to_ascii_lowercase() ^ ab.to_ascii_lowercase();
    }
    diff == 0
}

fn is_windows_reserved_device_name(segment: &str) -> bool {
    let trimmed = segment.trim_matches(|c: char| c == ' ' || c == '.');
    let stem = trimmed
        .split('.')
        .next()
        .unwrap_or("")
        .to_ascii_uppercase();
    matches!(
        stem.as_str(),
        "CON"
            | "PRN"
            | "AUX"
            | "NUL"
            | "COM1"
            | "COM2"
            | "COM3"
            | "COM4"
            | "COM5"
            | "COM6"
            | "COM7"
            | "COM8"
            | "COM9"
            | "LPT1"
            | "LPT2"
            | "LPT3"
            | "LPT4"
            | "LPT5"
            | "LPT6"
            | "LPT7"
            | "LPT8"
            | "LPT9"
    )
}

fn check_no_symlink_or_reparse(path: &Path) -> Result<(), String> {
    super::crypto_util::check_no_symlink_or_reparse_component(path)
}

pub fn validate_and_resolve_destination(
    authorized_root: &Path,
    untrusted_relative_path: &str,
    strategy: DuplicateFileStrategy,
) -> Result<PathBuf, String> {
    if untrusted_relative_path.trim().is_empty() {
        return Err("SECURITY_REJECT_EMPTY_PATH: empty relative path".to_owned());
    }
    if untrusted_relative_path.contains('\0') {
        return Err("SECURITY_REJECT_NULL_BYTE: null byte in path".to_owned());
    }
    if untrusted_relative_path.starts_with('/')
        || untrusted_relative_path.starts_with('\\')
        || untrusted_relative_path.contains(':')
    {
        return Err(
            "SECURITY_REJECT_ABSOLUTE_OR_UNC_PATH: absolute/UNC/drive path forbidden".to_owned(),
        );
    }
    if untrusted_relative_path.contains('\\') {
        for raw_part in untrusted_relative_path.split('\\') {
            if raw_part == ".." || raw_part.is_empty() {
                return Err(
                    "SECURITY_REJECT_PATH_TRAVERSAL: backslash traversal or empty segment"
                        .to_owned(),
                );
            }
            if is_windows_reserved_device_name(raw_part) {
                return Err(format!(
                    "SECURITY_REJECT_RESERVED_DEVICE: '{}' is a reserved OS device name",
                    raw_part
                ));
            }
        }
    }

    if !authorized_root.exists() {
        fs::create_dir_all(authorized_root)
            .map_err(|e| format!("failed creating authorized transfer root: {e}"))?;
    }
    check_no_symlink_or_reparse(authorized_root)?;
    let canonical_root = authorized_root
        .canonicalize()
        .map_err(|e| format!("failed canonicalizing authorized root: {e}"))?;

    let normalized_rel = untrusted_relative_path.replace('\\', "/");
    let rel_path = Path::new(&normalized_rel);

    let mut current = canonical_root.clone();
    for comp in rel_path.components() {
        match comp {
            Component::Normal(os_seg) => {
                let Some(seg) = os_seg.to_str() else {
                    return Err("SECURITY_REJECT_INVALID_UTF8_SEGMENT".to_owned());
                };
                if seg.is_empty() || seg == "." || seg == ".." {
                    return Err("SECURITY_REJECT_PATH_TRAVERSAL: dot traversal segment".to_owned());
                }
                if seg.ends_with('.') || seg.ends_with(' ') {
                    return Err("SECURITY_REJECT_TRAILING_DOT_OR_SPACE".to_owned());
                }
                if is_windows_reserved_device_name(seg) {
                    return Err(format!(
                        "SECURITY_REJECT_RESERVED_DEVICE: '{}' is reserved",
                        seg
                    ));
                }
                current.push(seg);
                check_no_symlink_or_reparse(&current)?;
            }
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(
                    "SECURITY_REJECT_PATH_TRAVERSAL: parent/root/prefix component forbidden"
                        .to_owned(),
                );
            }
        }
    }

    if !current.starts_with(&canonical_root) || current == canonical_root {
        return Err("SECURITY_REJECT_OUTSIDE_AUTHORIZED_ROOT".to_owned());
    }

    if let Some(parent) = current.parent() {
        if parent.exists() {
            let canon_parent = parent
                .canonicalize()
                .map_err(|e| format!("failed canonicalizing parent: {e}"))?;
            if !canon_parent.starts_with(&canonical_root) {
                return Err(
                    "SECURITY_REJECT_SYMLINK_ESCAPE: parent resolves outside authorized root"
                        .to_owned(),
                );
            }
        }
    }

    if current.exists() {
        match strategy {
            DuplicateFileStrategy::RequireConfirmation => {
                return Err("DUPLICATE_REQUIRES_CONFIRMATION".to_owned());
            }
            DuplicateFileStrategy::Skip => {
                return Err("DUPLICATE_SKIPPED_BY_POLICY".to_owned());
            }
            DuplicateFileStrategy::OverwriteConfirmed => {}
            DuplicateFileStrategy::AutoRename => {
                let parent = current
                    .parent()
                    .ok_or_else(|| "missing parent directory".to_owned())?
                    .to_path_buf();
                let stem = current
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("file");
                let ext = current.extension().and_then(|e| e.to_str());
                let mut idx = 1u32;
                loop {
                    let candidate_name = match ext {
                        Some(e) if !e.is_empty() => format!("{stem} ({idx}).{e}"),
                        _ => format!("{stem} ({idx})"),
                    };
                    let candidate = parent.join(candidate_name);
                    if !candidate.exists() {
                        check_no_symlink_or_reparse(&candidate)?;
                        current = candidate;
                        break;
                    }
                    idx += 1;
                    if idx > 10_000 {
                        return Err("DUPLICATE_RENAME_EXHAUSTED".to_owned());
                    }
                }
            }
        }
    }

    Ok(current)
}

pub fn resolve_transfer_manifest_root_and_specs(
    base_path: &Path,
    files: &[FileEntry],
) -> Result<(PathBuf, Vec<ExpectedFileIntegritySpec>), String> {
    if files.is_empty() {
        return Err("SECURITY_REJECT_EMPTY_MANIFEST: transfer file list is empty".to_owned());
    }
    if files.len() == 1 && files[0].name.is_empty() {
        let sha_clean = files[0].sha256.trim().to_ascii_lowercase();
        if !is_valid_sha256_hex(&sha_clean) {
            return Err(
                "INTEGRITY_REJECT_MISSING_SENDER_SHA256: peer did not supply valid 64-hex SHA-256 for single-file transfer"
                    .to_owned(),
            );
        }
        let dest_root = base_path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .ok_or_else(|| {
                "SECURITY_REJECT_MISSING_DEST_PARENT: single-file destination has no parent directory"
                    .to_owned()
            })?
            .to_path_buf();
        let leaf_name = base_path
            .file_name()
            .and_then(|n| n.to_str())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                "SECURITY_REJECT_INVALID_DEST_FILENAME: invalid single-file destination name"
                    .to_owned()
            })?
            .to_owned();
        validate_and_resolve_destination(
            &dest_root,
            &leaf_name,
            DuplicateFileStrategy::OverwriteConfirmed,
        )?;
        return Ok((
            dest_root,
            vec![ExpectedFileIntegritySpec {
                relative_path: leaf_name,
                expected_bytes: files[0].size,
                expected_sha256: sha_clean,
            }],
        ));
    }

    let dest_root = base_path.to_path_buf();
    let mut specs = Vec::with_capacity(files.len());
    for entry in files {
        #[cfg(not(windows))]
        if entry.name.contains('\\') {
            return Err(format!(
                "SECURITY_REJECT_UNNORMALIZED_BACKSLASH: relative path '{}' contains unnormalized backslash",
                entry.name
            ));
        }
        let sha_clean = entry.sha256.trim().to_ascii_lowercase();
        if !is_valid_sha256_hex(&sha_clean) {
            return Err(format!(
                "INTEGRITY_REJECT_MISSING_SENDER_SHA256: peer did not supply valid 64-hex SHA-256 for '{}'",
                entry.name
            ));
        }
        validate_and_resolve_destination(
            &dest_root,
            &entry.name,
            DuplicateFileStrategy::OverwriteConfirmed,
        )?;
        specs.push(ExpectedFileIntegritySpec {
            relative_path: entry.name.clone(),
            expected_bytes: entry.size,
            expected_sha256: sha_clean,
        });
    }
    Ok((dest_root, specs))
}

pub struct TransferQueueManager {
    authorized_root: Mutex<PathBuf>,
    bandwidth_limit_kbps: Mutex<Option<u32>>,
    next_generation: AtomicU64,
    jobs: Mutex<Vec<TransferJob>>,
}

impl TransferQueueManager {
    pub fn new(default_root: PathBuf) -> Self {
        Self {
            authorized_root: Mutex::new(default_root),
            bandwidth_limit_kbps: Mutex::new(None),
            next_generation: AtomicU64::new(1),
            jobs: Mutex::new(Vec::new()),
        }
    }

    pub fn set_authorized_root(&self, root: PathBuf) {
        let mut guard = self.authorized_root.lock().unwrap();
        *guard = root;
    }

    pub fn get_authorized_root(&self) -> PathBuf {
        self.authorized_root.lock().unwrap().clone()
    }

    pub fn set_bandwidth_limit_kbps(&self, limit_kbps: Option<u32>) {
        let mut guard = self.bandwidth_limit_kbps.lock().unwrap();
        *guard = limit_kbps.filter(|&v| v > 0);
    }

    pub fn get_bandwidth_limit_kbps(&self) -> Option<u32> {
        *self.bandwidth_limit_kbps.lock().unwrap()
    }

    pub fn has_active_transfers(&self) -> bool {
        self.jobs
            .lock()
            .unwrap()
            .iter()
            .any(|j| j.status == TransferStatus::Active)
    }

    pub fn active_transfer_count(&self) -> usize {
        self.jobs
            .lock()
            .unwrap()
            .iter()
            .filter(|j| j.status == TransferStatus::Active)
            .count()
    }

    pub fn enqueue_download(
        &self,
        peer_id: &str,
        untrusted_relative_path: &str,
        total_bytes: u64,
        expected_sha256: Option<String>,
        duplicate_strategy: DuplicateFileStrategy,
    ) -> Result<TransferJob, String> {
        let root = self.authorized_root.lock().unwrap().clone();
        let resolved = validate_and_resolve_destination(
            &root,
            untrusted_relative_path,
            duplicate_strategy,
        )?;
        let normalized_expected = expected_sha256
            .as_deref()
            .map(|s| s.trim().to_ascii_lowercase())
            .filter(|s| !s.is_empty());
        let now = chrono::Utc::now().to_rfc3339();
        let generation = self.next_generation.fetch_add(1, Ordering::SeqCst);
        let job = TransferJob {
            job_id: uuid::Uuid::new_v4().to_string(),
            engine_identity: None,
            generation,
            peer_id: peer_id.to_owned(),
            direction: TransferDirection::DownloadToLocal,
            relative_path: untrusted_relative_path.to_owned(),
            resolved_target_path: resolved.to_string_lossy().into_owned(),
            dest_root_dir: Some(root.to_string_lossy().into_owned()),
            expected_relative_files: vec![untrusted_relative_path.to_owned()],
            expected_file_specs: vec![ExpectedFileIntegritySpec {
                relative_path: untrusted_relative_path.to_owned(),
                expected_bytes: total_bytes,
                expected_sha256: normalized_expected.clone().unwrap_or_default(),
            }],
            total_bytes,
            transferred_bytes: 0,
            resume_offset: 0,
            expected_sha256: normalized_expected,
            verified_sha256: None,
            computed_sha256: None,
            file_sha256_map: HashMap::new(),
            integrity_state: "PENDING".to_owned(),
            status: TransferStatus::Queued,
            speed_bytes_per_sec: 0,
            eta_seconds: None,
            error_message: None,
            created_at_utc: now.clone(),
            updated_at_utc: now,
            auto_open_disabled: true,
        };
        self.jobs.lock().unwrap().push(job.clone());
        Ok(job)
    }

    pub fn update_progress(
        &self,
        job_id: &str,
        transferred_bytes: u64,
        speed_bytes_per_sec: u64,
    ) -> Result<TransferJob, String> {
        let bw_cap = self.get_bandwidth_limit_kbps();
        let effective_speed = match bw_cap {
            Some(kbps) => speed_bytes_per_sec.min((kbps as u64) * 1024),
            None => speed_bytes_per_sec,
        };
        let mut jobs = self.jobs.lock().unwrap();
        let job = jobs
            .iter_mut()
            .find(|j| j.job_id == job_id)
            .ok_or_else(|| "transfer job not found".to_owned())?;
        if matches!(
            job.status,
            TransferStatus::Cancelled | TransferStatus::Completed | TransferStatus::Failed
        ) {
            return Err("cannot update progress on finalized transfer job".to_owned());
        }
        job.status = TransferStatus::Active;
        job.transferred_bytes = transferred_bytes.min(job.total_bytes.max(transferred_bytes));
        job.resume_offset = job.transferred_bytes;
        job.speed_bytes_per_sec = effective_speed;
        let remaining = job.total_bytes.saturating_sub(job.transferred_bytes);
        job.eta_seconds = if effective_speed > 0 {
            Some(remaining / effective_speed)
        } else {
            None
        };
        job.updated_at_utc = chrono::Utc::now().to_rfc3339();
        Ok(job.clone())
    }

    pub fn pause(&self, job_id: &str) -> Result<TransferJob, String> {
        self.transition(job_id, |job| {
            if matches!(job.status, TransferStatus::Active | TransferStatus::Queued) {
                job.status = TransferStatus::Paused;
                job.speed_bytes_per_sec = 0;
                job.eta_seconds = None;
                Ok(())
            } else {
                Err("only active or queued jobs can be paused".to_owned())
            }
        })
    }

    pub fn resume(&self, job_id: &str) -> Result<TransferJob, String> {
        self.transition(job_id, |job| {
            if job.status == TransferStatus::Paused {
                job.status = TransferStatus::Active;
                job.resume_offset = job.transferred_bytes;
                Ok(())
            } else {
                Err("only paused jobs can be resumed".to_owned())
            }
        })
    }

    pub fn cancel(&self, job_id: &str) -> Result<TransferJob, String> {
        self.transition(job_id, |job| {
            if job.status == TransferStatus::Completed {
                Err("completed job cannot be cancelled".to_owned())
            } else {
                job.status = TransferStatus::Cancelled;
                job.verified_sha256 = None;
                job.integrity_state = "CANCELLED".to_owned();
                job.speed_bytes_per_sec = 0;
                job.eta_seconds = None;
                Ok(())
            }
        })
    }

    pub fn retry(&self, job_id: &str) -> Result<TransferJob, String> {
        let next_gen = self.next_generation.fetch_add(1, Ordering::SeqCst);
        self.transition(job_id, |job| {
            if matches!(job.status, TransferStatus::Failed | TransferStatus::Cancelled) {
                job.generation = next_gen;
                job.status = TransferStatus::Queued;
                job.verified_sha256 = None;
                job.integrity_state = "PENDING".to_owned();
                job.error_message = None;
                Ok(())
            } else {
                Err("only failed or cancelled jobs can be retried".to_owned())
            }
        })
    }

    pub fn finalize_and_verify(&self, job_id: &str) -> Result<TransferJob, String> {
        let (snapshot_gen, root_dir, target_path, expected_total, expected_sha_snapshot, rel_snapshot) = {
            let jobs = self.jobs.lock().unwrap();
            let job = jobs
                .iter()
                .find(|j| j.job_id == job_id)
                .ok_or_else(|| "transfer job not found".to_owned())?;
            if !matches!(
                job.status,
                TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
            ) {
                return Err(format!(
                    "INTEGRITY_NON_ACTIVE_JOB: cannot finalize job '{}' in status {:?}",
                    job.job_id, job.status
                ));
            }
            let root = job
                .dest_root_dir
                .as_deref()
                .map(PathBuf::from)
                .unwrap_or_else(|| self.get_authorized_root());
            (
                job.generation,
                root,
                PathBuf::from(&job.resolved_target_path),
                job.total_bytes,
                job.expected_sha256.clone(),
                job.relative_path.clone(),
            )
        };

        let staging_leftover = PathBuf::from(format!("{}.download", target_path.display()));
        let digest_leftover = PathBuf::from(format!("{}.digest", target_path.display()));
        if staging_leftover.exists() || digest_leftover.exists() {
            let msg = format!(
                "INTEGRITY_UNFINALIZED_DOWNLOAD_STAGING: incomplete staging artifacts exist for '{}'",
                target_path.display()
            );
            return self.commit_job_with_generation_cas(job_id, snapshot_gen, |job| {
                job.status = TransferStatus::Failed;
                job.verified_sha256 = None;
                job.integrity_state = "FAILED_UNFINALIZED_STAGING".to_owned();
                job.error_message = Some(msg.clone());
                Err(msg)
            });
        }

        let hash_res = sha256_file_confined_no_follow(&root_dir, &target_path);
        self.commit_job_with_generation_cas(job_id, snapshot_gen, |job| {
            let (actual_hash, actual_len) = match hash_res {
                Ok(v) => v,
                Err(e) => {
                    job.status = TransferStatus::Failed;
                    job.verified_sha256 = None;
                    job.integrity_state = "FAILED_SYMLINK_OR_UNREADABLE".to_owned();
                    job.error_message = Some(e.clone());
                    return Err(e);
                }
            };
            if actual_len != expected_total {
                let msg = format!(
                    "INTEGRITY_BYTE_SIZE_MISMATCH: expected {} bytes, got {} bytes",
                    expected_total, actual_len
                );
                job.status = TransferStatus::Failed;
                job.verified_sha256 = None;
                job.computed_sha256 = Some(actual_hash);
                job.integrity_state = "FAILED_MISSING_OR_TRUNCATED_FILE".to_owned();
                job.error_message = Some(msg.clone());
                return Err(msg);
            }
            job.computed_sha256 = Some(actual_hash.clone());
            let Some(expected) = expected_sha_snapshot
                .as_deref()
                .filter(|s| is_valid_sha256_hex(s))
            else {
                let msg = "INTEGRITY_MISSING_SENDER_SHA256: cannot mark transfer Completed without valid 64-char sender SHA-256".to_owned();
                job.status = TransferStatus::Failed;
                job.verified_sha256 = None;
                job.integrity_state = "FAILED_UNVERIFIED_MISSING_SENDER_DIGEST".to_owned();
                job.error_message = Some(msg.clone());
                return Err(msg);
            };
            if !constant_time_eq_sha256_hex(expected, &actual_hash) {
                let msg = format!(
                    "INTEGRITY_SHA256_MISMATCH: expected {}, got {}",
                    expected.trim(),
                    actual_hash
                );
                job.status = TransferStatus::Failed;
                job.verified_sha256 = None;
                job.integrity_state = "FAILED_SHA256_MISMATCH".to_owned();
                job.error_message = Some(msg.clone());
                return Err(msg);
            }
            job.file_sha256_map.insert(rel_snapshot, actual_hash.clone());
            job.verified_sha256 = Some(actual_hash);
            job.integrity_state = "SENDER_SHA256_VERIFIED".to_owned();
            job.transferred_bytes = actual_len;
            job.speed_bytes_per_sec = 0;
            job.eta_seconds = Some(0);
            job.status = TransferStatus::Completed;
            Ok(())
        })
    }

    pub fn list_jobs(&self) -> Vec<TransferJob> {
        self.jobs.lock().unwrap().clone()
    }

    pub fn track_engine_receive_start_batch_scoped(
        &self,
        identity: EngineTransferIdentity,
        dest_dir: &str,
        relative_files: Vec<String>,
        total_bytes: u64,
    ) -> Result<(String, u64), String> {
        let single_len = if relative_files.len() == 1 {
            total_bytes
        } else {
            0
        };
        let specs = relative_files
            .into_iter()
            .map(|rel| ExpectedFileIntegritySpec {
                relative_path: rel,
                expected_bytes: single_len,
                expected_sha256: String::new(),
            })
            .collect();
        self.track_engine_transfer_start_scoped(identity, dest_dir, specs, total_bytes)
    }

    pub fn track_engine_transfer_start_scoped(
        &self,
        identity: EngineTransferIdentity,
        dest_dir: &str,
        file_specs: Vec<ExpectedFileIntegritySpec>,
        total_bytes: u64,
    ) -> Result<(String, u64), String> {
        identity.validate()?;
        let generation = self.next_generation.fetch_add(1, Ordering::SeqCst);
        let dir_tag = match identity.direction {
            TransferDirection::DownloadToLocal => "dl",
            TransferDirection::UploadToRemote => "ul",
        };
        let job_id = format!(
            "engine-{}-{}-c{}-j{}-g{}",
            identity.session_scope, dir_tag, identity.conn_id, identity.engine_job_id, generation
        );
        let now = chrono::Utc::now().to_rfc3339();
        let relative_files: Vec<String> = file_specs
            .iter()
            .map(|s| s.relative_path.clone())
            .collect();
        let first_rel = relative_files
            .first()
            .cloned()
            .unwrap_or_else(|| "transfer_batch".to_owned());
        let resolved = Path::new(dest_dir)
            .join(&first_rel)
            .to_string_lossy()
            .into_owned();
        let single_expected_sha = if file_specs.len() == 1
            && is_valid_sha256_hex(&file_specs[0].expected_sha256)
        {
            Some(file_specs[0].expected_sha256.trim().to_ascii_lowercase())
        } else {
            None
        };
        let initial_integrity_state = match identity.direction {
            TransferDirection::DownloadToLocal => "PENDING".to_owned(),
            TransferDirection::UploadToRemote => "OUTBOUND_SENDER_STREAM_HASHED".to_owned(),
        };
        let peer_label = format!("{}:conn-{}", identity.session_scope, identity.conn_id);

        let mut jobs = self.jobs.lock().unwrap();
        // Never overwrite an existing job's root, manifest, peer identity, or transferred state.
        // If an earlier generation for the exact same (scope, conn_id, direction, engine_job_id)
        // is still non-terminal (e.g., reconnect/ID reuse), mark only that older generation
        // superseded while preserving its original audit fields intact.
        for existing in jobs.iter_mut() {
            if existing.engine_identity.as_ref() == Some(&identity)
                && matches!(
                    existing.status,
                    TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
                )
            {
                existing.status = TransferStatus::Failed;
                existing.verified_sha256 = None;
                existing.integrity_state = "SUPERSEDED_BY_NEW_GENERATION".to_owned();
                existing.error_message = Some(format!(
                    "INTEGRITY_SUPERSEDED_BY_GENERATION_{generation}"
                ));
                existing.speed_bytes_per_sec = 0;
                existing.eta_seconds = None;
                existing.updated_at_utc = now.clone();
            }
        }

        jobs.push(TransferJob {
            job_id: job_id.clone(),
            engine_identity: Some(identity.clone()),
            generation,
            peer_id: peer_label,
            direction: identity.direction,
            relative_path: first_rel,
            resolved_target_path: resolved,
            dest_root_dir: Some(dest_dir.to_owned()),
            expected_relative_files: relative_files,
            expected_file_specs: file_specs,
            total_bytes,
            transferred_bytes: 0,
            resume_offset: 0,
            expected_sha256: single_expected_sha,
            verified_sha256: None,
            computed_sha256: None,
            file_sha256_map: HashMap::new(),
            integrity_state: initial_integrity_state,
            status: TransferStatus::Active,
            speed_bytes_per_sec: 0,
            eta_seconds: None,
            error_message: None,
            created_at_utc: now.clone(),
            updated_at_utc: now,
            auto_open_disabled: true,
        });
        Ok((job_id, generation))
    }

    pub fn update_engine_progress_scoped(
        &self,
        identity: &EngineTransferIdentity,
        transferred_bytes: u64,
        speed_bytes_per_sec: u64,
    ) -> Result<TransferJob, String> {
        identity.validate()?;
        let bw_cap = self.get_bandwidth_limit_kbps();
        let effective_speed = match bw_cap {
            Some(kbps) => speed_bytes_per_sec.min((kbps as u64) * 1024),
            None => speed_bytes_per_sec,
        };
        let mut jobs = self.jobs.lock().unwrap();
        let job = jobs
            .iter_mut()
            .filter(|j| {
                j.engine_identity.as_ref() == Some(identity)
                    && matches!(
                        j.status,
                        TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
                    )
            })
            .max_by_key(|j| j.generation)
            .ok_or_else(|| {
                format!(
                    "INTEGRITY_ORPHAN_JOB: no active transfer for scope '{}' conn {} {:?} job {}",
                    identity.session_scope,
                    identity.conn_id,
                    identity.direction,
                    identity.engine_job_id
                )
            })?;
        job.status = TransferStatus::Active;
        job.transferred_bytes = transferred_bytes.min(job.total_bytes.max(transferred_bytes));
        job.resume_offset = job.transferred_bytes;
        job.speed_bytes_per_sec = effective_speed;
        let remaining = job.total_bytes.saturating_sub(job.transferred_bytes);
        job.eta_seconds = if effective_speed > 0 {
            Some(remaining / effective_speed)
        } else {
            None
        };
        job.updated_at_utc = chrono::Utc::now().to_rfc3339();
        Ok(job.clone())
    }

    pub fn resume_engine_transfer_scoped(
        &self,
        identity: &EngineTransferIdentity,
        resume_offset: u64,
    ) -> Result<TransferJob, String> {
        identity.validate()?;
        let mut jobs = self.jobs.lock().unwrap();
        let job = jobs
            .iter_mut()
            .filter(|j| {
                j.engine_identity.as_ref() == Some(identity)
                    && matches!(
                        j.status,
                        TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
                    )
            })
            .max_by_key(|j| j.generation)
            .ok_or_else(|| {
                format!(
                    "INTEGRITY_ORPHAN_JOB: no resumable transfer for scope '{}' conn {} {:?} job {}",
                    identity.session_scope,
                    identity.conn_id,
                    identity.direction,
                    identity.engine_job_id
                )
            })?;
        job.status = TransferStatus::Active;
        job.resume_offset = resume_offset;
        job.transferred_bytes = resume_offset.min(job.total_bytes.max(resume_offset));
        job.updated_at_utc = chrono::Utc::now().to_rfc3339();
        Ok(job.clone())
    }

    pub fn verify_and_finalize_engine_receive_scoped(
        &self,
        identity: &EngineTransferIdentity,
        expected_generation: Option<u64>,
    ) -> Result<TransferJob, String> {
        identity.validate()?;
        if identity.direction != TransferDirection::DownloadToLocal {
            return Err(
                "INTEGRITY_DIRECTION_MISMATCH: receiver SHA-256 verification applies only to DownloadToLocal"
                    .to_owned(),
            );
        }

        let (snapshot_job_id, snapshot_gen, dest_root, specs, expected_total) = {
            let jobs = self.jobs.lock().unwrap();
            let job = jobs
                .iter()
                .filter(|j| j.engine_identity.as_ref() == Some(identity))
                .max_by_key(|j| j.generation)
                .ok_or_else(|| {
                    format!(
                        "INTEGRITY_ORPHAN_JOB: unknown engine receive job for scope '{}' conn {} job {}",
                        identity.session_scope, identity.conn_id, identity.engine_job_id
                    )
                })?;
            if let Some(exp_gen) = expected_generation {
                if job.generation != exp_gen {
                    return Err(format!(
                        "INTEGRITY_STALE_GENERATION: requested generation {}, latest generation is {}",
                        exp_gen, job.generation
                    ));
                }
            }
            if !matches!(
                job.status,
                TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
            ) {
                return Err(format!(
                    "INTEGRITY_NON_ACTIVE_JOB: job '{}' (generation {}) is in terminal status {:?}",
                    job.job_id, job.generation, job.status
                ));
            }
            let root = job
                .dest_root_dir
                .as_deref()
                .map(PathBuf::from)
                .ok_or_else(|| "INTEGRITY_MISSING_DEST_ROOT".to_owned())?;
            let effective_specs = if !job.expected_file_specs.is_empty() {
                job.expected_file_specs.clone()
            } else {
                let fallback_sha = job.expected_sha256.clone().unwrap_or_default();
                let single_len = if job.expected_relative_files.len() == 1 {
                    job.total_bytes
                } else {
                    0
                };
                job.expected_relative_files
                    .iter()
                    .map(|rel| ExpectedFileIntegritySpec {
                        relative_path: rel.clone(),
                        expected_bytes: single_len,
                        expected_sha256: fallback_sha.clone(),
                    })
                    .collect()
            };
            (
                job.job_id.clone(),
                job.generation,
                root,
                effective_specs,
                job.total_bytes,
            )
        };

        if specs.is_empty() {
            let msg =
                "INTEGRITY_EMPTY_FILE_MANIFEST: no files recorded for engine receive job".to_owned();
            return self.commit_engine_job_with_cas(
                &snapshot_job_id,
                identity,
                snapshot_gen,
                |job| {
                    job.status = TransferStatus::Failed;
                    job.verified_sha256 = None;
                    job.integrity_state = "FAILED_EMPTY_FILE_MANIFEST".to_owned();
                    job.error_message = Some(msg.clone());
                    Err(msg)
                },
            );
        }

        let mut actual_total_bytes = 0u64;
        let mut manifest_sum_bytes = 0u64;
        let mut digest_map = HashMap::new();
        let mut primary_sha: Option<String> = None;
        let mut verified_records = Vec::with_capacity(specs.len());

        for spec in &specs {
            manifest_sum_bytes = manifest_sum_bytes
                .checked_add(spec.expected_bytes)
                .ok_or_else(|| "INTEGRITY_MANIFEST_BYTE_OVERFLOW".to_owned())?;
            let candidate = dest_root.join(&spec.relative_path);
            let staging_leftover = PathBuf::from(format!("{}.download", candidate.display()));
            let digest_leftover = PathBuf::from(format!("{}.digest", candidate.display()));
            if staging_leftover.exists() || digest_leftover.exists() {
                let msg = format!(
                    "INTEGRITY_UNFINALIZED_DOWNLOAD_STAGING: '{}' still has unfinalized staging files",
                    candidate.display()
                );
                return self.commit_engine_job_with_cas(
                    &snapshot_job_id,
                    identity,
                    snapshot_gen,
                    |job| {
                        job.status = TransferStatus::Failed;
                        job.verified_sha256 = None;
                        job.integrity_state = "FAILED_UNFINALIZED_STAGING".to_owned();
                        job.error_message = Some(msg.clone());
                        Err(msg)
                    },
                );
            }

            let (sha, len) = match sha256_file_confined_no_follow(&dest_root, &candidate) {
                Ok(v) => v,
                Err(e) => {
                    return self.commit_engine_job_with_cas(
                        &snapshot_job_id,
                        identity,
                        snapshot_gen,
                        |job| {
                            job.status = TransferStatus::Failed;
                            job.verified_sha256 = None;
                            job.integrity_state = "FAILED_SYMLINK_OR_MISSING_FILE".to_owned();
                            job.error_message = Some(e.clone());
                            Err(e)
                        },
                    );
                }
            };

            if primary_sha.is_none() {
                primary_sha = Some(sha.clone());
            }
            actual_total_bytes = actual_total_bytes.saturating_add(len);
            digest_map.insert(spec.relative_path.clone(), sha.clone());

            if len != spec.expected_bytes {
                let msg = format!(
                    "INTEGRITY_FILE_BYTE_SIZE_MISMATCH: file '{}' expected {} bytes, got {} bytes",
                    spec.relative_path, spec.expected_bytes, len
                );
                return self.commit_engine_job_with_cas(
                    &snapshot_job_id,
                    identity,
                    snapshot_gen,
                    |job| {
                        job.status = TransferStatus::Failed;
                        job.transferred_bytes = actual_total_bytes;
                        job.verified_sha256 = None;
                        job.computed_sha256 = primary_sha;
                        job.file_sha256_map = digest_map;
                        job.integrity_state = "FAILED_MISSING_OR_TRUNCATED_FILE".to_owned();
                        job.error_message = Some(msg.clone());
                        Err(msg)
                    },
                );
            }

            if !is_valid_sha256_hex(&spec.expected_sha256) {
                let msg = format!(
                    "INTEGRITY_MISSING_SENDER_SHA256: file '{}' has no valid 64-char sender SHA-256",
                    spec.relative_path
                );
                return self.commit_engine_job_with_cas(
                    &snapshot_job_id,
                    identity,
                    snapshot_gen,
                    |job| {
                        job.status = TransferStatus::Failed;
                        job.transferred_bytes = actual_total_bytes;
                        job.verified_sha256 = None;
                        job.computed_sha256 = primary_sha;
                        job.file_sha256_map = digest_map;
                        job.integrity_state =
                            "FAILED_UNVERIFIED_MISSING_SENDER_DIGEST".to_owned();
                        job.error_message = Some(msg.clone());
                        Err(msg)
                    },
                );
            }

            if !constant_time_eq_sha256_hex(&spec.expected_sha256, &sha) {
                let msg = format!(
                    "INTEGRITY_SHA256_MISMATCH: file '{}' expected {}, got {}",
                    spec.relative_path,
                    spec.expected_sha256.trim(),
                    sha
                );
                return self.commit_engine_job_with_cas(
                    &snapshot_job_id,
                    identity,
                    snapshot_gen,
                    |job| {
                        job.status = TransferStatus::Failed;
                        job.transferred_bytes = actual_total_bytes;
                        job.verified_sha256 = None;
                        job.computed_sha256 = primary_sha;
                        job.file_sha256_map = digest_map;
                        job.integrity_state = "FAILED_SHA256_MISMATCH".to_owned();
                        job.error_message = Some(msg.clone());
                        Err(msg)
                    },
                );
            }

            verified_records.push(format!("{}:{}:{}", spec.relative_path, len, sha));
        }

        if manifest_sum_bytes != expected_total || actual_total_bytes != expected_total {
            let msg = format!(
                "INTEGRITY_RECEIVED_SIZE_MISMATCH: expected_total={} bytes, manifest_sum={} bytes, actual={} bytes across {} file(s)",
                expected_total,
                manifest_sum_bytes,
                actual_total_bytes,
                specs.len()
            );
            return self.commit_engine_job_with_cas(
                &snapshot_job_id,
                identity,
                snapshot_gen,
                |job| {
                    job.status = TransferStatus::Failed;
                    job.transferred_bytes = actual_total_bytes;
                    job.verified_sha256 = None;
                    job.computed_sha256 = primary_sha;
                    job.file_sha256_map = digest_map;
                    job.integrity_state = "FAILED_MISSING_OR_TRUNCATED_FILE".to_owned();
                    job.error_message = Some(msg.clone());
                    Err(msg)
                },
            );
        }

        let aggregate_proof = if verified_records.len() == 1 {
            primary_sha.clone()
        } else {
            Some(sha256_hex(verified_records.join("\n").as_bytes()))
        };

        self.commit_engine_job_with_cas(&snapshot_job_id, identity, snapshot_gen, |job| {
            job.computed_sha256 = primary_sha;
            job.file_sha256_map = digest_map;
            job.verified_sha256 = aggregate_proof;
            job.integrity_state = "SENDER_SHA256_VERIFIED".to_owned();
            job.transferred_bytes = actual_total_bytes;
            job.speed_bytes_per_sec = 0;
            job.eta_seconds = Some(0);
            job.error_message = None;
            job.status = TransferStatus::Completed;
            Ok(())
        })
    }

    pub fn track_engine_transfer_finish_scoped(
        &self,
        identity: &EngineTransferIdentity,
        expected_generation: Option<u64>,
        completed: bool,
        cancelled: bool,
        error_message: Option<&str>,
    ) -> Result<TransferJob, String> {
        identity.validate()?;
        if completed && identity.direction == TransferDirection::DownloadToLocal {
            return self.verify_and_finalize_engine_receive_scoped(identity, expected_generation);
        }

        let mut jobs = self.jobs.lock().unwrap();
        let Some(job) = jobs
            .iter_mut()
            .filter(|j| j.engine_identity.as_ref() == Some(identity))
            .max_by_key(|j| j.generation)
        else {
            return Err(format!(
                "INTEGRITY_ORPHAN_JOB: no tracked job for scope '{}' conn {} {:?} job {}",
                identity.session_scope,
                identity.conn_id,
                identity.direction,
                identity.engine_job_id
            ));
        };

        if let Some(exp_gen) = expected_generation {
            if job.generation != exp_gen {
                return Err(format!(
                    "INTEGRITY_STALE_GENERATION: expected generation {}, latest is {}",
                    exp_gen, job.generation
                ));
            }
        }
        if !matches!(
            job.status,
            TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
        ) {
            return Err(format!(
                "INTEGRITY_NON_ACTIVE_JOB: job '{}' is already {:?}",
                job.job_id, job.status
            ));
        }

        if completed {
            // FT010-Q03: Outbound UploadToRemote completion from a remote Done packet is never
            // labeled SENDER_SHA256_VERIFIED without an authenticated receiver cryptographic receipt.
            job.status = TransferStatus::Completed;
            job.verified_sha256 = None;
            job.integrity_state =
                "SENDER_STREAM_EOF_CHECKED_UNVERIFIED_RECEIVER".to_owned();
            job.transferred_bytes = job.total_bytes;
            job.eta_seconds = Some(0);
            job.error_message = None;
        } else if cancelled {
            job.status = TransferStatus::Cancelled;
            job.verified_sha256 = None;
            job.integrity_state = "CANCELLED".to_owned();
            job.error_message = error_message.map(|s| s.to_owned());
        } else {
            job.status = TransferStatus::Failed;
            job.verified_sha256 = None;
            job.integrity_state = "FAILED_TRANSPORT".to_owned();
            job.error_message = error_message.map(|s| s.to_owned());
        }
        job.speed_bytes_per_sec = 0;
        job.updated_at_utc = chrono::Utc::now().to_rfc3339();
        Ok(job.clone())
    }

    pub fn fail_all_active_for_scope(&self, session_scope: &str, reason: &str) -> usize {
        if session_scope.trim().is_empty() {
            return 0;
        }
        let now = chrono::Utc::now().to_rfc3339();
        let mut count = 0usize;
        let mut jobs = self.jobs.lock().unwrap();
        for job in jobs.iter_mut() {
            let matches_scope = job
                .engine_identity
                .as_ref()
                .map(|id| id.session_scope == session_scope)
                .unwrap_or(false);
            if matches_scope
                && matches!(
                    job.status,
                    TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
                )
            {
                job.status = TransferStatus::Failed;
                job.verified_sha256 = None;
                job.integrity_state = "FAILED_DISCONNECTED".to_owned();
                job.error_message = Some(reason.to_owned());
                job.speed_bytes_per_sec = 0;
                job.eta_seconds = None;
                job.updated_at_utc = now.clone();
                count += 1;
            }
        }
        count
    }

    pub fn fail_all_active_transfers(&self, reason: &str) -> usize {
        let now = chrono::Utc::now().to_rfc3339();
        let mut count = 0usize;
        let mut jobs = self.jobs.lock().unwrap();
        for job in jobs.iter_mut() {
            if matches!(
                job.status,
                TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
            ) {
                job.status = TransferStatus::Failed;
                job.verified_sha256 = None;
                job.integrity_state = "REVOKED_EMERGENCY".to_owned();
                job.error_message = Some(reason.to_owned());
                job.speed_bytes_per_sec = 0;
                job.eta_seconds = None;
                job.updated_at_utc = now.clone();
                count += 1;
            }
        }
        count
    }

    fn commit_job_with_generation_cas<F>(
        &self,
        job_id: &str,
        expected_gen: u64,
        f: F,
    ) -> Result<TransferJob, String>
    where
        F: FnOnce(&mut TransferJob) -> Result<(), String>,
    {
        let mut jobs = self.jobs.lock().unwrap();
        let job = jobs
            .iter_mut()
            .find(|j| j.job_id == job_id)
            .ok_or_else(|| "transfer job not found".to_owned())?;
        if job.generation != expected_gen
            || !matches!(
                job.status,
                TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
            )
        {
            return Err(format!(
                "INTEGRITY_STALE_GENERATION_OR_CANCELLED: job '{}' changed generation ({} vs {}) or entered status {:?} before commit",
                job.job_id, job.generation, expected_gen, job.status
            ));
        }
        let res = f(job);
        job.updated_at_utc = chrono::Utc::now().to_rfc3339();
        res?;
        Ok(job.clone())
    }

    fn commit_engine_job_with_cas<F>(
        &self,
        snapshot_job_id: &str,
        expected_identity: &EngineTransferIdentity,
        expected_gen: u64,
        f: F,
    ) -> Result<TransferJob, String>
    where
        F: FnOnce(&mut TransferJob) -> Result<(), String>,
    {
        let mut jobs = self.jobs.lock().unwrap();
        let has_newer_generation = jobs.iter().any(|other| {
            other.engine_identity.as_ref() == Some(expected_identity)
                && other.generation > expected_gen
        });
        let job = jobs
            .iter_mut()
            .find(|j| j.job_id == snapshot_job_id)
            .ok_or_else(|| {
                format!(
                    "INTEGRITY_ORPHAN_JOB: snapshot job '{}' disappeared before commit",
                    snapshot_job_id
                )
            })?;
        if has_newer_generation
            || job.generation != expected_gen
            || job.engine_identity.as_ref() != Some(expected_identity)
            || !matches!(
                job.status,
                TransferStatus::Active | TransferStatus::Queued | TransferStatus::Paused
            )
        {
            return Err(format!(
                "INTEGRITY_STALE_GENERATION_OR_CANCELLED: job '{}' (gen {}, status {:?}) was superseded or cancelled before commit",
                job.job_id, job.generation, job.status
            ));
        }
        let res = f(job);
        job.updated_at_utc = chrono::Utc::now().to_rfc3339();
        res?;
        Ok(job.clone())
    }

    fn transition<F>(&self, job_id: &str, f: F) -> Result<TransferJob, String>
    where
        F: FnOnce(&mut TransferJob) -> Result<(), String>,
    {
        let mut jobs = self.jobs.lock().unwrap();
        let job = jobs
            .iter_mut()
            .find(|j| j.job_id == job_id)
            .ok_or_else(|| "transfer job not found".to_owned())?;
        let res = f(job);
        job.updated_at_utc = chrono::Utc::now().to_rfc3339();
        res?;
        Ok(job.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_traversal_unc_reserved_and_symlinks() {
        let base = std::env::temp_dir().join(format!("dv_xfer_test_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&base).unwrap();

        assert!(validate_and_resolve_destination(
            &base,
            "../../etc/passwd",
            DuplicateFileStrategy::AutoRename
        )
        .is_err());
        assert!(validate_and_resolve_destination(
            &base,
            "..\\..\\Windows\\System32\\cmd.exe",
            DuplicateFileStrategy::AutoRename
        )
        .is_err());
        assert!(validate_and_resolve_destination(
            &base,
            "\\\\evil-server\\share\\payload.exe",
            DuplicateFileStrategy::AutoRename
        )
        .is_err());
        assert!(validate_and_resolve_destination(
            &base,
            "C:\\Windows\\win.ini",
            DuplicateFileStrategy::AutoRename
        )
        .is_err());
        assert!(validate_and_resolve_destination(
            &base,
            "docs/CON.txt",
            DuplicateFileStrategy::AutoRename
        )
        .is_err());
        assert!(validate_and_resolve_destination(
            &base,
            "docs/report.txt:secret",
            DuplicateFileStrategy::AutoRename
        )
        .is_err());

        #[cfg(unix)]
        {
            let outside = std::env::temp_dir().join(format!("dv_outside_{}", uuid::Uuid::new_v4()));
            fs::create_dir_all(&outside).unwrap();
            let link_dir = base.join("escape_link");
            std::os::unix::fs::symlink(&outside, &link_dir).unwrap();
            let res = validate_and_resolve_destination(
                &base,
                "escape_link/secret.txt",
                DuplicateFileStrategy::AutoRename,
            );
            assert!(res.is_err());
            assert!(res.unwrap_err().contains("SECURITY_REJECT_SYMLINK"));
            fs::remove_dir_all(&outside).ok();
        }

        #[cfg(windows)]
        {
            let outside = std::env::temp_dir().join(format!("dv_outside_{}", uuid::Uuid::new_v4()));
            fs::create_dir_all(&outside).unwrap();
            let link_dir = base.join("escape_junction");
            let status = std::process::Command::new("cmd")
                .args([
                    "/C",
                    "mklink",
                    "/J",
                    &link_dir.to_string_lossy(),
                    &outside.to_string_lossy(),
                ])
                .status()
                .unwrap();
            assert!(status.success());
            let res = validate_and_resolve_destination(
                &base,
                "escape_junction/secret.txt",
                DuplicateFileStrategy::AutoRename,
            );
            assert!(res.is_err());
            let _ = fs::remove_dir(&link_dir);
            fs::remove_dir_all(&outside).ok();
        }

        fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn f14_f16_per_file_sender_sha256_integrity_and_negative_tamper_suite() {
        let base = std::env::temp_dir().join(format!("dv_xfer_q_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&base).unwrap();

        let existing = base.join("video.mp4");
        fs::write(&existing, b"old").unwrap();
        let renamed = validate_and_resolve_destination(
            &base,
            "video.mp4",
            DuplicateFileStrategy::AutoRename,
        )
        .unwrap();
        assert!(renamed.ends_with("video (1).mp4"));

        let mgr = TransferQueueManager::new(base.clone());
        mgr.set_bandwidth_limit_kbps(Some(1024));
        let payload = b"DAUVERSE_FILE_INTEGRITY_VERIFIED_PAYLOAD_2026";
        let expected_sha = sha256_hex(payload);

        let job = mgr
            .enqueue_download(
                "peer-home",
                "renders/comfy_output.mp4",
                payload.len() as u64,
                Some(expected_sha.clone()),
                DuplicateFileStrategy::AutoRename,
            )
            .unwrap();

        let p1 = mgr.update_progress(&job.job_id, 16, 10_000_000).unwrap();
        assert_eq!(p1.status, TransferStatus::Active);
        assert_eq!(p1.speed_bytes_per_sec, 1024 * 1024);

        let paused = mgr.pause(&job.job_id).unwrap();
        assert_eq!(paused.status, TransferStatus::Paused);
        assert_eq!(paused.resume_offset, 16);

        let resumed = mgr.resume(&job.job_id).unwrap();
        assert_eq!(resumed.status, TransferStatus::Active);

        let target = PathBuf::from(&resumed.resolved_target_path);
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        fs::write(&target, payload).unwrap();

        let done = mgr.finalize_and_verify(&job.job_id).unwrap();
        assert_eq!(done.status, TransferStatus::Completed);
        assert!(done.auto_open_disabled);
        assert_eq!(done.verified_sha256.as_deref(), Some(expected_sha.as_str()));
        assert_eq!(done.integrity_state, "SENDER_SHA256_VERIFIED");

        // F16 Positive: Multi-file manifest with exact per-file byte lengths and sender SHA-256s
        let f1_bytes = b"AAAA";
        let f2_bytes = b"CCCCCC";
        fs::write(base.join("a.bin"), f1_bytes).unwrap();
        fs::write(base.join("b.bin"), f2_bytes).unwrap();
        let id_77 = EngineTransferIdentity::new(
            "test-sess-1",
            1,
            TransferDirection::DownloadToLocal,
            77,
        );
        let (_, gen_77) = mgr
            .track_engine_transfer_start_scoped(
                id_77.clone(),
                base.to_str().unwrap(),
                vec![
                    ExpectedFileIntegritySpec {
                        relative_path: "a.bin".to_owned(),
                        expected_bytes: 4,
                        expected_sha256: sha256_hex(f1_bytes),
                    },
                    ExpectedFileIntegritySpec {
                        relative_path: "b.bin".to_owned(),
                        expected_bytes: 6,
                        expected_sha256: sha256_hex(f2_bytes),
                    },
                ],
                10,
            )
            .unwrap();
        let rx_ok = mgr
            .verify_and_finalize_engine_receive_scoped(&id_77, Some(gen_77))
            .unwrap();
        assert_eq!(rx_ok.status, TransferStatus::Completed);
        assert!(rx_ok.verified_sha256.is_some());
        assert_eq!(rx_ok.file_sha256_map.len(), 2);
        assert_eq!(rx_ok.integrity_state, "SENDER_SHA256_VERIFIED");

        // F16 Negative 1: Missing sender SHA-256 MUST fail closed (never mark Completed!)
        let id_177 = EngineTransferIdentity::new(
            "test-sess-1",
            1,
            TransferDirection::DownloadToLocal,
            177,
        );
        let (job_id_177, gen_177) = mgr
            .track_engine_receive_start_batch_scoped(
                id_177.clone(),
                base.to_str().unwrap(),
                vec!["a.bin".to_owned(), "b.bin".to_owned()],
                10,
            )
            .unwrap();
        assert!(mgr
            .verify_and_finalize_engine_receive_scoped(&id_177, Some(gen_177))
            .is_err());
        let rx_unverified = mgr
            .list_jobs()
            .into_iter()
            .find(|j| j.job_id == job_id_177)
            .unwrap();
        assert_eq!(rx_unverified.status, TransferStatus::Failed);

        let unverified_dl = mgr
            .enqueue_download(
                "peer-home",
                "renders/no_digest.bin",
                4,
                None,
                DuplicateFileStrategy::OverwriteConfirmed,
            )
            .unwrap();
        fs::write(&unverified_dl.resolved_target_path, b"AAAA").unwrap();
        assert!(mgr.finalize_and_verify(&unverified_dl.job_id).is_err());

        // F16 Negative 2: Same-size content mutation (AAAA -> BBBB) MUST fail closed
        fs::write(base.join("a.bin"), b"BBBB").unwrap();
        let id_178 = EngineTransferIdentity::new(
            "test-sess-1",
            1,
            TransferDirection::DownloadToLocal,
            178,
        );
        mgr.track_engine_transfer_start_scoped(
            id_178.clone(),
            base.to_str().unwrap(),
            vec![ExpectedFileIntegritySpec {
                relative_path: "a.bin".to_owned(),
                expected_bytes: 4,
                expected_sha256: sha256_hex(b"AAAA"),
            }],
            4,
        )
        .unwrap();
        let err_mut = mgr
            .verify_and_finalize_engine_receive_scoped(&id_178, None)
            .unwrap_err();
        assert!(err_mut.contains("INTEGRITY_SHA256_MISMATCH"));

        // F16 Negative 3: Compensating multi-file lengths ([2, 8] == 10 vs [4, 6] == 10) MUST fail closed
        fs::write(base.join("comp1.bin"), b"12").unwrap();
        fs::write(base.join("comp2.bin"), b"12345678").unwrap();
        let id_179 = EngineTransferIdentity::new(
            "test-sess-1",
            1,
            TransferDirection::DownloadToLocal,
            179,
        );
        mgr.track_engine_transfer_start_scoped(
            id_179.clone(),
            base.to_str().unwrap(),
            vec![
                ExpectedFileIntegritySpec {
                    relative_path: "comp1.bin".to_owned(),
                    expected_bytes: 4,
                    expected_sha256: sha256_hex(b"1234"),
                },
                ExpectedFileIntegritySpec {
                    relative_path: "comp2.bin".to_owned(),
                    expected_bytes: 6,
                    expected_sha256: sha256_hex(b"123456"),
                },
            ],
            10,
        )
        .unwrap();
        let err_comp = mgr
            .verify_and_finalize_engine_receive_scoped(&id_179, None)
            .unwrap_err();
        assert!(err_comp.contains("INTEGRITY_FILE_BYTE_SIZE_MISMATCH"));

        // F16 Negative 4: Unfinalized .download leftover even when destination file already exists (interrupted overwrite)
        fs::write(base.join("over.bin"), b"AAAA").unwrap();
        fs::write(base.join("over.bin.download"), b"AA").unwrap();
        let id_180 = EngineTransferIdentity::new(
            "test-sess-1",
            1,
            TransferDirection::DownloadToLocal,
            180,
        );
        mgr.track_engine_transfer_start_scoped(
            id_180.clone(),
            base.to_str().unwrap(),
            vec![ExpectedFileIntegritySpec {
                relative_path: "over.bin".to_owned(),
                expected_bytes: 4,
                expected_sha256: sha256_hex(b"AAAA"),
            }],
            4,
        )
        .unwrap();
        let err_stg = mgr
            .verify_and_finalize_engine_receive_scoped(&id_180, None)
            .unwrap_err();
        assert!(err_stg.contains("INTEGRITY_UNFINALIZED_DOWNLOAD_STAGING"));
        fs::remove_file(base.join("over.bin.download")).ok();

        // F16 Negative 5: 0-byte expected file with non-empty file on disk MUST fail closed
        let zero_dl = mgr
            .enqueue_download(
                "peer-home",
                "renders/empty_expected.bin",
                0,
                Some(sha256_hex(b"")),
                DuplicateFileStrategy::OverwriteConfirmed,
            )
            .unwrap();
        fs::write(&zero_dl.resolved_target_path, b"unexpected").unwrap();
        let err_zero = mgr.finalize_and_verify(&zero_dl.job_id).unwrap_err();
        assert!(err_zero.contains("INTEGRITY_BYTE_SIZE_MISMATCH"));

        // Single-file vs folder geometry resolution
        let single_entries = vec![FileEntry {
            name: String::new(),
            size: 4,
            sha256: sha256_hex(b"AAAA"),
            ..Default::default()
        }];
        let (single_root, single_specs) =
            resolve_transfer_manifest_root_and_specs(&base.join("single_upload.bin"), &single_entries)
                .unwrap();
        assert_eq!(single_root, base);
        assert_eq!(single_specs.len(), 1);
        assert_eq!(single_specs[0].relative_path, "single_upload.bin");

        // F16 Negative: Missing/empty sender SHA-256 in FileEntry is rejected BEFORE any disk write/rename
        let missing_sha_entries = vec![FileEntry {
            name: String::new(),
            size: 4,
            sha256: String::new(),
            ..Default::default()
        }];
        let missing_sha_err = resolve_transfer_manifest_root_and_specs(
            &base.join("unverified_single.bin"),
            &missing_sha_entries,
        )
        .unwrap_err();
        assert!(missing_sha_err.contains("INTEGRITY_REJECT_MISSING_SENDER_SHA256"));

        #[cfg(not(windows))]
        {
            let backslash_entries = vec![FileEntry {
                name: "sub\\evil.bin".to_owned(),
                size: 4,
                sha256: sha256_hex(b"AAAA"),
                ..Default::default()
            }];
            let bs_err =
                resolve_transfer_manifest_root_and_specs(&base, &backslash_entries).unwrap_err();
            assert!(bs_err.contains("SECURITY_REJECT_UNNORMALIZED_BACKSLASH"));
        }

        // F14 Negative: Symlink planted after validate_and_resolve_destination and before finalize is rejected
        #[cfg(unix)]
        {
            let outside_secret =
                std::env::temp_dir().join(format!("dv_race_secret_{}.txt", uuid::Uuid::new_v4()));
            fs::write(&outside_secret, b"SENSITIVE").unwrap();
            let id_80 = EngineTransferIdentity::new(
                "test-sess-1",
                1,
                TransferDirection::DownloadToLocal,
                80,
            );
            mgr.track_engine_transfer_start_scoped(
                id_80.clone(),
                base.to_str().unwrap(),
                vec![ExpectedFileIntegritySpec {
                    relative_path: "race_swap.txt".to_owned(),
                    expected_bytes: 9,
                    expected_sha256: sha256_hex(b"SENSITIVE"),
                }],
                9,
            )
            .unwrap();
            std::os::unix::fs::symlink(&outside_secret, base.join("race_swap.txt")).unwrap();
            assert!(mgr
                .verify_and_finalize_engine_receive_scoped(&id_80, None)
                .is_err());
            fs::remove_file(&outside_secret).ok();
        }

        fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn ft010_b05_concurrent_same_id_peers_directions_generations_and_race_isolation() {
        let workspace = std::env::temp_dir().join(format!("dv_ft010_b05_{}", uuid::Uuid::new_v4()));
        let root_a = workspace.join("peer_a");
        let root_b = workspace.join("peer_b");
        let root_c = workspace.join("peer_c");
        fs::create_dir_all(&root_a).unwrap();
        fs::create_dir_all(&root_b).unwrap();
        fs::create_dir_all(&root_c).unwrap();

        let mgr = std::sync::Arc::new(TransferQueueManager::new(workspace.clone()));

        // 0. Reject shared connection-0 and empty session_scope
        assert!(mgr
            .track_engine_transfer_start_scoped(
                EngineTransferIdentity::new("client-sess", 0, TransferDirection::DownloadToLocal, 1),
                root_a.to_str().unwrap(),
                vec![],
                0,
            )
            .unwrap_err()
            .contains("INTEGRITY_INVALID_IDENTITY"));
        assert!(mgr
            .track_engine_transfer_start_scoped(
                EngineTransferIdentity::new("   ", 10, TransferDirection::DownloadToLocal, 1),
                root_a.to_str().unwrap(),
                vec![],
                0,
            )
            .unwrap_err()
            .contains("INTEGRITY_INVALID_IDENTITY"));

        // 1. Exact Codex FT010-B05 collision_model reproduction:
        //    Connection A (conn 10, job 1) has CORRUPT bytes on disk.
        //    Connection B (conn 11, job 1) has VALID bytes on disk.
        //    Tracking B after A MUST NOT overwrite A's root, manifest, or peer_id;
        //    verifying A MUST FAIL while verifying B MUST PASS.
        fs::write(root_a.join("shared_id.bin"), b"CORRUPTED!").unwrap();
        fs::write(root_b.join("shared_id.bin"), b"VALID_PEER").unwrap();

        let id_peer_a = EngineTransferIdentity::new(
            "server-cm-conn-10",
            10,
            TransferDirection::DownloadToLocal,
            1,
        );
        let id_peer_b = EngineTransferIdentity::new(
            "server-cm-conn-11",
            11,
            TransferDirection::DownloadToLocal,
            1,
        );

        let (job_a_id, gen_a) = mgr
            .track_engine_transfer_start_scoped(
                id_peer_a.clone(),
                root_a.to_str().unwrap(),
                vec![ExpectedFileIntegritySpec {
                    relative_path: "shared_id.bin".to_owned(),
                    expected_bytes: 10,
                    expected_sha256: sha256_hex(b"EXPECTED_A"),
                }],
                10,
            )
            .unwrap();
        let (job_b_id, gen_b) = mgr
            .track_engine_transfer_start_scoped(
                id_peer_b.clone(),
                root_b.to_str().unwrap(),
                vec![ExpectedFileIntegritySpec {
                    relative_path: "shared_id.bin".to_owned(),
                    expected_bytes: 10,
                    expected_sha256: sha256_hex(b"VALID_PEER"),
                }],
                10,
            )
            .unwrap();
        assert_ne!(job_a_id, job_b_id);
        assert_ne!(gen_a, gen_b);

        let err_a = mgr
            .verify_and_finalize_engine_receive_scoped(&id_peer_a, Some(gen_a))
            .expect_err("corrupt peer A transfer must fail even when peer B reused engine_job_id 1");
        assert!(err_a.contains("INTEGRITY_SHA256_MISMATCH"));

        let ok_b = mgr
            .verify_and_finalize_engine_receive_scoped(&id_peer_b, Some(gen_b))
            .expect("valid peer B transfer must pass independently");
        assert_eq!(ok_b.status, TransferStatus::Completed);
        assert_eq!(ok_b.peer_id, "server-cm-conn-11:conn-11");
        assert_eq!(ok_b.dest_root_dir.as_deref(), root_b.to_str());
        assert_eq!(ok_b.integrity_state, "SENDER_SHA256_VERIFIED");

        let stored_a = mgr
            .list_jobs()
            .into_iter()
            .find(|j| j.job_id == job_a_id)
            .unwrap();
        assert_eq!(stored_a.status, TransferStatus::Failed);
        assert_eq!(stored_a.peer_id, "server-cm-conn-10:conn-10");
        assert_eq!(stored_a.dest_root_dir.as_deref(), root_a.to_str());
        assert!(stored_a.verified_sha256.is_none());

        // 2. Opposite directions with same (session_scope, conn_id, engine_job_id) + FT010-Q03 outbound status
        fs::write(root_b.join("duplex.bin"), b"DUPLEX_OK").unwrap();
        let id_dl = EngineTransferIdentity::new(
            "client-sess-9-r1",
            9,
            TransferDirection::DownloadToLocal,
            7,
        );
        let id_ul = EngineTransferIdentity::new(
            "client-sess-9-r1",
            9,
            TransferDirection::UploadToRemote,
            7,
        );
        mgr.track_engine_transfer_start_scoped(
            id_dl.clone(),
            root_b.to_str().unwrap(),
            vec![ExpectedFileIntegritySpec {
                relative_path: "duplex.bin".to_owned(),
                expected_bytes: 9,
                expected_sha256: sha256_hex(b"DUPLEX_OK"),
            }],
            9,
        )
        .unwrap();
        mgr.track_engine_transfer_start_scoped(
            id_ul.clone(),
            root_b.to_str().unwrap(),
            vec![ExpectedFileIntegritySpec {
                relative_path: "duplex.bin".to_owned(),
                expected_bytes: 9,
                expected_sha256: sha256_hex(b"DUPLEX_OK"),
            }],
            9,
        )
        .unwrap();

        // Resume + progress on DownloadToLocal must not mutate UploadToRemote
        mgr.resume_engine_transfer_scoped(&id_dl, 4).unwrap();
        let prog_dl = mgr.update_engine_progress_scoped(&id_dl, 7, 4096).unwrap();
        assert_eq!(prog_dl.transferred_bytes, 7);

        // Outbound UploadToRemote completion must NOT claim SENDER_SHA256_VERIFIED (FT010-Q03)
        let ul_done = mgr
            .track_engine_transfer_finish_scoped(&id_ul, None, true, false, None)
            .unwrap();
        assert_eq!(ul_done.status, TransferStatus::Completed);
        assert!(ul_done.verified_sha256.is_none());
        assert_eq!(
            ul_done.integrity_state,
            "SENDER_STREAM_EOF_CHECKED_UNVERIFIED_RECEIVER"
        );

        let dl_done = mgr
            .verify_and_finalize_engine_receive_scoped(&id_dl, None)
            .unwrap();
        assert_eq!(dl_done.status, TransferStatus::Completed);
        assert_eq!(dl_done.integrity_state, "SENDER_SHA256_VERIFIED");

        // 3. Cancellation isolation + Reconnect ID reuse (generation supersede + stale snapshot rejection)
        fs::write(root_c.join("gen1.bin"), b"GEN1").unwrap();
        fs::write(root_c.join("gen2.bin"), b"GEN2_OK").unwrap();
        let id_reuse = EngineTransferIdentity::new(
            "server-cm-conn-30",
            30,
            TransferDirection::DownloadToLocal,
            5,
        );
        let id_other = EngineTransferIdentity::new(
            "server-cm-conn-31",
            31,
            TransferDirection::DownloadToLocal,
            5,
        );
        let (job_g1_id, g1) = mgr
            .track_engine_transfer_start_scoped(
                id_reuse.clone(),
                root_c.to_str().unwrap(),
                vec![ExpectedFileIntegritySpec {
                    relative_path: "gen1.bin".to_owned(),
                    expected_bytes: 4,
                    expected_sha256: sha256_hex(b"GEN1"),
                }],
                4,
            )
            .unwrap();
        mgr.track_engine_transfer_start_scoped(
            id_other.clone(),
            root_c.to_str().unwrap(),
            vec![ExpectedFileIntegritySpec {
                relative_path: "gen2.bin".to_owned(),
                expected_bytes: 7,
                expected_sha256: sha256_hex(b"GEN2_OK"),
            }],
            7,
        )
        .unwrap();

        // Cancelling conn 31 job 5 does NOT cancel conn 30 job 5
        mgr.track_engine_transfer_finish_scoped(&id_other, None, false, true, Some("peer cancel"))
            .unwrap();
        assert!(mgr
            .verify_and_finalize_engine_receive_scoped(&id_other, None)
            .unwrap_err()
            .contains("INTEGRITY_NON_ACTIVE_JOB"));

        // Reconnect/reuse on conn 30 job 5 creates generation g2 and supersedes g1
        let (_, g2) = mgr
            .track_engine_transfer_start_scoped(
                id_reuse.clone(),
                root_c.to_str().unwrap(),
                vec![ExpectedFileIntegritySpec {
                    relative_path: "gen2.bin".to_owned(),
                    expected_bytes: 7,
                    expected_sha256: sha256_hex(b"GEN2_OK"),
                }],
                7,
            )
            .unwrap();
        assert!(g2 > g1);
        let stale_err = mgr
            .verify_and_finalize_engine_receive_scoped(&id_reuse, Some(g1))
            .expect_err("stale generation g1 must be rejected");
        assert!(stale_err.contains("INTEGRITY_STALE_GENERATION"));

        let g1_record = mgr
            .list_jobs()
            .into_iter()
            .find(|j| j.job_id == job_g1_id)
            .unwrap();
        assert_eq!(g1_record.status, TransferStatus::Failed);
        assert_eq!(g1_record.integrity_state, "SUPERSEDED_BY_NEW_GENERATION");
        assert_eq!(g1_record.relative_path, "gen1.bin");

        let g2_ok = mgr
            .verify_and_finalize_engine_receive_scoped(&id_reuse, Some(g2))
            .unwrap();
        assert_eq!(g2_ok.status, TransferStatus::Completed);
        assert_eq!(g2_ok.relative_path, "gen2.bin");

        // 4. Multi-threaded stale-snapshot race: concurrent supersede/cancel during file hashing
        let large_payload = vec![0x5Au8; 8 * 1024 * 1024];
        let large_sha = sha256_hex(&large_payload);
        fs::write(root_c.join("race_large.bin"), &large_payload).unwrap();
        let id_race = EngineTransferIdentity::new(
            "server-cm-conn-99",
            99,
            TransferDirection::DownloadToLocal,
            42,
        );
        let (race_job_id, race_gen) = mgr
            .track_engine_transfer_start_scoped(
                id_race.clone(),
                root_c.to_str().unwrap(),
                vec![ExpectedFileIntegritySpec {
                    relative_path: "race_large.bin".to_owned(),
                    expected_bytes: large_payload.len() as u64,
                    expected_sha256: large_sha,
                }],
                large_payload.len() as u64,
            )
            .unwrap();

        let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));
        std::thread::scope(|s| {
            let mgr_verify = std::sync::Arc::clone(&mgr);
            let b_verify = std::sync::Arc::clone(&barrier);
            let id_v = id_race.clone();
            let h1 = s.spawn(move || {
                b_verify.wait();
                mgr_verify.verify_and_finalize_engine_receive_scoped(&id_v, Some(race_gen))
            });

            let mgr_cancel = std::sync::Arc::clone(&mgr);
            let b_cancel = std::sync::Arc::clone(&barrier);
            let jid = race_job_id.clone();
            let h2 = s.spawn(move || {
                b_cancel.wait();
                mgr_cancel.cancel(&jid)
            });

            let verify_res = h1.join().unwrap();
            let cancel_res = h2.join().unwrap();
            // Exactly one terminal outcome must hold consistently: never both Cancelled AND Completed!
            let final_job = mgr
                .list_jobs()
                .into_iter()
                .find(|j| j.job_id == race_job_id)
                .unwrap();
            if cancel_res.is_ok() {
                assert!(verify_res.is_err());
                assert_eq!(final_job.status, TransferStatus::Cancelled);
                assert!(final_job.verified_sha256.is_none());
            } else {
                assert!(verify_res.is_ok());
                assert_eq!(final_job.status, TransferStatus::Completed);
            }
        });

        fs::remove_dir_all(&workspace).ok();
    }
}

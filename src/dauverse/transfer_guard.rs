use super::crypto_util::sha256_file;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Component, Path, PathBuf},
    sync::Mutex,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DuplicateFileStrategy {
    RequireConfirmation,
    AutoRename,
    OverwriteConfirmed,
    Skip,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TransferDirection {
    UploadToRemote,
    DownloadToLocal,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferJob {
    pub job_id: String,
    pub peer_id: String,
    pub direction: TransferDirection,
    pub relative_path: String,
    pub resolved_target_path: String,
    pub total_bytes: u64,
    pub transferred_bytes: u64,
    pub resume_offset: u64,
    pub expected_sha256: Option<String>,
    pub verified_sha256: Option<String>,
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
    let Ok(meta) = fs::symlink_metadata(path) else {
        return Ok(());
    };
    if meta.file_type().is_symlink() {
        return Err(format!(
            "SECURITY_REJECT_SYMLINK: refusing symlink component '{}'",
            path.display()
        ));
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
        if (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
            return Err(format!(
                "SECURITY_REJECT_REPARSE_POINT: refusing junction/reparse point '{}'",
                path.display()
            ));
        }
    }
    Ok(())
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
        return Err("SECURITY_REJECT_ABSOLUTE_OR_UNC_PATH: absolute/UNC/drive path forbidden".to_owned());
    }
    if untrusted_relative_path.contains('\\') {
        for raw_part in untrusted_relative_path.split('\\') {
            if raw_part == ".." || raw_part.is_empty() {
                return Err("SECURITY_REJECT_PATH_TRAVERSAL: backslash traversal or empty segment".to_owned());
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

pub struct TransferQueueManager {
    authorized_root: Mutex<PathBuf>,
    bandwidth_limit_kbps: Mutex<Option<u32>>,
    jobs: Mutex<Vec<TransferJob>>,
}

impl TransferQueueManager {
    pub fn new(default_root: PathBuf) -> Self {
        Self {
            authorized_root: Mutex::new(default_root),
            bandwidth_limit_kbps: Mutex::new(None),
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
        let now = chrono::Utc::now().to_rfc3339();
        let job = TransferJob {
            job_id: uuid::Uuid::new_v4().to_string(),
            peer_id: peer_id.to_owned(),
            direction: TransferDirection::DownloadToLocal,
            relative_path: untrusted_relative_path.to_owned(),
            resolved_target_path: resolved.to_string_lossy().into_owned(),
            total_bytes,
            transferred_bytes: 0,
            resume_offset: 0,
            expected_sha256,
            verified_sha256: None,
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
        if matches!(job.status, TransferStatus::Cancelled | TransferStatus::Completed) {
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
                job.speed_bytes_per_sec = 0;
                job.eta_seconds = None;
                Ok(())
            }
        })
    }

    pub fn retry(&self, job_id: &str) -> Result<TransferJob, String> {
        self.transition(job_id, |job| {
            if matches!(job.status, TransferStatus::Failed | TransferStatus::Cancelled) {
                job.status = TransferStatus::Queued;
                job.error_message = None;
                Ok(())
            } else {
                Err("only failed or cancelled jobs can be retried".to_owned())
            }
        })
    }

    pub fn finalize_and_verify(&self, job_id: &str) -> Result<TransferJob, String> {
        let target_path = {
            let jobs = self.jobs.lock().unwrap();
            let job = jobs
                .iter()
                .find(|j| j.job_id == job_id)
                .ok_or_else(|| "transfer job not found".to_owned())?;
            PathBuf::from(&job.resolved_target_path)
        };

        check_no_symlink_or_reparse(&target_path)?;
        let actual_hash = sha256_file(&target_path)?;

        self.transition(job_id, |job| {
            if let Some(expected) = &job.expected_sha256 {
                if !expected.trim().eq_ignore_ascii_case(&actual_hash) {
                    job.status = TransferStatus::Failed;
                    job.error_message = Some(format!(
                        "INTEGRITY_SHA256_MISMATCH: expected {}, got {}",
                        expected.trim(),
                        actual_hash
                    ));
                    return Err(job.error_message.clone().unwrap());
                }
            }
            job.verified_sha256 = Some(actual_hash);
            job.transferred_bytes = job.total_bytes;
            job.speed_bytes_per_sec = 0;
            job.eta_seconds = Some(0);
            job.status = TransferStatus::Completed;
            Ok(())
        })
    }

    pub fn list_jobs(&self) -> Vec<TransferJob> {
        self.jobs.lock().unwrap().clone()
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

        fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn queue_lifecycle_duplicate_rename_and_sha256_integrity() {
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
        let expected_sha = super::super::crypto_util::sha256_hex(payload);

        let job = mgr
            .enqueue_download(
                "peer-home",
                "renders/comfy_output.mp4",
                payload.len() as u64,
                Some(expected_sha),
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
        assert!(done.verified_sha256.is_some());

        let bad_job = mgr
            .enqueue_download(
                "peer-home",
                "renders/corrupted.bin",
                5,
                Some("0000000000000000000000000000000000000000000000000000000000000000".to_owned()),
                DuplicateFileStrategy::OverwriteConfirmed,
            )
            .unwrap();
        fs::write(&bad_job.resolved_target_path, b"hello").unwrap();
        assert!(mgr.finalize_and_verify(&bad_job.job_id).is_err());

        fs::remove_dir_all(&base).ok();
    }
}

#[cfg(windows)]
use std::os::windows::prelude::*;
use std::{
    fmt::{Debug, Display},
    io::{Cursor, Read},
    path::{Path, PathBuf},
    sync::atomic::{AtomicI32, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use serde_derive::{Deserialize, Serialize};
use serde_json::json;
use tokio::{
    fs::File,
    io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt, BufStream as TokioBufStream},
};

use crate::message_proto::*;
// https://doc.rust-lang.org/std/os/windows/fs/trait.MetadataExt.html
use hbb_common::{
    anyhow::anyhow,
    bail,
    compress::{compress, decompress},
    config::Config,
    get_version_number,
    sha2::{Digest, Sha256},
    ResultType, Stream,
};

static NEXT_JOB_ID: AtomicI32 = AtomicI32::new(1);

#[cfg(any(target_os = "android", test))]
pub mod android;

#[cfg(any(target_os = "android", all(test, unix)))]
mod android_transfer;

#[cfg(any(target_os = "android", all(test, unix)))]
mod android_descriptor;

pub mod download;

#[cfg(test)]
#[path = "fs/download_tests.rs"]
mod download_tests;

pub fn get_next_job_id() -> i32 {
    NEXT_JOB_ID.fetch_add(1, Ordering::SeqCst)
}

pub fn update_next_job_id(id: i32) {
    NEXT_JOB_ID.store(id, Ordering::SeqCst);
}

pub fn read_dir(path: &Path, include_hidden: bool) -> ResultType<FileDirectory> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(path) {
        return android::read_dir(&get_string(path), include_hidden);
    }
    let mut dir = FileDirectory {
        path: get_string(path),
        ..Default::default()
    };
    #[cfg(windows)]
    if "/" == &get_string(path) {
        let drives = unsafe { winapi::um::fileapi::GetLogicalDrives() };
        for i in 0..32 {
            if drives & (1 << i) != 0 {
                let name = format!(
                    "{}:",
                    std::char::from_u32('A' as u32 + i as u32).unwrap_or('A')
                );
                dir.entries.push(FileEntry {
                    name,
                    entry_type: FileType::DirDrive.into(),
                    ..Default::default()
                });
            }
        }
        return Ok(dir);
    }
    for entry in path.read_dir()?.flatten() {
        let p = entry.path();
        let name = p
            .file_name()
            .map(|p| p.to_str().unwrap_or(""))
            .unwrap_or("")
            .to_owned();
        if name.is_empty() {
            continue;
        }
        let mut is_hidden = false;
        let meta;
        if let Ok(tmp) = std::fs::symlink_metadata(&p) {
            meta = tmp;
        } else {
            continue;
        }
        // docs.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants
        #[cfg(windows)]
        if meta.file_attributes() & 0x2 != 0 {
            is_hidden = true;
        }
        #[cfg(not(windows))]
        if name.find('.').unwrap_or(usize::MAX) == 0 {
            is_hidden = true;
        }
        if is_hidden && !include_hidden {
            continue;
        }
        let (entry_type, size) = {
            if p.is_dir() {
                if meta.file_type().is_symlink() {
                    (FileType::DirLink.into(), 0)
                } else {
                    (FileType::Dir.into(), 0)
                }
            } else if meta.file_type().is_symlink() {
                (FileType::FileLink.into(), 0)
            } else {
                (FileType::File.into(), meta.len())
            }
        };
        let modified_time = meta
            .modified()
            .map(|x| {
                x.duration_since(std::time::SystemTime::UNIX_EPOCH)
                    .map(|x| x.as_secs())
                    .unwrap_or(0)
            })
            .unwrap_or(0);
        dir.entries.push(FileEntry {
            name: get_file_name(&p),
            entry_type,
            is_hidden,
            size,
            modified_time,
            ..Default::default()
        });
    }
    Ok(dir)
}

#[inline]
pub fn get_file_name(p: &Path) -> String {
    p.file_name()
        .map(|p| p.to_str().unwrap_or(""))
        .unwrap_or("")
        .to_owned()
}

#[inline]
pub fn get_string(path: &Path) -> String {
    path.to_str().unwrap_or("").to_owned()
}

#[inline]
pub fn get_path(path: &str) -> PathBuf {
    Path::new(path).to_path_buf()
}

#[inline]
pub fn get_home_as_string() -> String {
    #[cfg(target_os = "android")]
    match android::home() {
        Ok(Some(path)) => return path,
        Ok(None) => {}
        Err(error) => {
            log::trace!("Unable to load the selected document location: {}", error);
            return android::ROOT.trim_end_matches('/').to_owned();
        }
    }
    get_string(&Config::get_home())
}

fn read_dir_recursive(
    path: &Path,
    prefix: &Path,
    include_hidden: bool,
) -> ResultType<Vec<FileEntry>> {
    let mut files = Vec::new();
    if path.is_dir() {
        // to-do: symbol link handling, cp the link rather than the content
        // to-do: file mode, for unix
        let fd = read_dir(path, include_hidden)?;
        for entry in fd.entries.iter() {
            match entry.entry_type.enum_value() {
                Ok(FileType::File) => {
                    let mut entry = entry.clone();
                    entry.name = get_string(&prefix.join(entry.name));
                    files.push(entry);
                }
                Ok(FileType::Dir) => {
                    if let Ok(mut tmp) = read_dir_recursive(
                        &path.join(&entry.name),
                        &prefix.join(&entry.name),
                        include_hidden,
                    ) {
                        for entry in tmp.drain(0..) {
                            files.push(entry);
                        }
                    }
                }
                _ => {}
            }
        }
        Ok(files)
    } else if path.is_file() {
        let (size, modified_time) = if let Ok(meta) = std::fs::metadata(path) {
            (
                meta.len(),
                meta.modified()
                    .map(|x| {
                        x.duration_since(std::time::SystemTime::UNIX_EPOCH)
                            .map(|x| x.as_secs())
                            .unwrap_or(0)
                    })
                    .unwrap_or(0),
            )
        } else {
            (0, 0)
        };
        files.push(FileEntry {
            entry_type: FileType::File.into(),
            size,
            modified_time,
            ..Default::default()
        });
        Ok(files)
    } else {
        bail!("Not exists");
    }
}

pub fn get_recursive_files(path: &str, include_hidden: bool) -> ResultType<Vec<FileEntry>> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(Path::new(path)) {
        return android::recursive_files(path, include_hidden);
    }
    read_dir_recursive(&get_path(path), &get_path(""), include_hidden)
}

fn read_empty_dirs_recursive(
    path: &Path,
    prefix: &Path,
    include_hidden: bool,
) -> ResultType<Vec<FileDirectory>> {
    let mut dirs = Vec::new();
    if path.is_dir() {
        // to-do: symbol link handling, cp the link rather than the content
        // to-do: file mode, for unix
        let fd = read_dir(path, include_hidden)?;
        if fd.entries.is_empty() {
            dirs.push(fd);
        } else {
            for entry in fd.entries.iter() {
                match entry.entry_type.enum_value() {
                    Ok(FileType::Dir) => {
                        if let Ok(mut tmp) = read_empty_dirs_recursive(
                            &path.join(&entry.name),
                            &prefix.join(&entry.name),
                            include_hidden,
                        ) {
                            for entry in tmp.drain(0..) {
                                dirs.push(entry);
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        Ok(dirs)
    } else if path.is_file() {
        Ok(dirs)
    } else {
        bail!("Not exists");
    }
}

pub fn get_empty_dirs_recursive(
    path: &str,
    include_hidden: bool,
) -> ResultType<Vec<FileDirectory>> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(Path::new(path)) {
        return android::empty_dirs(path, include_hidden);
    }
    read_empty_dirs_recursive(&get_path(path), &get_path(""), include_hidden)
}

#[inline]
pub fn is_file_exists(file_path: &str) -> bool {
    return Path::new(file_path).exists();
}

#[inline]
pub fn can_enable_overwrite_detection(version: i64) -> bool {
    version >= get_version_number("1.1.10")
}

#[repr(i32)]
#[derive(Copy, Clone, Serialize, Debug, PartialEq)]
pub enum JobType {
    Generic = 0,
    Printer = 1,
}

impl Default for JobType {
    fn default() -> Self {
        JobType::Generic
    }
}

impl From<JobType> for file_transfer_send_request::FileType {
    fn from(t: JobType) -> Self {
        match t {
            JobType::Generic => file_transfer_send_request::FileType::Generic,
            JobType::Printer => file_transfer_send_request::FileType::Printer,
        }
    }
}

impl From<i32> for JobType {
    fn from(value: i32) -> Self {
        match value {
            0 => JobType::Generic,
            1 => JobType::Printer,
            _ => JobType::Generic,
        }
    }
}

impl Into<i32> for JobType {
    fn into(self) -> i32 {
        self as i32
    }
}

impl JobType {
    pub fn from_proto(t: ::protobuf::EnumOrUnknown<file_transfer_send_request::FileType>) -> Self {
        match t.enum_value() {
            Ok(file_transfer_send_request::FileType::Generic) => JobType::Generic,
            Ok(file_transfer_send_request::FileType::Printer) => JobType::Printer,
            _ => JobType::Generic,
        }
    }
}

#[derive(Debug)]
pub enum DataSource {
    FilePath(PathBuf),
    MemoryCursor(Cursor<Vec<u8>>),
}

impl Default for DataSource {
    fn default() -> Self {
        DataSource::FilePath(PathBuf::new())
    }
}

impl serde::Serialize for DataSource {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        match self {
            DataSource::FilePath(p) => serializer.serialize_str(p.to_str().unwrap_or("")),
            DataSource::MemoryCursor(_) => serializer.serialize_str(""),
        }
    }
}

impl Display for DataSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DataSource::FilePath(p) => write!(f, "File: {}", p.to_string_lossy().to_string()),
            DataSource::MemoryCursor(_) => write!(f, "Bytes"),
        }
    }
}

impl DataSource {
    fn to_meta(&self) -> String {
        match self {
            DataSource::FilePath(p) => p.to_string_lossy().to_string(),
            DataSource::MemoryCursor(_) => "".to_string(),
        }
    }
}

enum DataStream {
    FileStream(File),
    BufStream(TokioBufStream<Cursor<Vec<u8>>>),
}

impl Debug for DataStream {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DataStream::FileStream(fs) => write!(f, "{:?}", fs),
            DataStream::BufStream(_) => write!(f, "BufStream"),
        }
    }
}

impl DataStream {
    async fn write_all(&mut self, buf: &[u8]) -> ResultType<()> {
        match self {
            DataStream::FileStream(fs) => fs.write_all(buf).await?,
            DataStream::BufStream(bs) => bs.write_all(buf).await?,
        }
        Ok(())
    }

    async fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            DataStream::FileStream(fs) => fs.read(buf).await,
            DataStream::BufStream(bs) => bs.read(buf).await,
        }
    }
}

#[derive(Default, Serialize, Deserialize, Debug)]
pub struct FileDigest {
    pub size: u64,
    pub modified: u64,
}

#[derive(Default, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct TransferJob {
    #[cfg(any(target_os = "android", all(test, unix)))]
    #[serde(skip)]
    document_transfer: android_transfer::DocumentTransfer,
    pub id: i32,
    pub r#type: JobType,
    pub remote: String,
    pub data_source: DataSource,
    pub show_hidden: bool,
    pub is_remote: bool,
    pub is_last_job: bool,
    pub is_resume: bool,
    pub file_num: i32,
    #[serde(skip_serializing)]
    files: Vec<FileEntry>,
    pub conn_id: i32, // server only

    #[serde(skip_serializing)]
    data_stream: Option<DataStream>,
    pub total_size: u64,
    finished_size: u64,
    transferred: u64,
    enable_overwrite_detection: bool,
    file_confirmed: bool,
    // indicating the last file is skipped
    file_skipped: bool,
    file_is_waiting: bool,
    default_overwrite_strategy: Option<bool>,
    #[serde(skip_serializing)]
    digest: FileDigest,
    #[serde(skip)]
    download: Option<download::DownloadState>,
    #[serde(skip)]
    read_stream_integrity: Option<(usize, Sha256, u64)>,
    #[serde(skip)]
    resume_failed_err: Option<String>,
}

#[derive(Debug, Default, Serialize, Deserialize, Clone)]
pub struct TransferJobMeta {
    #[serde(default)]
    pub id: i32,
    #[serde(default)]
    pub remote: String,
    #[serde(default)]
    pub to: String,
    #[serde(default)]
    pub show_hidden: bool,
    #[serde(default)]
    pub file_num: i32,
    #[serde(default)]
    pub is_remote: bool,
}

#[derive(Debug, Default, Serialize, Deserialize, Clone)]
pub struct RemoveJobMeta {
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub is_remote: bool,
    #[serde(default)]
    pub no_confirm: bool,
}

#[inline]
fn get_ext(name: &str) -> &str {
    if let Some(i) = name.rfind('.') {
        return &name[i + 1..];
    }
    ""
}

#[inline]
fn is_compressed_file(name: &str) -> bool {
    let compressed_exts = ["xz", "gz", "zip", "7z", "rar", "bz2", "tgz", "png", "jpg"];
    let ext = get_ext(name);
    compressed_exts.iter().any(|x| ext.eq_ignore_ascii_case(x))
}

pub fn validate_file_name_no_traversal(name: &str) -> ResultType<()> {
    if name.bytes().any(|b| b == 0) {
        bail!("file name contains null bytes");
    }
    let has_traversal = name
        .split(|c: char| c == '/' || (cfg!(windows) && c == '\\'))
        .filter(|s| !s.is_empty())
        .any(|s| s == "..");
    if has_traversal {
        bail!("path traversal detected in file name");
    }
    #[cfg(windows)]
    {
        if name.len() >= 2 {
            let bytes = name.as_bytes();
            if bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
                bail!("absolute path detected in file name");
            }
        }
        if name.starts_with('/') || name.starts_with('\\') {
            bail!("absolute path detected in file name");
        }
    }
    #[cfg(not(windows))]
    if name.starts_with('/') {
        bail!("absolute path detected in file name");
    }
    Ok(())
}

fn validate_transfer_file_names(files: &[FileEntry]) -> ResultType<()> {
    // Single-file transfer may use an empty relative name, because
    // the destination file path is carried by transfer metadata.
    if files.len() == 1 && files.first().map_or(false, |f| f.name.is_empty()) {
        return Ok(());
    }
    for file in files {
        if file.name.is_empty() {
            bail!("empty file name in multi-file transfer");
        }
        validate_file_name_no_traversal(&file.name)?;
    }
    Ok(())
}

#[inline]
fn validate_fs_path_argument(path: &str, arg_name: &str) -> ResultType<()> {
    if path.is_empty() {
        bail!("{arg_name} cannot be empty");
    }
    if path.bytes().any(|b| b == 0) {
        bail!("{arg_name} contains null bytes");
    }
    Ok(())
}

fn validate_no_symlink_components(base: &PathBuf, name: &str) -> ResultType<()> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(base) {
        // Document IDs are resolved and confined to their grant by Android, not the OS filesystem.
        return Ok(());
    }
    if name.is_empty() {
        return Ok(());
    }
    let mut current = base.clone();
    for component in Path::new(name).components() {
        match component {
            std::path::Component::Normal(seg) => {
                current.push(seg);
                // Best-effort guard: path-based checks are inherently TOCTOU-prone
                // if local filesystem state changes between validation and write.
                match std::fs::symlink_metadata(&current) {
                    Ok(meta) => {
                        // This is inherent to filesystem-based checks and acknowledged as a limitation.
                        // For true protection, you'd need openat(2) / O_NOFOLLOW at write time.
                        if meta.file_type().is_symlink() {
                            bail!("symlink path component is not allowed");
                        }
                        #[cfg(windows)]
                        if (meta.file_attributes() & 0x0400) != 0 {
                            bail!("symlink or reparse point path component is not allowed");
                        }
                    }
                    Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                        // Component does not exist yet, continue best-effort validation.
                    }
                    Err(err) => {
                        bail!(
                            "failed to validate path component '{}': {}",
                            current.display(),
                            err
                        );
                    }
                }
            }
            std::path::Component::CurDir => {}
            _ => {
                bail!("invalid file name component");
            }
        }
    }
    Ok(())
}

/// Validate an untrusted relative file name and existing path components before joining it.
pub fn join_validated_path(base: &PathBuf, name: &str) -> ResultType<PathBuf> {
    validate_file_name_no_traversal(name)?;
    validate_no_symlink_components(base, name)?;
    Ok(TransferJob::join(base, name))
}

fn is_existing_symlink_or_reparse(path: &Path) -> bool {
    let Ok(meta) = std::fs::symlink_metadata(path) else {
        return false;
    };
    if meta.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
        if (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
            return true;
        }
    }
    false
}

pub fn compute_file_sha256_and_size(path: &Path) -> ResultType<(String, u64)> {
    if is_existing_symlink_or_reparse(path) {
        bail!(
            "refusing to hash symlink or reparse point '{}'",
            path.display()
        );
    }
    let mut f = std::fs::File::open(path)?;
    let meta = f.metadata()?;
    if meta.file_type().is_symlink() || !meta.file_type().is_file() {
        bail!("refusing to hash non-regular file '{}'", path.display());
    }
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 65536];
    let mut total_bytes = 0u64;
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        total_bytes = total_bytes.saturating_add(n as u64);
    }
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(64);
    for byte in digest.iter() {
        use std::fmt::Write as _;
        let _ = write!(&mut hex, "{byte:02x}");
    }
    Ok((hex, total_bytes))
}

pub(crate) fn constant_time_eq_ascii_hex(a: &str, b: &str) -> bool {
    let a = a.trim();
    let b = b.trim();
    if a.len() != 64 || b.len() != 64 {
        return false;
    }
    let mut diff = 0u8;
    for (ab, bb) in a.bytes().zip(b.bytes()) {
        if !ab.is_ascii_hexdigit() || !bb.is_ascii_hexdigit() {
            return false;
        }
        diff |= ab.to_ascii_lowercase() ^ bb.to_ascii_lowercase();
    }
    diff == 0
}

pub(super) fn query_std_handle_link_count(file: &std::fs::File) -> ResultType<u64> {
    #[cfg(unix)]
    {
        Ok(std::os::unix::fs::MetadataExt::nlink(&file.metadata()?))
    }
    #[cfg(windows)]
    {
        use std::mem::MaybeUninit;
        use winapi::{
            shared::minwindef::FALSE,
            um::fileapi::{GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION},
        };
        let mut info = MaybeUninit::<BY_HANDLE_FILE_INFORMATION>::uninit();
        if unsafe { GetFileInformationByHandle(file.as_raw_handle() as _, info.as_mut_ptr()) }
            == FALSE
        {
            bail!(
                "GetFileInformationByHandle failed: {}",
                std::io::Error::last_os_error()
            );
        }
        Ok(u64::from(unsafe { info.assume_init() }.nNumberOfLinks))
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = file;
        Ok(1)
    }
}

pub(super) fn verify_std_handle_single_link_regular_confined(
    file: &std::fs::File,
    #[allow(unused_variables)] pre_captured_canon_root: Option<&Path>,
) -> ResultType<()> {
    let meta = file.metadata()?;
    if meta.file_type().is_symlink() || !meta.file_type().is_file() {
        bail!("refusing non-regular or symlink file handle");
    }
    #[cfg(windows)]
    {
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
        if (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
            bail!("refusing reparse file handle");
        }
        verify_windows_raw_handle_confined(file.as_raw_handle(), pre_captured_canon_root)?;
    }
    let links = query_std_handle_link_count(file)?;
    if links != 1 {
        bail!("refusing hard-linked file handle (links={links})");
    }
    Ok(())
}

pub(super) fn open_readonly_no_follow_single_link(
    path: &Path,
    pre_captured_canon_root: Option<&Path>,
) -> ResultType<std::fs::File> {
    if is_existing_symlink_or_reparse(path) {
        bail!(
            "refusing symlink or reparse path '{}'",
            path.display()
        );
    }
    #[cfg(unix)]
    let f = {
        use std::os::unix::fs::OpenOptionsExt;
        std::fs::OpenOptions::new()
            .read(true)
            .custom_flags(hbb_common::libc::O_NOFOLLOW)
            .open(path)?
    };
    #[cfg(windows)]
    let f = {
        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
        std::fs::OpenOptions::new()
            .read(true)
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .open(path)?
    };
    #[cfg(not(any(unix, windows)))]
    let f = std::fs::File::open(path)?;

    verify_std_handle_single_link_regular_confined(&f, pre_captured_canon_root)?;
    Ok(f)
}

pub(super) fn ensure_destination_safe_for_overwrite(
    target: &Path,
    pre_captured_canon_root: Option<&Path>,
) -> ResultType<()> {
    match std::fs::symlink_metadata(target) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
        Ok(meta) => {
            if meta.file_type().is_symlink() || !meta.file_type().is_file() {
                bail!(
                    "refusing overwrite onto symlink or non-regular path '{}'",
                    target.display()
                );
            }
            #[cfg(windows)]
            {
                const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
                if (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
                    bail!(
                        "refusing overwrite onto reparse target '{}'",
                        target.display()
                    );
                }
            }
            let _verified = open_readonly_no_follow_single_link(target, pre_captured_canon_root)?;
            Ok(())
        }
    }
}

pub(crate) fn verify_staging_file_sha256_confined(
    staging_path: &Path,
    expected_size: u64,
    expected_sha256: &str,
    pre_captured_canon_root: Option<&Path>,
) -> ResultType<()> {
    let mut f = open_readonly_no_follow_single_link(staging_path, pre_captured_canon_root)?;
    if expected_sha256.trim().is_empty() {
        return Ok(());
    }
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 65536];
    let mut actual_size: u64 = 0;
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        actual_size = actual_size.saturating_add(n as u64);
    }
    if actual_size != expected_size {
        bail!(
            "transfer staging size mismatch for '{}': expected {} bytes, got {} bytes",
            staging_path.display(),
            expected_size,
            actual_size
        );
    }
    let digest = hasher.finalize();
    let mut actual_sha = String::with_capacity(64);
    for byte in digest.iter() {
        use std::fmt::Write as _;
        let _ = write!(&mut actual_sha, "{byte:02x}");
    }
    if !constant_time_eq_ascii_hex(&actual_sha, expected_sha256) {
        bail!(
            "transfer staging SHA-256 mismatch for '{}': expected {}, got {}",
            staging_path.display(),
            expected_sha256.trim(),
            actual_sha
        );
    }
    Ok(())
}

pub(crate) fn verify_staging_file_sha256(
    staging_path: &Path,
    expected_size: u64,
    expected_sha256: &str,
) -> ResultType<()> {
    verify_staging_file_sha256_confined(staging_path, expected_size, expected_sha256, None)
}

#[cfg(windows)]
pub(super) fn capture_confined_transfer_root(root: &Path) -> ResultType<PathBuf> {
    if is_existing_symlink_or_reparse(root) {
        bail!(
            "refusing symlink or reparse transfer root '{}'",
            root.display()
        );
    }
    if !root.exists() {
        std::fs::create_dir_all(root)?;
    }
    if is_existing_symlink_or_reparse(root) {
        bail!(
            "refusing symlink or reparse transfer root '{}'",
            root.display()
        );
    }
    Ok(root.canonicalize()?)
}

#[cfg(windows)]
pub(super) fn verify_windows_raw_handle_confined(
    raw_handle: std::os::windows::io::RawHandle,
    pre_captured_canon_root: Option<&Path>,
) -> ResultType<()> {
    use winapi::um::fileapi::GetFinalPathNameByHandleW;
    let mut cap: usize = 1024;
    let final_str = loop {
        let mut buf = vec![0u16; cap];
        let len =
            unsafe { GetFinalPathNameByHandleW(raw_handle as _, buf.as_mut_ptr(), cap as u32, 0) }
                as usize;
        if len == 0 {
            bail!(
                "GetFinalPathNameByHandleW failed: {}",
                std::io::Error::last_os_error()
            );
        }
        if len < cap {
            break String::from_utf16(&buf[..len])
                .map_err(|e| anyhow!("GetFinalPathNameByHandleW returned invalid UTF-16: {e}"))?;
        }
        if cap >= 65536 {
            bail!("GetFinalPathNameByHandleW path exceeded 65536 wide chars");
        }
        cap = (len + 1).max(cap.saturating_mul(2));
    };
    let norm = final_str.replace('/', "\\");
    if norm.starts_with("\\\\.\\") || norm.starts_with("\\??\\") {
        bail!("raw device or NT namespace handle rejected '{}'", norm);
    }
    let stripped = if let Some(unc) = norm.strip_prefix("\\\\?\\UNC\\") {
        format!("\\\\{unc}")
    } else if let Some(local) = norm.strip_prefix("\\\\?\\") {
        local.to_owned()
    } else {
        norm
    };
    let tail_after_drive = if stripped.len() >= 2
        && stripped.as_bytes()[0].is_ascii_alphabetic()
        && stripped.as_bytes()[1] == b':'
    {
        &stripped[2..]
    } else {
        stripped.as_str()
    };
    if tail_after_drive.contains(':') {
        bail!("NTFS alternate data stream rejected on handle '{}'", stripped);
    }
    if let Some(canon_root) = pre_captured_canon_root.filter(|p| !p.as_os_str().is_empty()) {
        let canon_str = canon_root.to_string_lossy().replace('/', "\\");
        let root_stripped = if let Some(unc) = canon_str.strip_prefix("\\\\?\\UNC\\") {
            format!("\\\\{unc}")
        } else if let Some(local) = canon_str.strip_prefix("\\\\?\\") {
            local.to_owned()
        } else {
            canon_str
        };
        let root_trimmed = root_stripped.trim_end_matches('\\').to_ascii_lowercase();
        let file_lower = stripped.to_ascii_lowercase();
        if !file_lower.starts_with(&root_trimmed)
            || file_lower.as_bytes().get(root_trimmed.len()) != Some(&b'\\')
        {
            bail!(
                "opened file handle '{}' escaped transfer root '{}'",
                stripped,
                root_stripped
            );
        }
    }
    Ok(())
}

pub(super) fn prepare_clean_exclusive_staging_slot(
    path: &Path,
    pre_captured_canon_root: Option<&Path>,
) -> ResultType<()> {
    match std::fs::symlink_metadata(path) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
        Ok(meta) => {
            if meta.file_type().is_symlink() || !meta.file_type().is_file() {
                bail!(
                    "refusing symlink or non-regular preexisting staging path '{}'",
                    path.display()
                );
            }
            #[cfg(windows)]
            {
                const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
                if (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
                    bail!(
                        "refusing reparse preexisting staging path '{}'",
                        path.display()
                    );
                }
            }
            // Read-only single-link check BEFORE unlinking: if hard-linked (links > 1), reject immediately without touching bytes!
            {
                let _ro = open_readonly_no_follow_single_link(path, pre_captured_canon_root)?;
            }
            std::fs::remove_file(path)?;
            Ok(())
        }
    }
}

pub(super) fn create_exclusive_staging_file_no_follow(
    path: &Path,
    pre_captured_canon_root: Option<&Path>,
) -> ResultType<std::fs::File> {
    prepare_clean_exclusive_staging_slot(path, pre_captured_canon_root)?;
    #[cfg(unix)]
    let opened = {
        use std::os::unix::fs::OpenOptionsExt;
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .custom_flags(hbb_common::libc::O_NOFOLLOW)
            .open(path)?
    };
    #[cfg(windows)]
    let opened = {
        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .open(path)?
    };
    #[cfg(not(any(unix, windows)))]
    let opened = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)?;

    verify_std_handle_single_link_regular_confined(&opened, pre_captured_canon_root)?;
    Ok(opened)
}

pub(super) fn write_exclusive_digest_file_no_follow(
    path: &Path,
    bytes: &[u8],
    pre_captured_canon_root: Option<&Path>,
) -> ResultType<()> {
    use std::io::Write as _;
    let mut f = create_exclusive_staging_file_no_follow(path, pre_captured_canon_root)?;
    f.write_all(bytes)?;
    f.sync_all()?;
    Ok(())
}

impl TransferJob {
    #[allow(clippy::too_many_arguments)]
    pub fn new_write(
        id: i32,
        r#type: JobType,
        remote: String,
        data_source: DataSource,
        file_num: i32,
        show_hidden: bool,
        is_remote: bool,
        enable_overwrite_detection: bool,
    ) -> Self {
        log::info!("new write {}", data_source);
        let is_download = is_remote && r#type == JobType::Generic;
        #[cfg(any(target_os = "android", all(test, unix)))]
        let is_download = is_download
            && !matches!(&data_source, DataSource::FilePath(path) if android::is_path(path));
        Self {
            id,
            r#type,
            remote,
            data_source,
            file_num,
            show_hidden,
            is_remote,
            files: Vec::new(),
            total_size: 0,
            enable_overwrite_detection,
            download: is_download.then(Default::default),
            ..Default::default()
        }
    }

    pub fn with_files(mut self, files: Vec<FileEntry>) -> ResultType<Self> {
        self.set_files(files)?;
        Ok(self)
    }

    pub fn new_read(
        id: i32,
        r#type: JobType,
        remote: String,
        data_source: DataSource,
        file_num: i32,
        show_hidden: bool,
        is_remote: bool,
        enable_overwrite_detection: bool,
    ) -> ResultType<Self> {
        log::info!("new read {}", data_source);
        let (files, total_size) = match &data_source {
            DataSource::FilePath(p) => {
                let p_str = p.to_str().ok_or(anyhow!("Invalid path"))?;
                let mut files = get_recursive_files(p_str, show_hidden)?;
                #[cfg(any(target_os = "android", test))]
                let is_android_doc = android::is_path(p);
                #[cfg(not(any(target_os = "android", test)))]
                let is_android_doc = false;
                if r#type == JobType::Generic && !is_android_doc {
                    for entry in &mut files {
                        let full_path = Self::join(p, &entry.name);
                        let (sha256, exact_size) = compute_file_sha256_and_size(&full_path)?;
                        entry.sha256 = sha256;
                        entry.size = exact_size;
                    }
                }
                let total_size = files.iter().map(|x| x.size).sum();
                (files, total_size)
            }
            DataSource::MemoryCursor(c) => (Vec::new(), c.get_ref().len() as u64),
        };
        Ok(Self {
            id,
            r#type,
            remote,
            data_source,
            file_num,
            show_hidden,
            is_remote,
            files,
            total_size,
            enable_overwrite_detection,
            ..Default::default()
        })
    }

    pub async fn get_buf_data(self) -> ResultType<Option<Vec<u8>>> {
        match self.data_stream {
            Some(DataStream::BufStream(mut bs)) => {
                bs.flush().await?;
                Ok(Some(bs.into_inner().into_inner()))
            }
            _ => Ok(None),
        }
    }

    #[inline]
    pub fn files(&self) -> &Vec<FileEntry> {
        &self.files
    }

    #[inline]
    pub fn set_files(&mut self, files: Vec<FileEntry>) -> ResultType<()> {
        if self.is_download() && !self.files.is_empty() {
            bail!("cannot replace an accepted download file list");
        }
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_remote
            && self.r#type == JobType::Generic
            && self.is_document()
            && !self.files.is_empty()
        {
            bail!("cannot replace an accepted download file list");
        }
        validate_transfer_file_names(&files)?;
        if let DataSource::FilePath(base) = &self.data_source {
            for file in &files {
                validate_no_symlink_components(base, &file.name)?;
            }
        }
        self.total_size = files.iter().map(|x| x.size).sum();
        self.files = files;
        Ok(())
    }

    #[inline]
    pub fn set_digest(&mut self, size: u64, modified: u64) {
        self.digest.size = size;
        self.digest.modified = modified;
    }

    #[inline]
    pub fn id(&self) -> i32 {
        self.id
    }

    #[inline]
    pub fn total_size(&self) -> u64 {
        self.total_size
    }

    #[inline]
    pub fn finished_size(&self) -> u64 {
        self.finished_size
    }

    #[inline]
    pub fn transferred(&self) -> u64 {
        self.transferred
    }

    #[inline]
    pub fn file_num(&self) -> i32 {
        self.file_num
    }

    fn resolve_entry_path(&self, base: &PathBuf, name: &str) -> Option<PathBuf> {
        if self.r#type == JobType::Generic {
            let result = if self.is_download() {
                download::validated_target(base, name)
            } else {
                join_validated_path(base, name)
            };
            match result {
                Ok(path) => Some(path),
                Err(err) => {
                    log::error!("Invalid file name in transfer job {}: {}", self.id, err);
                    None
                }
            }
        } else {
            Some(Self::join(base, name))
        }
    }

    pub async fn sync_stream(&mut self) -> ResultType<()> {
        if let Some(DataStream::FileStream(file)) = self.data_stream.as_mut() {
            file.sync_all().await?;
        }
        Ok(())
    }

    pub async fn flush_and_close_stream(&mut self) -> ResultType<()> {
        self.sync_stream().await?;
        self.data_stream = None;
        Ok(())
    }

    pub fn try_finalize_write_files(&self) -> ResultType<()> {
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_document() {
            return Ok(());
        }
        if self.is_download() {
            return self.finish_download();
        }
        if self.r#type == JobType::Printer {
            return Ok(());
        }
        if let DataSource::FilePath(p) = &self.data_source {
            let file_num = self.file_num as usize;
            if file_num < self.files.len() {
                let entry = &self.files[file_num];
                let path = join_validated_path(p, &entry.name)?;
                #[cfg(windows)]
                let pre_canon_root: Option<PathBuf> = {
                    let auth_root = if entry.name.is_empty() {
                        p.parent()
                    } else {
                        Some(p.as_path())
                    };
                    auth_root
                        .filter(|r| !r.as_os_str().is_empty())
                        .map(capture_confined_transfer_root)
                        .transpose()?
                };
                #[cfg(not(windows))]
                let pre_canon_root: Option<PathBuf> = None;

                ensure_destination_safe_for_overwrite(&path, pre_canon_root.as_deref())?;
                let download_path = PathBuf::from(format!("{}.download", get_string(&path)));
                if !download_path.exists() {
                    return Ok(());
                }
                verify_staging_file_sha256_confined(
                    &download_path,
                    entry.size,
                    entry.sha256.trim(),
                    pre_canon_root.as_deref(),
                )?;
                let digest_path = PathBuf::from(format!("{}.digest", get_string(&path)));
                match std::fs::remove_file(&digest_path) {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e.into()),
                }
                std::fs::rename(&download_path, &path)?;
                let _ = filetime::set_file_mtime(
                    &path,
                    filetime::FileTime::from_unix_time(entry.modified_time as _, 0),
                );
            }
        }
        Ok(())
    }

    pub fn modify_time(&self) {
        if let Err(err) = self.try_finalize_write_files() {
            hbb_common::throttled_log!(
                std::time::Duration::from_secs(30),
                error,
                "Transfer finalization failed for job {}: {}",
                self.id,
                err
            );
        }
    }

    pub fn remove_download_file(&self) {
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_document() {
            return;
        }
        if self.is_download() && self.data_stream.is_none() {
            return;
        }
        if self.r#type == JobType::Printer {
            return;
        }
        if let DataSource::FilePath(p) = &self.data_source {
            let file_num = self.file_num as usize;
            if file_num < self.files.len() {
                let entry = &self.files[file_num];
                let Some(path) = self.resolve_entry_path(p, &entry.name) else {
                    return;
                };
                let download_path = PathBuf::from(format!("{}.download", get_string(&path)));
                let digest_path = PathBuf::from(format!("{}.digest", get_string(&path)));
                if open_readonly_no_follow_single_link(&download_path, None).is_ok() {
                    std::fs::remove_file(&download_path).ok();
                }
                if open_readonly_no_follow_single_link(&digest_path, None).is_ok() {
                    std::fs::remove_file(&digest_path).ok();
                }
            }
        }
    }

    #[inline]
    pub fn set_finished_size_on_resume(&mut self) {
        if self.is_resume && self.file_num > 0 {
            let finished_size: u64 = self
                .files
                .iter()
                .take(self.file_num as usize)
                .map(|file| file.size)
                .sum();
            self.finished_size = finished_size;
        }
    }

    pub async fn write(&mut self, block: FileTransferBlock) -> ResultType<()> {
        if self.is_download() {
            return self.write_download(block).await;
        }
        if block.id != self.id {
            bail!("Wrong id");
        }
        if let Some(resume_err) = self.resume_failed_err.as_ref() {
            bail!("{resume_err}");
        }
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_document() {
            return self.write_document(block).await;
        }
        match &self.data_source {
            DataSource::FilePath(p) => {
                let file_num = block.file_num as usize;
                if file_num >= self.files.len() {
                    bail!("Wrong file number");
                }
                if file_num != self.file_num as usize || self.data_stream.is_none() {
                    if let Some(DataStream::FileStream(file)) = self.data_stream.as_mut() {
                        file.sync_all().await?;
                    }
                    self.data_stream = None;
                    self.try_finalize_write_files()?;
                    self.file_num = block.file_num;
                    let entry = &self.files[file_num];
                    #[cfg(windows)]
                    let pre_canon_root: Option<PathBuf> = if self.r#type == JobType::Printer {
                        None
                    } else {
                        let auth_root = if entry.name.is_empty() {
                            p.parent()
                        } else {
                            Some(p.as_path())
                        };
                        auth_root
                            .filter(|r| !r.as_os_str().is_empty())
                            .map(capture_confined_transfer_root)
                            .transpose()?
                    };
                    #[cfg(not(windows))]
                    let pre_canon_root: Option<PathBuf> = None;
                    let (path, digest_path) = if self.r#type == JobType::Printer {
                        (p.clone(), None)
                    } else {
                        let path = join_validated_path(p, &entry.name)?;
                        ensure_destination_safe_for_overwrite(&path, pre_canon_root.as_deref())?;
                        if let Some(pp) = path.parent() {
                            std::fs::create_dir_all(pp)?;
                            if is_existing_symlink_or_reparse(pp) {
                                bail!("Refusing symlink/reparse parent directory");
                            }
                        }
                        let file_path = get_string(&path);
                        (
                            PathBuf::from(format!("{}.download", &file_path)),
                            Some(PathBuf::from(format!("{}.digest", &file_path))),
                        )
                    };
                    let std_file =
                        create_exclusive_staging_file_no_follow(&path, pre_canon_root.as_deref())?;
                    self.data_stream = Some(DataStream::FileStream(File::from_std(std_file)));
                    if let Some(dp) = digest_path.as_ref() {
                        let digest_bytes = json!(self.digest).to_string();
                        write_exclusive_digest_file_no_follow(
                            dp,
                            digest_bytes.as_bytes(),
                            pre_canon_root.as_deref(),
                        )?;
                    }
                }
            }
            DataSource::MemoryCursor(c) => {
                if self.data_stream.is_none() {
                    self.data_stream = Some(DataStream::BufStream(TokioBufStream::new(c.clone())));
                }
            }
        }
        if block.compressed {
            let tmp = decompress(&block.data);
            self.data_stream
                .as_mut()
                .ok_or(anyhow!("data stream is None"))?
                .write_all(&tmp)
                .await?;
            self.finished_size += tmp.len() as u64;
        } else {
            self.data_stream
                .as_mut()
                .ok_or(anyhow!("file is None"))?
                .write_all(&block.data)
                .await?;
            self.finished_size += block.data.len() as u64;
        }
        self.transferred += block.data.len() as u64;
        Ok(())
    }

    #[inline]
    pub fn join(p: &PathBuf, name: &str) -> PathBuf {
        if name.is_empty() {
            p.clone()
        } else {
            p.join(name)
        }
    }

    /// Open the data stream for the current file.
    /// Returns Ok(true) if job is done, Ok(false) otherwise.
    async fn open_data_stream(&mut self) -> ResultType<bool> {
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_document() {
            return self.open_document_stream().await;
        }
        let file_num = self.file_num as usize;
        match &mut self.data_source {
            DataSource::FilePath(p) => {
                if file_num >= self.files.len() {
                    // job done
                    self.data_stream.take();
                    self.read_stream_integrity = None;
                    return Ok(true);
                };
                if self.data_stream.is_none() {
                    match File::open(Self::join(p, &self.files[file_num].name)).await {
                        Ok(file) => {
                            self.data_stream = Some(DataStream::FileStream(file));
                            self.read_stream_integrity = Some((file_num, Sha256::new(), 0));
                            self.file_confirmed = false;
                            self.file_is_waiting = false;
                        }
                        // On open error, behave the same as validation failure: advance
                        // to next file and return the error.
                        Err(err) => {
                            self.file_num += 1;
                            self.read_stream_integrity = None;
                            self.file_confirmed = false;
                            self.file_is_waiting = false;
                            return Err(err.into());
                        }
                    }
                }
            }
            DataSource::MemoryCursor(c) => {
                if self.data_stream.is_none() {
                    let mut t = std::io::Cursor::new(Vec::new());
                    std::mem::swap(&mut t, c);
                    self.data_stream = Some(DataStream::BufStream(TokioBufStream::new(t)));
                }
            }
        }
        Ok(false)
    }

    /// Get current file's digest (last_modified, file_size) for overwrite detection.
    async fn get_current_digest(&self) -> ResultType<(u64, u64)> {
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_document() {
            let entry = self
                .files
                .get(self.file_num as usize)
                .ok_or(anyhow!("Wrong file number"))?;
            return Ok((entry.modified_time, entry.size));
        }
        let meta = match self.data_stream.as_ref().ok_or(anyhow!("file is None"))? {
            DataStream::FileStream(file) => file.metadata().await?,
            DataStream::BufStream(_) => bail!("No digest for buf stream"),
        };
        let last_modified = meta
            .modified()?
            .duration_since(SystemTime::UNIX_EPOCH)?
            .as_secs();
        Ok((last_modified, meta.len()))
    }

    async fn init_data_stream(&mut self, stream: &mut hbb_common::Stream) -> ResultType<()> {
        if self.open_data_stream().await? {
            return Ok(());
        }
        if self.r#type == JobType::Generic
            && self.enable_overwrite_detection
            && !self.file_confirmed()
            && !self.file_is_waiting()
        {
            self.send_current_digest(stream).await?;
            self.set_file_is_waiting(true);
        }
        Ok(())
    }

    /// Initialize data stream for CM (Connection Manager) scenario.
    /// Returns digest info (last_modified, file_size) if overwrite detection is enabled,
    /// so caller can send it via IPC instead of network stream.
    /// Returns Ok(None) if job is done or already initialized.
    pub async fn init_data_stream_for_cm(&mut self) -> ResultType<Option<(u64, u64)>> {
        if self.open_data_stream().await? {
            return Ok(None);
        }
        // For overwrite detection, return digest info instead of sending via stream
        if self.r#type == JobType::Generic
            && self.enable_overwrite_detection
            && !self.file_confirmed()
            && !self.file_is_waiting()
        {
            let digest = self.get_current_digest().await?;
            self.set_file_is_waiting(true);
            return Ok(Some(digest));
        }
        Ok(None)
    }

    pub async fn read(&mut self) -> ResultType<Option<FileTransferBlock>> {
        if self.r#type == JobType::Generic {
            if self.enable_overwrite_detection && !self.file_confirmed() {
                return Ok(None);
            }
        }

        let file_num = self.file_num as usize;
        let name = match &self.data_source {
            DataSource::FilePath(p) => {
                if file_num >= self.files.len() {
                    self.data_stream.take();
                    return Ok(None);
                };
                if self.files.len() == 1 && self.files[file_num].name.is_empty() {
                    p.file_name()
                        .map(|p| p.to_str().unwrap_or(""))
                        .unwrap_or("")
                } else {
                    &self.files[file_num].name
                }
            }
            DataSource::MemoryCursor(..) => "",
        };
        const BUF_SIZE: usize = 128 * 1024;
        let mut buf: Vec<u8> = vec![0; BUF_SIZE];
        let mut compressed = false;
        let mut offset: usize = 0;
        loop {
            match self
                .data_stream
                .as_mut()
                .ok_or(anyhow!("data stream is None"))?
                .read(&mut buf[offset..])
                .await
            {
                Err(err) => {
                    self.file_num += 1;
                    self.data_stream = None;
                    self.read_stream_integrity = None;
                    self.file_confirmed = false;
                    self.file_is_waiting = false;
                    #[cfg(any(target_os = "android", all(test, unix)))]
                    if self.is_document() {
                        self.fail_document_read(err.to_string());
                    }
                    return Err(err.into());
                }
                Ok(n) => {
                    offset += n;
                    if n == 0 || offset == BUF_SIZE {
                        break;
                    }
                }
            }
        }
        unsafe { buf.set_len(offset) };
        if offset == 0 {
            #[cfg(any(target_os = "android", all(test, unix)))]
            if self.is_document() {
                self.finish_document_read().await?;
            }
            if matches!(self.data_source, DataSource::MemoryCursor(_)) {
                self.data_stream.take();
                return Ok(None);
            }
            let integrity_failure = if self.r#type == JobType::Generic {
                let expected_sha = self.files[file_num].sha256.trim().to_owned();
                let expected_size = self.files[file_num].size;
                if !expected_sha.is_empty() {
                    if let Some((tracked_idx, hasher, streamed_bytes)) =
                        self.read_stream_integrity.take()
                    {
                        if tracked_idx == file_num {
                            let digest = hasher.finalize();
                            let mut actual_sha = String::with_capacity(64);
                            for byte in digest.iter() {
                                use std::fmt::Write as _;
                                let _ = write!(&mut actual_sha, "{byte:02x}");
                            }
                            if streamed_bytes != expected_size
                                || !constant_time_eq_ascii_hex(&actual_sha, &expected_sha)
                            {
                                Some(format!(
                                    "sender file mutated during transfer for file {}: expected ({} bytes, {}), streamed ({} bytes, {})",
                                    file_num, expected_size, expected_sha, streamed_bytes, actual_sha
                                ))
                            } else {
                                None
                            }
                        } else {
                            None
                        }
                    } else if let DataSource::FilePath(p) = &self.data_source {
                        #[cfg(any(target_os = "android", test))]
                        let is_android_doc = android::is_path(p);
                        #[cfg(not(any(target_os = "android", test)))]
                        let is_android_doc = false;
                        if !is_android_doc {
                            let full_path = Self::join(p, &self.files[file_num].name);
                            verify_staging_file_sha256(&full_path, expected_size, &expected_sha)
                                .err()
                                .map(|e| format!("sender file mutated during resumed transfer: {e}"))
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                } else {
                    self.read_stream_integrity = None;
                    None
                }
            } else {
                self.read_stream_integrity = None;
                None
            };
            self.file_num += 1;
            self.data_stream = None;
            self.file_confirmed = false;
            self.file_is_waiting = false;
            if let Some(msg) = integrity_failure {
                bail!("{msg}");
            }
        } else {
            if let Some((tracked_idx, hasher, streamed_bytes)) = self.read_stream_integrity.as_mut()
            {
                if *tracked_idx == file_num {
                    hasher.update(&buf);
                    *streamed_bytes = streamed_bytes.saturating_add(offset as u64);
                }
            }
            self.finished_size += offset as u64;
            if matches!(self.data_source, DataSource::FilePath(_)) && !is_compressed_file(name) {
                let tmp = compress(&buf);
                if tmp.len() < buf.len() {
                    buf = tmp;
                    compressed = true;
                }
            }
            self.transferred += buf.len() as u64;
        }
        Ok(Some(FileTransferBlock {
            id: self.id,
            file_num: file_num as _,
            data: buf.into(),
            compressed,
            ..Default::default()
        }))
    }

    // Only for generic job and file stream
    async fn send_current_digest(&mut self, stream: &mut Stream) -> ResultType<()> {
        let (last_modified, file_size) = self.get_current_digest().await?;
        let mut msg = Message::new();
        let mut resp = FileResponse::new();
        resp.set_digest(FileTransferDigest {
            id: self.id,
            file_num: self.file_num,
            last_modified,
            file_size,
            is_resume: self.is_resume,
            ..Default::default()
        });
        msg.set_file_response(resp);
        stream.send(&msg).await?;
        log::info!(
            "id: {}, file_num: {}, digest message is sent. waiting for confirm. msg: {:?}",
            self.id,
            self.file_num,
            msg
        );
        Ok(())
    }

    pub fn set_overwrite_strategy(&mut self, overwrite_strategy: Option<bool>) {
        self.default_overwrite_strategy = overwrite_strategy;
    }

    pub fn default_overwrite_strategy(&self) -> Option<bool> {
        self.default_overwrite_strategy
    }

    pub fn set_file_confirmed(&mut self, file_confirmed: bool) {
        log::info!("id: {}, file_confirmed: {}", self.id, file_confirmed);
        self.file_confirmed = file_confirmed;
        self.file_skipped = false;
    }

    pub fn set_file_is_waiting(&mut self, file_is_waiting: bool) {
        self.file_is_waiting = file_is_waiting;
    }

    #[inline]
    pub fn file_is_waiting(&self) -> bool {
        self.file_is_waiting
    }

    #[inline]
    pub fn file_confirmed(&self) -> bool {
        self.file_confirmed
    }

    /// Indicating whether the last file is skipped
    #[inline]
    pub fn file_skipped(&self) -> bool {
        self.file_skipped
    }

    /// Indicating whether the whole task is skipped
    #[inline]
    pub fn job_skipped(&self) -> bool {
        self.file_skipped() && self.files.len() == 1
    }

    /// Check whether the job is completed after `read` returns `None`
    /// This is a helper function which gives additional lifecycle when the job reads `None`.
    /// If returns `true`, it means we can delete the job automatically. `False` otherwise.
    ///
    /// [`Note`]
    /// Conditions:
    /// 1. Files are not waiting for confirmation by peers.
    #[inline]
    pub fn job_completed(&self) -> bool {
        // has no error, Condition 2
        !self.enable_overwrite_detection || (!self.file_confirmed && !self.file_is_waiting)
    }

    /// Get job error message, useful for getting status when job had finished
    pub fn job_error(&self) -> Option<String> {
        #[cfg(any(target_os = "android", all(test, unix)))]
        if let Some(error) = &self.document_transfer.error {
            return Some(error.clone());
        }
        if self.job_skipped() {
            return Some("skipped".to_string());
        }
        None
    }

    pub fn set_file_skipped(&mut self) -> bool {
        log::debug!("skip file {} in job {}", self.file_num, self.id);
        self.data_stream.take();
        self.read_stream_integrity = None;
        self.set_file_confirmed(false);
        self.set_file_is_waiting(false);
        self.file_num += 1;
        self.file_skipped = true;
        true
    }

    async fn set_stream_offset(&mut self, file_num: usize, offset: u64) {
        self.read_stream_integrity = None;
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_document() {
            if let Err(error) = self.seek_document(offset).await {
                self.fail_document_read(error.to_string());
            }
            return;
        }
        if file_num >= self.files.len() {
            return;
        }
        if let DataSource::FilePath(p) = &self.data_source {
            let entry = &self.files[file_num];
            let Some(path) = self.resolve_entry_path(p, &entry.name) else {
                return;
            };
            let file_path = get_string(&path);
            let download_path = format!("{}.download", &file_path);
            let digest_path = format!("{}.digest", &file_path);

            let mut f = if !self.is_remote
                && (Path::new(&download_path).exists() || Path::new(&digest_path).exists())
            {
                let resume_res = (|| -> ResultType<std::fs::File> {
                    #[cfg(windows)]
                    let pre_canon_root: Option<PathBuf> = {
                        let entry = &self.files[file_num];
                        let auth_root = if entry.name.is_empty() {
                            p.parent()
                        } else {
                            Some(p.as_path())
                        };
                        auth_root
                            .filter(|r| !r.as_os_str().is_empty())
                            .map(capture_confined_transfer_root)
                            .transpose()?
                    };
                    #[cfg(not(windows))]
                    let pre_canon_root: Option<PathBuf> = None;

                    let _digest_ro = open_readonly_no_follow_single_link(
                        Path::new(&digest_path),
                        pre_canon_root.as_deref(),
                    )?;
                    #[cfg(unix)]
                    let opened = {
                        use std::os::unix::fs::OpenOptionsExt;
                        std::fs::OpenOptions::new()
                            .write(true)
                            .custom_flags(hbb_common::libc::O_NOFOLLOW)
                            .open(&download_path)?
                    };
                    #[cfg(windows)]
                    let opened = {
                        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
                        std::fs::OpenOptions::new()
                            .write(true)
                            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
                            .open(&download_path)?
                    };
                    #[cfg(not(any(unix, windows)))]
                    let opened = std::fs::OpenOptions::new()
                        .write(true)
                        .open(&download_path)?;

                    verify_std_handle_single_link_regular_confined(
                        &opened,
                        pre_canon_root.as_deref(),
                    )?;
                    if opened.metadata()?.len() != offset {
                        bail!(
                            "upload resume offset {} does not match staging size",
                            offset
                        );
                    }
                    Ok(opened)
                })();
                match resume_res {
                    Ok(std_f) => File::from_std(std_f),
                    Err(e) => {
                        let msg = format!("refusing unsafe upload resume staging '{}': {e}", download_path);
                        self.resume_failed_err = Some(msg);
                        return;
                    }
                }
            } else if self.is_remote && Path::new(&file_path).exists() {
                match open_readonly_no_follow_single_link(Path::new(&file_path), None)
                    .or_else(|_| std::fs::File::open(&file_path))
                {
                    Ok(std_f) => File::from_std(std_f),
                    Err(e) => {
                        log::warn!("Failed to open file {}: {}", file_path, e);
                        return;
                    }
                }
            } else {
                if !self.is_remote {
                    self.resume_failed_err = Some(format!(
                        "upload resume staging files missing for '{}'",
                        file_path
                    ));
                }
                log::warn!(
                    "File {} not found, cannot seek to offset {}",
                    file_path,
                    offset
                );
                return;
            };
            if f.seek(std::io::SeekFrom::Start(offset)).await.is_ok() {
                self.data_stream = Some(DataStream::FileStream(f));
                self.transferred += offset;
                self.finished_size += offset;
            }
        }
    }

    pub async fn confirm(&mut self, r: &FileTransferSendConfirmRequest) -> bool {
        #[cfg(any(target_os = "android", all(test, unix)))]
        if self.is_document() && self.is_remote {
            self.confirm_document(r);
        }
        if self.is_download() {
            self.confirm_download(r);
            // Open receiver resume streams in write() so validation errors reach the caller.
            if matches!(r.union, Some(file_transfer_send_confirm_request::Union::OffsetBlk(offset)) if offset > 0) {
                return true;
            }
        }
        if self.file_num() != r.file_num {
            // This branch will always be hit if:
            // 1. `confirm()` is called in `ui_cm_interface.rs`
            // 2. Not resuming
            //
            // It is ok. Because `confirm()` in `ui_cm_interface.rs` is only used for resuming.
            log::info!("file num truncated, ignoring");
        } else {
            match r.union {
                Some(file_transfer_send_confirm_request::Union::Skip(s)) => {
                    if s {
                        self.set_file_skipped();
                    } else {
                        self.set_file_confirmed(true);
                    }
                }
                Some(file_transfer_send_confirm_request::Union::OffsetBlk(offset)) => {
                    self.set_file_confirmed(true);
                    // If offset is greater than 0, we need to seek to the offset
                    if offset > 0 {
                        self.set_stream_offset(r.file_num as usize, offset as u64)
                            .await;
                    }
                }
                _ => {}
            }
        }
        true
    }

    #[inline]
    pub fn gen_meta(&self) -> TransferJobMeta {
        TransferJobMeta {
            id: self.id,
            remote: self.remote.to_string(),
            to: self.data_source.to_meta(),
            file_num: self.file_num,
            show_hidden: self.show_hidden,
            is_remote: self.is_remote,
        }
    }
}

#[inline]
pub fn new_error<T: std::string::ToString>(id: i32, err: T, file_num: i32) -> Message {
    let mut resp = FileResponse::new();
    resp.set_error(FileTransferError {
        id,
        error: err.to_string(),
        file_num,
        ..Default::default()
    });
    let mut msg_out = Message::new();
    msg_out.set_file_response(resp);
    msg_out
}

#[inline]
pub fn new_dir(id: i32, path: String, files: Vec<FileEntry>) -> Message {
    let mut resp = FileResponse::new();
    resp.set_dir(FileDirectory {
        id,
        path,
        entries: files,
        ..Default::default()
    });
    let mut msg_out = Message::new();
    msg_out.set_file_response(resp);
    msg_out
}

#[inline]
pub fn new_block(block: FileTransferBlock) -> Message {
    let mut resp = FileResponse::new();
    resp.set_block(block);
    let mut msg_out = Message::new();
    msg_out.set_file_response(resp);
    msg_out
}

#[inline]
pub fn new_send_confirm(r: FileTransferSendConfirmRequest) -> Message {
    let mut msg_out = Message::new();
    let mut action = FileAction::new();
    action.set_send_confirm(r);
    msg_out.set_file_action(action);
    msg_out
}

#[inline]
pub fn new_receive(
    id: i32,
    path: String,
    file_num: i32,
    files: Vec<FileEntry>,
    total_size: u64,
) -> Message {
    let mut action = FileAction::new();
    action.set_receive(FileTransferReceiveRequest {
        id,
        path,
        files,
        file_num,
        total_size,
        ..Default::default()
    });
    let mut msg_out = Message::new();
    msg_out.set_file_action(action);
    msg_out
}

#[inline]
pub fn new_send(
    id: i32,
    r#type: JobType,
    path: String,
    file_num: i32,
    include_hidden: bool,
) -> Message {
    log::info!("new send: {}, id: {}", path, id);
    let mut action = FileAction::new();
    let t: file_transfer_send_request::FileType = r#type.into();
    action.set_send(FileTransferSendRequest {
        id,
        path,
        include_hidden,
        file_num,
        file_type: t.into(),
        ..Default::default()
    });
    let mut msg_out = Message::new();
    msg_out.set_file_action(action);
    msg_out
}

#[inline]
pub fn new_done(id: i32, file_num: i32) -> Message {
    let mut resp = FileResponse::new();
    resp.set_done(FileTransferDone {
        id,
        file_num,
        ..Default::default()
    });
    let mut msg_out = Message::new();
    msg_out.set_file_response(resp);
    msg_out
}

#[inline]
pub fn remove_job(id: i32, jobs: &mut Vec<TransferJob>) -> Option<TransferJob> {
    jobs.iter()
        .position(|x| x.id() == id)
        .map(|index| jobs.remove(index))
}

#[inline]
pub fn get_job(id: i32, jobs: &mut [TransferJob]) -> Option<&mut TransferJob> {
    jobs.iter_mut().find(|x| x.id() == id)
}

#[inline]
pub fn get_job_immutable(id: i32, jobs: &[TransferJob]) -> Option<&TransferJob> {
    jobs.iter().find(|x| x.id() == id)
}

async fn init_jobs(jobs: &mut Vec<TransferJob>, stream: &mut hbb_common::Stream) -> ResultType<()> {
    for job in jobs.iter_mut() {
        if job.is_last_job {
            continue;
        }
        if let Err(err) = job.init_data_stream(stream).await {
            stream
                .send(&new_error(job.id(), err, job.file_num()))
                .await?;
        }
    }
    Ok(())
}

pub async fn handle_read_jobs(
    jobs: &mut Vec<TransferJob>,
    stream: &mut hbb_common::Stream,
) -> ResultType<String> {
    init_jobs(jobs, stream).await?;

    let mut job_log = Default::default();
    let mut finished = Vec::new();
    for job in jobs.iter_mut() {
        if job.is_last_job {
            continue;
        }
        match job.read().await {
            Err(err) => {
                stream
                    .send(&new_error(job.id(), err, job.file_num()))
                    .await?;
            }
            Ok(Some(block)) => {
                stream.send(&new_block(block)).await?;
            }
            Ok(None) => {
                if job.job_completed() {
                    job_log = serialize_transfer_job(job, true, false, "");
                    finished.push(job.id());
                    match job.job_error() {
                        Some(err) => {
                            job_log = serialize_transfer_job(job, false, false, &err);
                            stream
                                .send(&new_error(job.id(), err, job.file_num()))
                                .await?
                        }
                        None => stream.send(&new_done(job.id(), job.file_num())).await?,
                    }
                } else {
                    // waiting confirmation.
                }
            }
        }
        // Break to handle jobs one by one.
        break;
    }
    for id in finished {
        let _ = remove_job(id, jobs);
    }
    Ok(job_log)
}

pub fn remove_all_empty_dir(path: &Path) -> ResultType<()> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(path) {
        return android::remove_empty_tree(&get_string(path));
    }
    let fd = read_dir(path, true)?;
    for entry in fd.entries.iter() {
        match entry.entry_type.enum_value() {
            Ok(FileType::Dir) => {
                remove_all_empty_dir(&path.join(&entry.name)).ok();
            }
            Ok(FileType::DirLink) | Ok(FileType::FileLink) => {
                std::fs::remove_file(path.join(&entry.name)).ok();
            }
            _ => {}
        }
    }
    std::fs::remove_dir(path).ok();
    Ok(())
}

#[inline]
pub fn remove_file(file: &str) -> ResultType<()> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(Path::new(file)) {
        return android::remove_file(file);
    }
    validate_fs_path_argument(file, "file path")?;
    std::fs::remove_file(get_path(file))?;
    Ok(())
}

#[inline]
pub fn create_dir(dir: &str) -> ResultType<()> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(Path::new(dir)) {
        return android::operation("mkdir", dir);
    }
    validate_fs_path_argument(dir, "directory path")?;
    std::fs::create_dir_all(get_path(dir))?;
    Ok(())
}

#[inline]
pub fn rename_file(path: &str, new_name: &str) -> ResultType<()> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(Path::new(path)) {
        return android::rename(path, new_name);
    }
    validate_fs_path_argument(path, "path")?;
    if new_name.is_empty() {
        bail!("new file name cannot be empty");
    }
    validate_file_name_no_traversal(new_name)?;
    let path = std::path::Path::new(&path);
    if path.exists() {
        let dir = path
            .parent()
            .ok_or(anyhow!("Parent directoy of {path:?} not exists"))?;
        let new_path = dir.join(&new_name);
        std::fs::rename(&path, &new_path)?;
        Ok(())
    } else {
        bail!("{path:?} not exists");
    }
}

#[inline]
pub fn transform_windows_path(entries: &mut Vec<FileEntry>) {
    for entry in entries {
        entry.name = entry.name.replace('\\', "/");
    }
}

pub enum DigestCheckResult {
    IsSame,
    NeedConfirm(FileTransferDigest),
    NoSuchFile,
}

#[inline]
pub fn is_write_need_confirmation(
    is_resume: bool,
    file_path: &str,
    digest: &FileTransferDigest,
) -> ResultType<DigestCheckResult> {
    #[cfg(any(target_os = "android", test))]
    if android::is_path(Path::new(file_path)) {
        android::validate(file_path)?;
        if is_resume {
            bail!("Document transfers must be restarted after interruption");
        }
        return match android::stat(file_path)? {
            Some(entry) => Ok(DigestCheckResult::NeedConfirm(FileTransferDigest {
                id: digest.id,
                file_num: digest.file_num,
                last_modified: entry.modified_time,
                file_size: entry.size,
                is_identical: entry.modified_time != 0
                    && entry.modified_time == digest.last_modified
                    && entry.size == digest.file_size,
                ..Default::default()
            })),
            None => Ok(DigestCheckResult::NoSuchFile),
        };
    }
    let path = Path::new(file_path);
    let digest_file = format!("{}.digest", file_path);
    let download_file = format!("{}.download", file_path);
    if is_resume && Path::new(&digest_file).exists() && Path::new(&download_file).exists() {
        // If the digest file exists, it means the file was transferred before.
        // We can use the digest file to check whether the file is the same.
        if let Ok(content) = std::fs::read_to_string(digest_file) {
            if let Ok(local_digest) = serde_json::from_str::<FileDigest>(&content) {
                let is_identical = local_digest.modified == digest.last_modified
                    && local_digest.size == digest.file_size;
                if is_identical {
                    if let Ok(download_metadata) = std::fs::metadata(download_file) {
                        // Get the file size of the local file
                        // Only send confirmation if the file is not empty.
                        let transferred_size = download_metadata.len();
                        if transferred_size > 0 {
                            return Ok(DigestCheckResult::NeedConfirm(FileTransferDigest {
                                id: digest.id,
                                file_num: digest.file_num,
                                last_modified: digest.last_modified,
                                file_size: digest.file_size,
                                is_identical,
                                transferred_size,
                                ..Default::default()
                            }));
                        }
                    }
                }
            }
        }
    }

    if path.exists() && path.is_file() {
        let metadata = std::fs::metadata(path)?;
        let modified_time = metadata.modified()?;
        let remote_mt = Duration::from_secs(digest.last_modified);
        let local_mt = modified_time.duration_since(UNIX_EPOCH)?;
        // [Note]
        // We decide to give the decision whether to override the existing file to users,
        // which obey the behavior of the file manager in our system.
        let mut is_identical = false;
        if remote_mt == local_mt && digest.file_size == metadata.len() {
            is_identical = true;
        }
        Ok(DigestCheckResult::NeedConfirm(FileTransferDigest {
            id: digest.id,
            file_num: digest.file_num,
            last_modified: local_mt.as_secs(),
            file_size: metadata.len(),
            is_identical,
            ..Default::default()
        }))
    } else {
        // If the file does not exist, or the digest file and download file do not exist, we return NoSuchFile.
        Ok(DigestCheckResult::NoSuchFile)
    }
}

pub fn serialize_transfer_jobs(jobs: &[TransferJob]) -> String {
    let mut v = vec![];
    for job in jobs {
        let value = serde_json::to_value(job).unwrap_or_default();
        v.push(value);
    }
    serde_json::to_string(&v).unwrap_or_default()
}

pub fn serialize_transfer_job(job: &TransferJob, done: bool, cancel: bool, error: &str) -> String {
    let mut value = serde_json::to_value(job).unwrap_or_default();
    value["done"] = json!(done);
    value["cancel"] = json!(cancel);
    value["error"] = json!(error);
    serde_json::to_string(&value).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestTempDir {
        path: PathBuf,
    }

    impl TestTempDir {
        fn new(prefix: &str) -> Self {
            Self {
                path: unique_temp_dir(prefix),
            }
        }

        fn join(&self, path: &str) -> PathBuf {
            self.path.join(path)
        }
    }

    impl Drop for TestTempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        std::env::temp_dir().join(format!("{}_{}_{}", prefix, std::process::id(), timestamp))
    }

    fn new_file_entry(name: &str) -> FileEntry {
        let mut entry = FileEntry::new();
        entry.name = name.to_string();
        entry
    }

    fn new_validation_job(id: i32) -> TransferJob {
        TransferJob::new_write(
            id,
            JobType::Generic,
            "/fake/remote".to_string(),
            DataSource::FilePath(std::env::temp_dir().join(format!("rustdesk_validation_{id}"))),
            0,
            false,
            true,
            false,
        )
    }

    fn new_write_job(id: i32, download_dir: PathBuf, name: &str) -> ResultType<TransferJob> {
        let job = TransferJob::new_write(
            id,
            JobType::Generic,
            "/fake/remote".to_string(),
            DataSource::FilePath(download_dir),
            0,
            false,
            true,
            false,
        )
        .with_files(vec![new_file_entry(name)])?;
        Ok(job)
    }

    fn assert_err_contains(err: anyhow::Error, expected: &str) {
        assert!(
            err.to_string().contains(expected),
            "expected error containing '{}', got: {}",
            expected,
            err
        );
    }

    #[test]
    fn path_traversal_e2e_write_rejects_relative_escape() {
        let tmp_root = TestTempDir::new("rustdesk_e2e_relative");
        let downloads = tmp_root.join("downloads");
        std::fs::create_dir_all(&downloads).expect("create downloads dir");

        let err = new_write_job(1, downloads, "../traversal_proof.txt")
            .expect_err("relative path traversal must be rejected");
        assert_err_contains(err, "path traversal");
        assert!(!tmp_root.join("traversal_proof.txt").exists());
    }

    #[test]
    fn path_traversal_e2e_write_rejects_absolute_path() {
        let tmp_root = TestTempDir::new("rustdesk_e2e_absolute");
        let downloads = tmp_root.join("downloads");
        let absolute_target = tmp_root.join("fake_ssh").join("authorized_keys");
        std::fs::create_dir_all(&downloads).expect("create downloads dir");

        let err = new_write_job(2, downloads, &absolute_target.to_string_lossy())
            .expect_err("absolute path must be rejected");
        assert_err_contains(err, "absolute path");
        assert!(!absolute_target.exists());
    }

    #[cfg(windows)]
    pub(super) fn create_dir_link_or_junction_for_test(target: &Path, link: &Path) {
        if std::os::windows::fs::symlink_dir(target, link).is_ok() {
            return;
        }
        let status = std::process::Command::new("cmd")
            .args([
                "/C",
                "mklink",
                "/J",
                &link.to_string_lossy(),
                &target.to_string_lossy(),
            ])
            .status()
            .expect("invoke mklink /J for unprivileged NTFS junction");
        assert!(status.success(), "mklink /J failed with status: {status}");
    }

    #[test]
    fn path_traversal_e2e_write_rejects_symlink_escape() {
        let tmp_root = TestTempDir::new("rustdesk_e2e_symlink");
        let downloads = tmp_root.join("downloads");
        let outside = tmp_root.join("outside");
        let escaped_target = outside.join("escape.txt");
        std::fs::create_dir_all(&downloads).expect("create downloads dir");
        std::fs::create_dir_all(&outside).expect("create outside dir");

        let symlink_path = downloads.join("link");
        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            symlink(&outside, &symlink_path).expect("create symlink for test");
        }
        #[cfg(windows)]
        {
            create_dir_link_or_junction_for_test(&outside, &symlink_path);
        }

        let err = new_write_job(3, downloads, "link/escape.txt")
            .expect_err("symlink or junction traversal must be rejected");
        assert_err_contains(err, "symlink");
        assert!(!escaped_target.exists());
        let _ = std::fs::remove_dir(&symlink_path);
    }

    #[test]
    fn set_files_allows_single_empty_name_for_single_file_transfer() {
        let mut job = new_validation_job(101);
        assert!(job.set_files(vec![new_file_entry("")]).is_ok());
    }

    #[test]
    fn set_files_rejects_empty_name_in_multi_file_transfer() {
        let mut job = new_validation_job(102);
        let err = job
            .set_files(vec![new_file_entry(""), new_file_entry("ok.txt")])
            .expect_err("empty name in multi-file transfer must be rejected");
        assert_err_contains(err, "empty file name");
    }

    #[test]
    fn set_files_rejects_mixed_entries_when_one_is_traversal() {
        let mut job = new_validation_job(104);
        let err = job
            .set_files(vec![
                new_file_entry("safe/file.txt"),
                new_file_entry("../../escape.txt"),
            ])
            .expect_err("any traversal entry must reject the full file list");
        assert_err_contains(err, "path traversal");
    }

    #[cfg(windows)]
    #[test]
    fn set_files_rejects_unc_absolute_path() {
        let mut job = new_validation_job(105);
        let err = job
            .set_files(vec![new_file_entry("\\\\server\\share\\payload.txt")])
            .expect_err("UNC absolute path must be rejected");
        assert_err_contains(err, "absolute path");
    }

    #[test]
    fn rename_file_rejects_invalid_new_name() {
        let tmp_root = TestTempDir::new("rustdesk_rename_invalid");
        let src = tmp_root.join("source.txt");
        std::fs::create_dir_all(&tmp_root.path).expect("create temp dir");
        std::fs::write(&src, b"content").expect("create source file");

        let src_str = src.to_string_lossy().to_string();

        let err_empty =
            rename_file(&src_str, "").expect_err("empty new file name must be rejected");
        assert_err_contains(err_empty, "cannot be empty");

        let err_traversal = rename_file(&src_str, "../escape.txt")
            .expect_err("traversal new file name must be rejected");
        assert_err_contains(err_traversal, "path traversal");

        let err_null = rename_file(&src_str, "bad\0name.txt")
            .expect_err("null byte in new file name must be rejected");
        assert_err_contains(err_null, "null bytes");

        #[cfg(windows)]
        {
            let err_abs = rename_file(&src_str, "C:\\Windows\\Temp\\payload.txt")
                .expect_err("absolute new file name must be rejected");
            assert_err_contains(err_abs, "absolute path");
        }
        #[cfg(not(windows))]
        {
            let err_abs = rename_file(&src_str, "/tmp/payload.txt")
                .expect_err("absolute new file name must be rejected");
            assert_err_contains(err_abs, "absolute path");
        }
    }

    #[test]
    fn rename_file_accepts_valid_new_name() {
        let tmp_root = TestTempDir::new("rustdesk_rename_ok");
        let src = tmp_root.join("rename_src.txt");
        let dst = tmp_root.join("renamed.txt");
        std::fs::create_dir_all(&tmp_root.path).expect("create temp dir");
        std::fs::write(&src, b"content").expect("create source file");

        let src_str = src.to_string_lossy().to_string();
        rename_file(&src_str, "renamed.txt").expect("rename should succeed");

        assert!(!src.exists());
        assert!(dst.exists());
    }

    #[test]
    fn compressed_file_extensions_ignore_case() {
        // Cameras and phones name their photos IMG_0001.JPG.
        assert!(is_compressed_file("IMG_0001.JPG"));
        assert!(is_compressed_file("Backup.ZIP"));
    }

    #[tokio::test]
    async fn f16_new_read_populates_sha256_and_detects_mid_transfer_mutation_and_corrupted_staging() {
        let tmp_root = TestTempDir::new("rustdesk_f16_integrity");
        let src_dir = tmp_root.join("src");
        let dst_dir = tmp_root.join("dst");
        std::fs::create_dir_all(&src_dir).unwrap();
        std::fs::create_dir_all(&dst_dir).unwrap();

        let src_file = src_dir.join("payload.bin");
        std::fs::write(&src_file, b"AAAA").unwrap();

        let mut reader = TransferJob::new_read(
            41,
            JobType::Generic,
            "".to_string(),
            DataSource::FilePath(src_file.clone()),
            0,
            false,
            false,
            false,
        )
        .unwrap();
        assert_eq!(reader.files().len(), 1);
        assert_eq!(reader.files()[0].size, 4);
        assert_eq!(reader.files()[0].sha256.len(), 64);

        // Mutate sender file before read stream finishes -> EOF read MUST fail
        std::fs::write(&src_file, b"BBBB").unwrap();
        assert!(!reader.open_data_stream().await.unwrap());
        let first_block = reader.read().await.unwrap().unwrap();
        assert!(!first_block.data.is_empty());
        let eof_err = reader
            .read()
            .await
            .expect_err("sender file mutation must fail at EOF before FileTransferDone");
        assert!(eof_err.to_string().contains("sender file mutated"));

        // Receiver modify_time refuses to publish corrupted .download when entry.sha256 mismatches
        let (expected_sha_aaaa, _) = {
            let clean_file = src_dir.join("clean.bin");
            std::fs::write(&clean_file, b"AAAA").unwrap();
            compute_file_sha256_and_size(&clean_file).unwrap()
        };
        let mut writer = TransferJob::new_write(
            42,
            JobType::Generic,
            "".to_string(),
            DataSource::FilePath(dst_dir.clone()),
            0,
            false,
            false,
            false,
        )
        .with_files(vec![FileEntry {
            name: "out.bin".to_string(),
            size: 4,
            sha256: expected_sha_aaaa,
            ..Default::default()
        }])
        .unwrap();
        writer
            .write(FileTransferBlock {
                id: 42,
                file_num: 0,
                data: b"BBBB".to_vec().into(),
                compressed: false,
                ..Default::default()
            })
            .await
            .unwrap();
        writer.flush_and_close_stream().await.unwrap();
        assert!(writer.try_finalize_write_files().is_err());
        assert!(!dst_dir.join("out.bin").exists());
        assert!(dst_dir.join("out.bin.download").exists());
    }

    #[tokio::test]
    async fn ft010_b02_fresh_and_resume_upload_staging_hardlinks_preserve_outside_victim_bytes() {
        struct ScopedDir(PathBuf);
        impl Drop for ScopedDir {
            fn drop(&mut self) {
                let _ = std::fs::remove_dir_all(&self.0);
            }
        }
        let workspace = ScopedDir(std::env::temp_dir().join(format!(
            "dv_ft010_b02_{}_{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        )));
        let allowed = workspace.0.join("allowed");
        let outside = workspace.0.join("outside_transfer_root");
        std::fs::create_dir_all(&allowed).unwrap();
        std::fs::create_dir_all(&outside).unwrap();

        // Exact 43-byte victim payload from Codex FT010-B02 reproduction
        let victim_bytes: &[u8] = b"OUTSIDE_VICTIM_SECRET_43_BYTES_DO_NOT_TOUCH";
        assert_eq!(victim_bytes.len(), 43);
        let victim = outside.join("victim.txt");
        std::fs::write(&victim, victim_bytes).unwrap();

        // Case 1: Preexisting .download hardlink on fresh upload MUST error without truncating victim!
        let staged_hardlink = allowed.join("payload.bin.download");
        std::fs::hard_link(&victim, &staged_hardlink).unwrap();

        let (payload_sha, _) = {
            let tmp = outside.join("src_payload.bin");
            std::fs::write(&tmp, b"NEW_DATA").unwrap();
            compute_file_sha256_and_size(&tmp).unwrap()
        };

        let mut fresh_writer = TransferJob::new_write(
            91,
            JobType::Generic,
            "".to_string(),
            DataSource::FilePath(allowed.clone()),
            0,
            false,
            false,
            false,
        )
        .with_files(vec![FileEntry {
            name: "payload.bin".to_string(),
            size: 8,
            sha256: payload_sha.clone(),
            ..Default::default()
        }])
        .unwrap();

        let err = fresh_writer
            .write(FileTransferBlock {
                id: 91,
                file_num: 0,
                data: b"NEW_DATA".to_vec().into(),
                compressed: false,
                ..Default::default()
            })
            .await
            .expect_err("fresh upload must reject preexisting hard-linked .download staging file");
        assert!(
            err.to_string().contains("hard-linked"),
            "unexpected error: {}",
            err
        );
        fresh_writer.remove_download_file();
        // Out-of-root victim MUST remain byte-identical (43 bytes, never truncated to 0!)
        assert_eq!(std::fs::read(&victim).unwrap(), victim_bytes);
        std::fs::remove_file(&staged_hardlink).unwrap();

        // Case 2: Preexisting .digest hardlink on fresh upload MUST error without truncating victim!
        let digest_hardlink = allowed.join("payload2.bin.digest");
        std::fs::hard_link(&victim, &digest_hardlink).unwrap();
        let mut digest_writer = TransferJob::new_write(
            92,
            JobType::Generic,
            "".to_string(),
            DataSource::FilePath(allowed.clone()),
            0,
            false,
            false,
            false,
        )
        .with_files(vec![FileEntry {
            name: "payload2.bin".to_string(),
            size: 8,
            sha256: payload_sha.clone(),
            ..Default::default()
        }])
        .unwrap();
        assert!(digest_writer
            .write(FileTransferBlock {
                id: 92,
                file_num: 0,
                data: b"NEW_DATA".to_vec().into(),
                compressed: false,
                ..Default::default()
            })
            .await
            .is_err());
        assert_eq!(std::fs::read(&victim).unwrap(), victim_bytes);
        std::fs::remove_file(&digest_hardlink).unwrap();

        // Case 3: Upload resume with hard-linked .download MUST fail closed without modifying victim!
        let resume_dl = allowed.join("resumed.bin.download");
        let resume_dg = allowed.join("resumed.bin.digest");
        std::fs::hard_link(&victim, &resume_dl).unwrap();
        std::fs::write(&resume_dg, r#"{"size":51,"modified":1}"#).unwrap();

        let mut resume_writer = TransferJob::new_write(
            93,
            JobType::Generic,
            "".to_string(),
            DataSource::FilePath(allowed.clone()),
            0,
            false,
            false,
            true,
        )
        .with_files(vec![FileEntry {
            name: "resumed.bin".to_string(),
            size: 51,
            sha256: payload_sha.clone(),
            ..Default::default()
        }])
        .unwrap();
        resume_writer.is_resume = true;
        resume_writer
            .confirm(&FileTransferSendConfirmRequest {
                id: 93,
                file_num: 0,
                union: Some(file_transfer_send_confirm_request::Union::OffsetBlk(43)),
                ..Default::default()
            })
            .await;
        assert!(resume_writer
            .write(FileTransferBlock {
                id: 93,
                file_num: 0,
                data: b"APPENDED".to_vec().into(),
                compressed: false,
                ..Default::default()
            })
            .await
            .is_err());
        assert_eq!(std::fs::read(&victim).unwrap(), victim_bytes);
        std::fs::remove_file(&resume_dl).unwrap();
        std::fs::remove_file(&resume_dg).unwrap();

        // Case 4: Valid fresh upload still succeeds cleanly
        let mut valid_writer = TransferJob::new_write(
            94,
            JobType::Generic,
            "".to_string(),
            DataSource::FilePath(allowed.clone()),
            0,
            false,
            false,
            false,
        )
        .with_files(vec![FileEntry {
            name: "clean_ok.bin".to_string(),
            size: 8,
            sha256: payload_sha,
            ..Default::default()
        }])
        .unwrap();
        valid_writer
            .write(FileTransferBlock {
                id: 94,
                file_num: 0,
                data: b"NEW_DATA".to_vec().into(),
                compressed: false,
                ..Default::default()
            })
            .await
            .unwrap();
        valid_writer.flush_and_close_stream().await.unwrap();
        valid_writer.try_finalize_write_files().unwrap();
        assert_eq!(std::fs::read(allowed.join("clean_ok.bin")).unwrap(), b"NEW_DATA");
    }
}

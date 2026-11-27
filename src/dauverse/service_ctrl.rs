use super::crypto_util::{
    check_no_symlink_or_reparse_component, open_no_follow_regular_file, write_atomic_bytes,
};
use hbb_common::{
    bytes::{Bytes, BytesMut},
    bytes_codec::BytesCodec,
    config::{Config, Config2, DEFAULT_SETTINGS, OVERWRITE_SETTINGS},
    tokio::sync::mpsc::UnboundedSender,
    tokio_util::codec::{Decoder, Encoder},
    toml,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet},
    io::{ErrorKind, Read, Write},
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Condvar, Mutex, OnceLock,
    },
    time::{Duration, Instant},
};

static CONSERVATIVE_ACCESS_DENY_LATCH: AtomicBool = AtomicBool::new(false);
static NEXT_ENGINE_REG_ID: AtomicU64 = AtomicU64::new(1);

#[cfg(test)]
static GLOBAL_TEST_SERIAL_BUSY: AtomicBool = AtomicBool::new(false);

#[cfg(test)]
pub(crate) struct GlobalTestSerialToken;

#[cfg(test)]
impl GlobalTestSerialToken {
    pub(crate) fn acquire_sync() -> Self {
        while GLOBAL_TEST_SERIAL_BUSY
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            std::thread::sleep(Duration::from_millis(2));
        }
        Self
    }

    pub(crate) async fn acquire_async() -> Self {
        while GLOBAL_TEST_SERIAL_BUSY
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            hbb_common::tokio::time::sleep(Duration::from_millis(2)).await;
        }
        Self
    }
}

#[cfg(test)]
impl Drop for GlobalTestSerialToken {
    fn drop(&mut self) {
        GLOBAL_TEST_SERIAL_BUSY.store(false, Ordering::SeqCst);
    }
}

struct LiveEngineConnectionEntry {
    conn_id: i32,
    revoked: Arc<AtomicBool>,
    close_sender: UnboundedSender<crate::ipc::Data>,
}

fn live_engine_registry() -> &'static (Mutex<HashMap<u64, LiveEngineConnectionEntry>>, Condvar) {
    static REGISTRY: OnceLock<(Mutex<HashMap<u64, LiveEngineConnectionEntry>>, Condvar)> =
        OnceLock::new();
    REGISTRY.get_or_init(|| (Mutex::new(HashMap::new()), Condvar::new()))
}

pub struct LiveEngineConnectionGuard {
    reg_id: u64,
    revoked: Arc<AtomicBool>,
}

impl LiveEngineConnectionGuard {
    pub fn revoked_flag(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.revoked)
    }

    pub fn is_revoked(&self) -> bool {
        self.revoked.load(Ordering::SeqCst) || is_conservative_access_denied()
    }
}

impl Drop for LiveEngineConnectionGuard {
    fn drop(&mut self) {
        let (lock, cvar) = live_engine_registry();
        let mut map = lock.lock().unwrap();
        map.remove(&self.reg_id);
        cvar.notify_all();
    }
}

#[inline]
pub fn is_conservative_access_denied() -> bool {
    CONSERVATIVE_ACCESS_DENY_LATCH.load(Ordering::SeqCst)
}

#[inline]
pub fn set_conservative_access_denied(deny: bool) {
    CONSERVATIVE_ACCESS_DENY_LATCH.store(deny, Ordering::SeqCst);
}

pub fn register_live_engine_connection(
    conn_id: i32,
    close_sender: UnboundedSender<crate::ipc::Data>,
) -> LiveEngineConnectionGuard {
    let reg_id = NEXT_ENGINE_REG_ID.fetch_add(1, Ordering::SeqCst);
    let initially_revoked = is_conservative_access_denied();
    let revoked = Arc::new(AtomicBool::new(initially_revoked));
    let (lock, _) = live_engine_registry();
    let mut map = lock.lock().unwrap();
    map.insert(
        reg_id,
        LiveEngineConnectionEntry {
            conn_id,
            revoked: Arc::clone(&revoked),
            close_sender,
        },
    );
    LiveEngineConnectionGuard { reg_id, revoked }
}

pub fn active_live_engine_connection_count() -> usize {
    let (lock, _) = live_engine_registry();
    lock.lock().unwrap().len()
}

pub fn revoke_all_local_engine_connections(timeout: Duration) -> Result<usize, String> {
    let (lock, cvar) = live_engine_registry();
    let target_reg_ids: HashSet<u64> = {
        let map = lock.lock().unwrap();
        let mut ids = HashSet::with_capacity(map.len());
        for (&reg_id, entry) in map.iter() {
            entry.revoked.store(true, Ordering::SeqCst);
            for perm in ["keyboard", "clipboard", "audio", "file", "restart"] {
                let _ = entry.close_sender.send(crate::ipc::Data::SwitchPermission {
                    name: perm.to_owned(),
                    enabled: false,
                });
            }
            let _ = entry.close_sender.send(crate::ipc::Data::Close);
            let _ = entry.conn_id;
            ids.insert(reg_id);
        }
        ids
    };

    #[cfg(not(target_os = "ios"))]
    let _ = crate::ui_cm_interface::kick_all_cm_clients_for_revoke();

    if let Some(rt) = super::DauverseRuntime::try_global() {
        let _ = rt
            .transfer_queue
            .fail_all_active_transfers("EMERGENCY_REVOKE_ALL_ACCESS");
    }

    if target_reg_ids.is_empty() {
        return Ok(0);
    }

    let deadline = Instant::now() + timeout;
    let mut map = lock.lock().unwrap();
    while map.keys().any(|k| target_reg_ids.contains(k)) {
        let now = Instant::now();
        if now >= deadline {
            let remaining = map.keys().filter(|k| target_reg_ids.contains(k)).count();
            set_conservative_access_denied(true);
            return Err(format!(
                "ENGINE_REVOKE_DISCONNECT_TIMEOUT: {remaining} live engine connection(s) did not acknowledge disconnect within {}ms",
                timeout.as_millis()
            ));
        }
        let wait_dur = deadline.saturating_duration_since(now);
        let (next_map, _) = cvar.wait_timeout(map, wait_dur).unwrap();
        map = next_map;
    }
    Ok(target_reg_ids.len())
}

pub fn execute_in_process_server_emergency_revoke() -> Result<usize, String> {
    set_conservative_access_denied(true);
    hbb_common::password_security::update_temporary_password();
    let disconnected = revoke_all_local_engine_connections(Duration::from_secs(3));
    let cfg_res = commit_security_config2_options_at(
        &Config2::file(),
        &[
            ("approve-mode", "click"),
            ("enable-keyboard", "N"),
            ("enable-clipboard", "N"),
            ("enable-file-transfer", "N"),
            ("stop-service", "Y"),
        ],
        true,
    );
    let count = disconnected?;
    cfg_res?;
    Ok(count)
}

fn encode_ipc_revoke_request() -> Result<BytesMut, String> {
    let payload = serde_json::to_vec(&crate::ipc::Data::DauverseEmergencyRevoke(None))
        .map_err(|e| format!("IPC_REVOKE_SERIALIZE_FAILED: {e}"))?;
    let mut codec = BytesCodec::new();
    let mut out = BytesMut::new();
    codec
        .encode(Bytes::from(payload), &mut out)
        .map_err(|e| format!("IPC_REVOKE_ENCODE_FAILED: {e}"))?;
    Ok(out)
}

fn read_and_decode_ipc_revoke_ack<R: Read>(reader: &mut R) -> Result<usize, String> {
    let mut codec = BytesCodec::new();
    codec.set_max_packet_length(64 * 1024);
    let mut buf = BytesMut::with_capacity(1024);
    let mut chunk = [0u8; 1024];
    loop {
        if let Some(frame) = codec
            .decode(&mut buf)
            .map_err(|e| format!("IPC_REVOKE_DECODE_FAILED: {e}"))?
        {
            let msg: crate::ipc::Data = serde_json::from_slice(&frame)
                .map_err(|e| format!("IPC_REVOKE_DESERIALIZE_FAILED: {e}"))?;
            return match msg {
                crate::ipc::Data::DauverseEmergencyRevoke(Some(res)) => res,
                _ => Err(
                    "IPC_REVOKE_UNEXPECTED_RESPONSE: server did not return DauverseEmergencyRevoke acknowledgement"
                        .to_owned(),
                ),
            };
        }
        let n = reader
            .read(&mut chunk)
            .map_err(|e| format!("IPC_REVOKE_READ_FAILED: {e}"))?;
        if n == 0 {
            return Err(
                "IPC_REVOKE_EOF_BEFORE_ACK: server closed IPC channel before acknowledging revoke"
                    .to_owned(),
            );
        }
        buf.extend_from_slice(&chunk[..n]);
    }
}

#[cfg(unix)]
pub(crate) fn request_local_server_ipc_revoke_sync(
    ipc_path_str: &str,
    timeout: Duration,
) -> Result<Option<usize>, String> {
    if ipc_path_str.trim().is_empty() {
        return Ok(None);
    }
    let mut stream = match std::os::unix::net::UnixStream::connect(ipc_path_str) {
        Ok(s) => s,
        Err(e)
            if matches!(
                e.kind(),
                ErrorKind::NotFound | ErrorKind::ConnectionRefused
            ) =>
        {
            return Ok(None);
        }
        Err(e) => {
            return Err(format!(
                "IPC_REVOKE_CONNECT_FAILED: failed connecting to '{}': {e}",
                ipc_path_str
            ));
        }
    };
    stream
        .set_write_timeout(Some(timeout))
        .map_err(|e| format!("IPC_REVOKE_SET_WRITE_TIMEOUT_FAILED: {e}"))?;
    stream
        .set_read_timeout(Some(timeout))
        .map_err(|e| format!("IPC_REVOKE_SET_READ_TIMEOUT_FAILED: {e}"))?;
    let frame = encode_ipc_revoke_request()?;
    stream
        .write_all(&frame)
        .map_err(|e| format!("IPC_REVOKE_WRITE_FAILED: {e}"))?;
    stream
        .flush()
        .map_err(|e| format!("IPC_REVOKE_FLUSH_FAILED: {e}"))?;
    read_and_decode_ipc_revoke_ack(&mut stream).map(Some)
}

#[cfg(windows)]
pub(crate) fn request_local_server_ipc_revoke_sync(
    ipc_path_str: &str,
    timeout: Duration,
) -> Result<Option<usize>, String> {
    use std::os::windows::{fs::OpenOptionsExt, io::AsRawHandle};
    use windows::Win32::{
        Foundation::ERROR_PIPE_BUSY,
        Storage::FileSystem::{FILE_GENERIC_READ, FILE_WRITE_DATA, SECURITY_IDENTIFICATION},
    };
    const CLIENT_ACCESS: u32 = FILE_GENERIC_READ.0 | FILE_WRITE_DATA.0;
    let trimmed = ipc_path_str.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let pipe_path = if trimmed.starts_with(r"\\.\pipe\") {
        trimmed.to_owned()
    } else {
        format!(r"\\.\pipe\{trimmed}")
    };
    let deadline = std::time::Instant::now() + timeout;
    let mut pipe = loop {
        match std::fs::OpenOptions::new()
            .access_mode(CLIENT_ACCESS)
            .share_mode(0)
            .security_qos_flags(SECURITY_IDENTIFICATION.0)
            .open(&pipe_path)
        {
            Ok(f) => break f,
            Err(e) if e.kind() == ErrorKind::NotFound => return Ok(None),
            Err(e) if e.raw_os_error() == Some(ERROR_PIPE_BUSY.0 as i32) => {
                if std::time::Instant::now() >= deadline {
                    return Err(format!(
                        "IPC_REVOKE_PIPE_BUSY_TIMEOUT: '{pipe_path}' remained busy for {}ms",
                        timeout.as_millis()
                    ));
                }
                std::thread::sleep(Duration::from_millis(25));
            }
            Err(e) => {
                return Err(format!(
                    "IPC_REVOKE_PIPE_OPEN_FAILED: failed opening '{pipe_path}': {e}"
                ));
            }
        }
    };
    crate::ipc::ensure_raw_pipe_server(pipe.as_raw_handle(), false)
        .map_err(|e| format!("IPC_REVOKE_UNTRUSTED_PIPE_SERVER: '{pipe_path}': {e}"))?;
    let frame = encode_ipc_revoke_request()?;
    let remaining = deadline.saturating_duration_since(std::time::Instant::now());
    if remaining.is_zero() {
        return Err(format!(
            "IPC_REVOKE_TIMEOUT: deadline expired before writing revoke frame to '{pipe_path}'"
        ));
    }
    let (tx, rx) = std::sync::mpsc::sync_channel::<Result<usize, String>>(1);
    std::thread::spawn(move || {
        let outcome = pipe
            .write_all(&frame)
            .map_err(|e| format!("IPC_REVOKE_WRITE_FAILED: {e}"))
            .and_then(|_| {
                pipe.flush()
                    .map_err(|e| format!("IPC_REVOKE_FLUSH_FAILED: {e}"))
            })
            .and_then(|_| read_and_decode_ipc_revoke_ack(&mut pipe));
        let _ = tx.send(outcome);
    });
    match rx.recv_timeout(remaining) {
        Ok(res) => res.map(Some),
        Err(_) => Err(format!(
            "IPC_REVOKE_TIMEOUT: local --server pipe did not acknowledge revoke within {}ms",
            timeout.as_millis()
        )),
    }
}

#[cfg(not(any(unix, windows)))]
pub(crate) fn request_local_server_ipc_revoke_sync(
    _ipc_path_str: &str,
    _timeout: Duration,
) -> Result<Option<usize>, String> {
    Ok(None)
}

pub fn effective_option_from_config2(cfg2: &Config2, key: &str) -> String {
    if let Some(forced) = OVERWRITE_SETTINGS.read().unwrap().get(key) {
        return forced.clone();
    }
    if let Some(val) = cfg2.options.get(key) {
        return val.clone();
    }
    if let Some(def) = DEFAULT_SETTINGS.read().unwrap().get(key) {
        return def.clone();
    }
    String::new()
}

pub fn read_durable_config2_at(cfg_path: &Path) -> Result<(Config2, Option<toml::Value>), String> {
    match std::fs::symlink_metadata(cfg_path) {
        Ok(_) => {
            check_no_symlink_or_reparse_component(cfg_path)?;
        }
        Err(e) if e.kind() == ErrorKind::NotFound => {
            if let Some(parent) = cfg_path.parent().filter(|p| !p.as_os_str().is_empty()) {
                if parent.exists() {
                    check_no_symlink_or_reparse_component(parent)?;
                }
            }
            return Ok((Config2::default(), None));
        }
        Err(e) => {
            return Err(format!(
                "CONFIG2_DURABLE_STAT_FAILED: '{}': {e}",
                cfg_path.display()
            ));
        }
    }

    let (mut file, _) = open_no_follow_regular_file(cfg_path)
        .map_err(|e| format!("CONFIG2_DURABLE_OPEN_FAILED: {e}"))?;
    let mut raw_bytes = Vec::new();
    file.read_to_end(&mut raw_bytes)
        .map_err(|e| format!("CONFIG2_DURABLE_READ_FAILED: '{}': {e}", cfg_path.display()))?;
    let raw_text = String::from_utf8(raw_bytes)
        .map_err(|e| format!("CONFIG2_DURABLE_UTF8_INVALID: '{}': {e}", cfg_path.display()))?;
    let doc: toml::Value = toml::from_str(&raw_text)
        .map_err(|e| format!("CONFIG2_DURABLE_PARSE_FAILED: '{}': {e}", cfg_path.display()))?;
    if let Some(td_v2) = doc.get("trusted_devices_v2") {
        if !td_v2.is_str() {
            return Err(format!(
                "CONFIG2_CORRUPT_TRUSTED_DEVICES_V2_FIELD: '{}' has non-string trusted_devices_v2",
                cfg_path.display()
            ));
        }
    }
    let parsed_cfg2: Config2 = toml::from_str(&raw_text)
        .map_err(|e| format!("CONFIG2_DURABLE_SCHEMA_FAILED: '{}': {e}", cfg_path.display()))?;
    Ok((parsed_cfg2, Some(doc)))
}

fn commit_atomic_config2_file(cfg_path: &Path, data: &[u8]) -> Result<(), String> {
    let parent = cfg_path
        .parent()
        .ok_or_else(|| format!("missing parent directory for '{}'", cfg_path.display()))?;
    if !parent.exists() {
        return write_atomic_bytes(cfg_path, data, true);
    }
    check_no_symlink_or_reparse_component(parent)?;
    check_no_symlink_or_reparse_component(cfg_path)?;

    let file_name = cfg_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("RustDesk2.toml");
    let tmp_path = parent.join(format!(".{file_name}.tmp.{}", uuid::Uuid::new_v4()));

    let write_res: Result<(), String> = (|| {
        #[cfg(unix)]
        {
            use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
            let mut opts = std::fs::OpenOptions::new();
            opts.write(true)
                .create_new(true)
                .mode(0o600)
                .custom_flags(hbb_common::libc::O_NOFOLLOW);
            let mut f = opts
                .open(&tmp_path)
                .map_err(|e| format!("failed opening atomic temp file: {e}"))?;
            f.set_permissions(std::fs::Permissions::from_mode(0o600))
                .map_err(|e| format!("failed setting 0600 permissions: {e}"))?;
            f.write_all(data)
                .map_err(|e| format!("failed writing atomic temp file: {e}"))?;
            f.sync_all()
                .map_err(|e| format!("failed syncing atomic temp file: {e}"))?;
        }
        #[cfg(not(unix))]
        {
            return write_atomic_bytes(cfg_path, data, true);
        }
        #[cfg(unix)]
        {
            std::fs::rename(&tmp_path, cfg_path)
                .map_err(|e| format!("atomic rename to '{}' failed: {e}", cfg_path.display()))?;
            if let Ok(dir_handle) = std::fs::File::open(parent) {
                let _ = dir_handle.sync_all();
            }
            Ok(())
        }
    })();

    if write_res.is_err() {
        let _ = std::fs::remove_file(&tmp_path);
    }
    write_res
}

pub fn commit_security_config2_options_at(
    cfg_path: &Path,
    updates: &[(&str, &str)],
    conservative_deny_on_error: bool,
) -> Result<Config2, String> {
    let fail_with_policy = |msg: String| -> Result<Config2, String> {
        if conservative_deny_on_error {
            set_conservative_access_denied(true);
        }
        Err(msg)
    };

    {
        let overwrite = OVERWRITE_SETTINGS.read().unwrap();
        for &(k, v) in updates {
            if let Some(forced) = overwrite.get(k) {
                if forced != v {
                    return fail_with_policy(format!(
                        "CONFIG2_POLICY_OVERRIDE_CONFLICT: option '{k}' is locked to '{forced}' by policy override"
                    ));
                }
            }
        }
    }

    let (_existing_cfg2, existing_doc_opt) = match read_durable_config2_at(cfg_path) {
        Ok(v) => v,
        Err(e) => return fail_with_policy(e),
    };

    let preserved_credentials: Vec<(&str, Option<toml::Value>)> = [
        "unlock_pin",
        "trusted_devices",
        "trusted_devices_v2",
        "socks",
    ]
    .iter()
    .map(|&field| {
        (
            field,
            existing_doc_opt
                .as_ref()
                .and_then(|d| d.get(field).cloned()),
        )
    })
    .collect();

    let mut working_doc = match existing_doc_opt {
        Some(doc) => doc,
        None => match toml::Value::try_from(Config2::get()) {
            Ok(v) => v,
            Err(e) => {
                return fail_with_policy(format!("CONFIG2_SERIALIZE_SEED_FAILED: {e}"));
            }
        },
    };

    {
        let Some(root_table) = working_doc.as_table_mut() else {
            return fail_with_policy(
                "CONFIG2_INVALID_ROOT_TABLE: Config2 document root is not a TOML table".to_owned(),
            );
        };
        let options_entry = root_table
            .entry("options")
            .or_insert_with(|| toml::Value::Table(toml::map::Map::new()));
        let Some(options_table) = options_entry.as_table_mut() else {
            return fail_with_policy(
                "CONFIG2_INVALID_OPTIONS_TABLE: 'options' field is not a TOML table".to_owned(),
            );
        };
        let defaults = DEFAULT_SETTINGS.read().unwrap();
        for &(k, v) in updates {
            let is_default_or_empty =
                v.is_empty() || defaults.get(k).map(String::as_str) == Some(v);
            if is_default_or_empty {
                options_table.remove(k);
            } else {
                options_table.insert(k.to_owned(), toml::Value::String(v.to_owned()));
            }
        }
    }

    let serialized = match toml::to_string(&working_doc) {
        Ok(s) => s,
        Err(e) => return fail_with_policy(format!("CONFIG2_TOML_ENCODE_FAILED: {e}")),
    };
    if let Err(e) = toml::from_str::<Config2>(&serialized) {
        return fail_with_policy(format!("CONFIG2_PREWRITE_VALIDATE_FAILED: {e}"));
    }

    if let Err(write_err) = commit_atomic_config2_file(cfg_path, serialized.as_bytes()) {
        return fail_with_policy(format!("CONFIG2_ATOMIC_COMMIT_FAILED: {write_err}"));
    }

    let is_live_config2_file = cfg_path == Config2::file();
    let prev_mem_options = is_live_config2_file.then(|| Config2::get().options);
    let fail_after_mem_sync = |msg: String| -> Result<Config2, String> {
        if !conservative_deny_on_error {
            if let Some(prev_opts) = prev_mem_options.clone() {
                Config::set_options(prev_opts);
            }
        }
        fail_with_policy(msg)
    };
    if is_live_config2_file {
        for &(k, v) in updates {
            Config::set_option(k.to_owned(), v.to_owned());
        }
        // Re-commit our atomic fsynced document so Config::set_option's non-fsynced confy store
        // cannot degrade permissions, atomicity, or preserved raw fields on disk.
        if let Err(write_err) = commit_atomic_config2_file(cfg_path, serialized.as_bytes()) {
            return fail_after_mem_sync(format!("CONFIG2_POST_SYNC_COMMIT_FAILED: {write_err}"));
        }
    }

    let (verified_cfg2, verified_doc_opt) = match read_durable_config2_at(cfg_path) {
        Ok(v) => v,
        Err(e) => return fail_after_mem_sync(format!("CONFIG2_READBACK_VERIFY_FAILED: {e}")),
    };
    let Some(verified_doc) = verified_doc_opt else {
        return fail_after_mem_sync(
            "CONFIG2_READBACK_MISSING: committed Config2 file disappeared during verification"
                .to_owned(),
        );
    };

    for &(k, expected_v) in updates {
        let actual_v = effective_option_from_config2(&verified_cfg2, k);
        if actual_v != expected_v {
            return fail_after_mem_sync(format!(
                "CONFIG2_DURABLE_OPTION_MISMATCH: option '{k}' expected '{expected_v}', durable readback got '{actual_v}'"
            ));
        }
    }

    for (field, before_val) in preserved_credentials {
        if let Some(expected_cred) = before_val {
            let after_val = verified_doc.get(field);
            if after_val != Some(&expected_cred) {
                return fail_after_mem_sync(format!(
                    "CONFIG2_CREDENTIAL_PRESERVATION_FAILED: durable field '{field}' changed unexpectedly during option commit"
                ));
            }
        }
    }

    #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
    if is_live_config2_file {
        if let Err(sync_err) = Config2::get_for_sync() {
            return fail_after_mem_sync(format!(
                "CONFIG2_PINNED_API_SYNC_VERIFY_FAILED: {sync_err}"
            ));
        }
    }

    Ok(verified_cfg2)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ServiceRunState {
    Running,
    Stopped,
    DegradedRecovering,
    NotInstalledPortableMode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceStartupState {
    pub scm_service_name: String,
    pub scm_display_name: String,
    pub service_state: ServiceRunState,
    pub desired_auto_start: bool,
    pub auto_start_with_windows: bool,
    pub desired_unattended_enabled: bool,
    pub unattended_access_enabled: bool,
    pub service_owned_by_dauverse: Option<bool>,
    pub external_service_collision_detected: bool,
    pub observed_service_binary_path: Option<String>,
    pub pre_login_session_helper_enabled: bool,
    pub privilege_separation_enforced: bool,
    pub system_tray_indicator_visible: bool,
    pub active_remote_banner_visible: bool,
    pub defender_av_untouched: bool,
    pub no_hidden_persistence: bool,
    pub boss_service_install_approved: bool,
    pub last_health_check_utc: String,
    pub recovery_restart_count: u32,
    #[serde(default = "default_true")]
    pub config_persistence_healthy: bool,
    #[serde(default)]
    pub last_persistence_error: Option<String>,
    #[serde(default)]
    pub conservative_access_deny_latched: bool,
    #[serde(default)]
    pub active_engine_connections_count: usize,
}

fn default_true() -> bool {
    true
}

pub fn is_service_image_path_owned_by_install_dir(image_path: &str, install_dir: &str) -> bool {
    let clean_img = image_path
        .trim()
        .trim_start_matches('"')
        .replace('/', "\\")
        .to_ascii_lowercase();
    let mut clean_dir = install_dir
        .trim()
        .trim_matches('"')
        .replace('/', "\\")
        .trim_end_matches('\\')
        .to_ascii_lowercase();
    if clean_dir.is_empty() {
        return false;
    }
    clean_dir.push('\\');
    clean_img.starts_with(&clean_dir)
}

#[cfg(target_os = "windows")]
fn query_owned_scm_service_state(service_name: &str) -> (ServiceRunState, Option<String>) {
    use windows_service::{
        service::{ServiceAccess, ServiceState},
        service_manager::{ServiceManager, ServiceManagerAccess},
    };
    let manager = match ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
    {
        Ok(m) => m,
        Err(e) => {
            return (
                ServiceRunState::DegradedRecovering,
                Some(format!("SERVICE_SCM_CONNECT_FAILED: {e}")),
            )
        }
    };
    let svc = match manager.open_service(service_name, ServiceAccess::QUERY_STATUS) {
        Ok(s) => s,
        Err(e) => {
            return (
                ServiceRunState::DegradedRecovering,
                Some(format!("SERVICE_SCM_OPEN_QUERY_FAILED: {e}")),
            )
        }
    };
    match svc.query_status() {
        Ok(st) => match st.current_state {
            ServiceState::Stopped => (ServiceRunState::Stopped, None),
            ServiceState::Running => (ServiceRunState::Running, None),
            _ => (ServiceRunState::DegradedRecovering, None),
        },
        Err(e) => (
            ServiceRunState::DegradedRecovering,
            Some(format!("SERVICE_SCM_QUERY_STATUS_FAILED: {e}")),
        ),
    }
}

#[cfg(target_os = "windows")]
fn query_windows_service_ownership_and_run_state_detailed() -> (
    ServiceRunState,
    Option<bool>,
    bool,
    Option<String>,
    bool,
    Option<String>,
) {
    use winreg::{
        enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, KEY_READ},
        RegKey,
    };

    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_string_lossy().into_owned()))
        .unwrap_or_default();

    let mut query_err: Option<String> = None;
    let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
    let (svc_state, owned, collision, img_opt) = match hklm.open_subkey_with_flags(
        "SYSTEM\\CurrentControlSet\\Services\\RustDesk",
        KEY_READ,
    ) {
        Ok(svc_key) => {
            let img: String = match svc_key.get_value("ImagePath") {
                Ok(v) => v,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
                Err(e) => {
                    query_err = Some(format!("SERVICE_IMAGE_PATH_READ_FAILED: {e}"));
                    String::new()
                }
            };
            if is_service_image_path_owned_by_install_dir(&img, &exe_dir) {
                let (st, scm_err) = query_owned_scm_service_state("RustDesk");
                if query_err.is_none() {
                    query_err = scm_err;
                }
                (st, Some(true), false, Some(img))
            } else {
                // External RustDesk installation owns the SCM "RustDesk" service; do NOT claim or touch it!
                (
                    ServiceRunState::NotInstalledPortableMode,
                    Some(false),
                    true,
                    Some(img),
                )
            }
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            (ServiceRunState::NotInstalledPortableMode, None, false, None)
        }
        Err(e) => {
            query_err = Some(format!("SERVICE_REGISTRY_OPEN_FAILED: {e}"));
            (ServiceRunState::DegradedRecovering, None, false, None)
        }
    };

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let run_present = match hkcu.open_subkey_with_flags(
        "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
        KEY_READ,
    ) {
        Ok(k) => match k.get_value::<String, _>("DauverseRemoteDesktop") {
            Ok(val) => is_service_image_path_owned_by_install_dir(&val, &exe_dir),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => false,
            Err(e) => {
                if query_err.is_none() {
                    query_err = Some(format!("SERVICE_RUN_VALUE_READ_FAILED: {e}"));
                }
                false
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => false,
        Err(e) => {
            if query_err.is_none() {
                query_err = Some(format!("SERVICE_RUN_KEY_READ_FAILED: {e}"));
            }
            false
        }
    };

    (svc_state, owned, collision, img_opt, run_present, query_err)
}

#[cfg(target_os = "windows")]
fn query_windows_service_ownership_and_run_state() -> (
    ServiceRunState,
    Option<bool>,
    bool,
    Option<String>,
    bool,
) {
    let (svc_state, owned, collision, img_opt, run_present, _err) =
        query_windows_service_ownership_and_run_state_detailed();
    (svc_state, owned, collision, img_opt, run_present)
}

impl Default for ServiceStartupState {
    fn default() -> Self {
        Self {
            scm_service_name: "RustDesk".to_owned(),
            scm_display_name: "DAUVERSE Remote Desktop Service (RustDesk Engine)".to_owned(),
            service_state: ServiceRunState::NotInstalledPortableMode,
            desired_auto_start: false,
            auto_start_with_windows: false,
            desired_unattended_enabled: false,
            unattended_access_enabled: false,
            service_owned_by_dauverse: None,
            external_service_collision_detected: false,
            observed_service_binary_path: None,
            pre_login_session_helper_enabled: false,
            privilege_separation_enforced: true,
            system_tray_indicator_visible: true,
            active_remote_banner_visible: true,
            defender_av_untouched: true,
            no_hidden_persistence: true,
            boss_service_install_approved: false,
            last_health_check_utc: chrono::Utc::now().to_rfc3339(),
            recovery_restart_count: 0,
            config_persistence_healthy: true,
            last_persistence_error: None,
            conservative_access_deny_latched: false,
            active_engine_connections_count: 0,
        }
    }
}

pub struct ServiceController {
    state: Mutex<ServiceStartupState>,
}

impl ServiceController {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(ServiceStartupState::default()),
        }
    }

    pub fn is_service_running(&self) -> bool {
        self.status().service_state == ServiceRunState::Running
    }

    pub fn commit_security_options(
        &self,
        updates: &[(&str, &str)],
        conservative_deny_on_error: bool,
    ) -> Result<Config2, String> {
        match commit_security_config2_options_at(
            &Config2::file(),
            updates,
            conservative_deny_on_error,
        ) {
            Ok(cfg2) => {
                let mut g = self.state.lock().unwrap();
                g.config_persistence_healthy = true;
                g.last_persistence_error = None;
                g.conservative_access_deny_latched = is_conservative_access_denied();
                Ok(cfg2)
            }
            Err(e) => {
                let mut g = self.state.lock().unwrap();
                g.config_persistence_healthy = false;
                g.last_persistence_error = Some(e.clone());
                g.conservative_access_deny_latched = is_conservative_access_denied();
                Err(e)
            }
        }
    }

    pub fn status(&self) -> ServiceStartupState {
        let durable_read = read_durable_config2_at(&Config2::file());
        let deny_latched = is_conservative_access_denied();
        let active_conns = active_live_engine_connection_count();

        let mut g = self.state.lock().unwrap();
        #[cfg(target_os = "windows")]
        {
            let (svc_state, owned, collision, img_opt, run_present) =
                query_windows_service_and_autorun_compat();
            g.service_state = svc_state;
            g.service_owned_by_dauverse = owned;
            g.external_service_collision_detected = collision;
            g.observed_service_binary_path = img_opt;
            #[cfg(not(test))]
            {
                g.auto_start_with_windows = run_present;
            }
            #[cfg(test)]
            {
                let _ = run_present;
            }
        }

        match durable_read {
            Ok((durable_cfg2, Some(_))) => {
                let approve_mode = effective_option_from_config2(&durable_cfg2, "approve-mode");
                g.config_persistence_healthy = true;
                g.last_persistence_error = None;
                g.unattended_access_enabled = !deny_latched
                    && !approve_mode.is_empty()
                    && approve_mode != "click"
                    && !g.external_service_collision_detected;
            }
            Ok((durable_cfg2, None)) => {
                let approve_mode = effective_option_from_config2(&durable_cfg2, "approve-mode");
                if g.last_persistence_error.is_none() {
                    g.config_persistence_healthy = true;
                }
                g.unattended_access_enabled = !deny_latched
                    && g.config_persistence_healthy
                    && !approve_mode.is_empty()
                    && approve_mode != "click"
                    && !g.external_service_collision_detected;
            }
            Err(err) => {
                g.config_persistence_healthy = false;
                g.last_persistence_error = Some(err);
                g.unattended_access_enabled = false;
            }
        }
        g.conservative_access_deny_latched = deny_latched;
        g.active_engine_connections_count = active_conns;
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        g.clone()
    }

    pub fn configure_unattended(
        &self,
        enable: bool,
        owner_authenticated: bool,
    ) -> Result<ServiceStartupState, String> {
        if !owner_authenticated {
            return Err("AUTH_REQUIRED_FOR_UNATTENDED_CONFIG".to_owned());
        }
        let current = self.status();
        if enable && current.external_service_collision_detected {
            return Err(
                "SERVICE_COLLISION_EXTERNAL_RUSTDESK_DETECTED: refusing unattended activation while an external RustDesk Windows service owns SCM 'RustDesk'"
                    .to_owned(),
            );
        }
        let target_mode = if enable { "password" } else { "click" };
        let verified_cfg2 = if enable {
            let cfg2 = self.commit_security_options(
                &[("stop-service", ""), ("approve-mode", target_mode)],
                false,
            )?;
            set_conservative_access_denied(false);
            cfg2
        } else {
            self.commit_security_options(&[("approve-mode", target_mode)], true)?
        };
        let actual_mode = effective_option_from_config2(&verified_cfg2, "approve-mode");
        if actual_mode != target_mode {
            return Err(format!(
                "UNATTENDED_CONFIG_VERIFY_FAILED: expected durable approve-mode='{target_mode}', got '{actual_mode}'"
            ));
        }

        {
            let mut g = self.state.lock().unwrap();
            g.desired_unattended_enabled = enable;
            g.unattended_access_enabled = enable;
            g.system_tray_indicator_visible = true;
            g.active_remote_banner_visible = true;
            g.config_persistence_healthy = true;
            g.last_persistence_error = None;
            g.conservative_access_deny_latched = is_conservative_access_denied();
            g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        }
        Ok(self.status())
    }

    pub fn set_auto_start(
        &self,
        enable: bool,
        owner_authenticated: bool,
    ) -> Result<ServiceStartupState, String> {
        if !owner_authenticated {
            return Err("AUTH_REQUIRED_FOR_STARTUP_CONFIG".to_owned());
        }
        #[cfg(all(target_os = "windows", not(test)))]
        {
            use winreg::{
                enums::{HKEY_CURRENT_USER, KEY_SET_VALUE},
                RegKey,
            };
            let exe_path = std::env::current_exe()
                .map_err(|e| format!("failed resolving current_exe for Run key: {e}"))?;
            let hkcu = RegKey::predef(HKEY_CURRENT_USER);
            let run_key = hkcu
                .open_subkey_with_flags(
                    "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    KEY_SET_VALUE,
                )
                .map_err(|e| format!("failed opening HKCU Run key: {e}"))?;
            if enable {
                let cmd = format!("\"{}\" --dauverse-ui", exe_path.display());
                run_key
                    .set_value("DauverseRemoteDesktop", &cmd)
                    .map_err(|e| format!("failed writing HKCU Run entry: {e}"))?;
            } else {
                match run_key.delete_value("DauverseRemoteDesktop") {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => {
                        return Err(format!("failed deleting HKCU Run entry: {e}"));
                    }
                }
            }
            let (_, _, _, _, run_present) = query_windows_service_ownership_and_run_state();
            if run_present != enable {
                return Err(format!(
                    "AUTO_START_REGISTRY_VERIFY_FAILED: expected HKCU Run present={enable}, observed={run_present}"
                ));
            }
        }
        let mut g = self.state.lock().unwrap();
        g.desired_auto_start = enable;
        g.auto_start_with_windows = enable;
        g.no_hidden_persistence = true;
        g.last_health_check_utc = chrono::Utc::now().to_rfc3339();
        Ok(g.clone())
    }

    pub fn revoke_all_access_immediately(&self) -> Result<ServiceStartupState, String> {
        // 1. Immediately engage conservative runtime denial and rotate temporary password
        //    so any concurrent or incoming session attempt is blocked even before disk/OS steps complete.
        set_conservative_access_denied(true);
        hbb_common::password_security::update_temporary_password();

        #[cfg(all(target_os = "windows", not(test)))]
        let (
            before_svc_state,
            before_owned,
            before_collision,
            _img_opt,
            before_run_present,
            before_query_err,
        ) = query_windows_service_ownership_and_run_state_detailed();

        #[cfg(not(all(target_os = "windows", not(test))))]
        let before_collision = {
            let g = self.state.lock().unwrap();
            g.external_service_collision_detected || g.service_owned_by_dauverse == Some(false)
        };

        // 2. Revoke all live in-process engine connections and wait for observable disconnect ACK.
        let mut first_error: Option<String> = None;
        if let Err(local_err) = revoke_all_local_engine_connections(Duration::from_secs(3)) {
            first_error = Some(local_err);
        }

        // 3. If not already in `--server` and no external non-owned RustDesk service collision exists,
        //    send synchronous emergency revoke to any local `--server` IPC listener and require ACK.
        if !crate::is_server() && !before_collision {
            let ipc_path = Config::ipc_path("");
            if let Err(ipc_err) =
                request_local_server_ipc_revoke_sync(&ipc_path, Duration::from_secs(3))
            {
                if first_error.is_none() {
                    first_error = Some(ipc_err);
                }
            }
        }

        // 4. Commit conservative security options atomically to Config2::file() and verify durable disk state.
        let durable_approve_mode = match self.commit_security_options(
            &[
                ("approve-mode", "click"),
                ("enable-keyboard", "N"),
                ("enable-clipboard", "N"),
                ("enable-file-transfer", "N"),
                ("stop-service", "Y"),
            ],
            true,
        ) {
            Ok(verified_cfg2) => effective_option_from_config2(&verified_cfg2, "approve-mode"),
            Err(cfg_err) => {
                if first_error.is_none() {
                    first_error = Some(cfg_err);
                }
                String::new()
            }
        };

        #[cfg(all(target_os = "windows", not(test)))]
        {
            use winreg::{
                enums::{HKEY_CURRENT_USER, KEY_SET_VALUE},
                RegKey,
            };
            let before_query_ok = before_query_err.is_none();
            let mut os_action_err: Option<String> = first_error.or(before_query_err);

            if before_run_present || os_action_err.is_some() {
                match RegKey::predef(HKEY_CURRENT_USER).open_subkey_with_flags(
                    "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    KEY_SET_VALUE,
                ) {
                    Ok(run_key) => match run_key.delete_value("DauverseRemoteDesktop") {
                        Ok(()) => {}
                        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                        Err(e) => {
                            if os_action_err.is_none() {
                                os_action_err =
                                    Some(format!("SERVICE_REVOKE_RUN_KEY_DELETE_FAILED: {e}"));
                            }
                        }
                    },
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => {
                        if os_action_err.is_none() {
                            os_action_err =
                                Some(format!("SERVICE_REVOKE_RUN_KEY_OPEN_FAILED: {e}"));
                        }
                    }
                }
            }

            // Strictly preserve F03 ownership protection: NEVER stop SCM 'RustDesk' unless owned == Some(true)
            if before_query_ok
                && before_owned == Some(true)
                && before_svc_state != ServiceRunState::Stopped
            {
                if let Err(stop_err) = stop_owned_windows_scm_service("RustDesk") {
                    if os_action_err.is_none() {
                        os_action_err = Some(stop_err);
                    }
                }
            }

            {
                let mut g = self.state.lock().unwrap();
                g.desired_unattended_enabled = false;
                g.desired_auto_start = false;
                g.pre_login_session_helper_enabled = false;
            }
            let (
                _after_svc_state,
                _after_owned,
                _after_collision,
                _after_img,
                _after_run,
                after_query_err,
            ) = query_windows_service_ownership_and_run_state_detailed();
            if os_action_err.is_none() {
                os_action_err = after_query_err;
            }
            let refreshed = self.status();
            verify_post_revoke_os_truth_full(
                &durable_approve_mode,
                refreshed.service_owned_by_dauverse,
                refreshed.service_state,
                refreshed.auto_start_with_windows,
                active_live_engine_connection_count(),
                os_action_err,
            )?;
            return Ok(refreshed);
        }

        #[cfg(not(all(target_os = "windows", not(test))))]
        {
            {
                let mut g = self.state.lock().unwrap();
                g.desired_unattended_enabled = false;
                g.desired_auto_start = false;
                g.auto_start_with_windows = false;
                g.pre_login_session_helper_enabled = false;
            }
            let refreshed = self.status();
            verify_post_revoke_os_truth_full(
                &durable_approve_mode,
                refreshed.service_owned_by_dauverse,
                refreshed.service_state,
                refreshed.auto_start_with_windows,
                active_live_engine_connection_count(),
                first_error,
            )?;
            Ok(refreshed)
        }
    }

    pub fn read_live_host_capabilities(&self) -> serde_json::Value {
        let deny = is_conservative_access_denied();
        let cfg2 = read_durable_config2_at(&Config2::file())
            .map(|(c, _)| c)
            .unwrap_or_else(|_| Config2::get());
        let opt_enabled = |key: &str| -> bool {
            if deny {
                return false;
            }
            let v = effective_option_from_config2(&cfg2, key);
            hbb_common::config::option2bool(key, &v)
        };
        let approve_mode = effective_option_from_config2(&cfg2, "approve-mode");
        let stop_service = hbb_common::config::option2bool(
            "stop-service",
            &effective_option_from_config2(&cfg2, "stop-service"),
        );
        let direct_ip = hbb_common::config::option2bool(
            hbb_common::config::keys::OPTION_DIRECT_SERVER,
            &effective_option_from_config2(&cfg2, hbb_common::config::keys::OPTION_DIRECT_SERVER),
        );
        serde_json::json!({
            "conservative_deny_latched": deny,
            "stop_service": stop_service,
            "approve_mode": if approve_mode.is_empty() { "password_and_click".to_owned() } else { approve_mode },
            "direct_ip_access_enabled": direct_ip,
            "enable_keyboard": opt_enabled("enable-keyboard"),
            "enable_clipboard": opt_enabled("enable-clipboard"),
            "enable_file_transfer": opt_enabled("enable-file-transfer"),
            "enable_audio": opt_enabled("enable-audio"),
            "enable_tunnel": opt_enabled("enable-tunnel"),
            "enable_remote_restart": opt_enabled("enable-remote-restart"),
            "enable_record_session": hbb_common::config::option2bool(
                "allow-auto-record-incoming",
                &effective_option_from_config2(&cfg2, "allow-auto-record-incoming"),
            ),
        })
    }

    pub fn windows_access_readiness(&self) -> serde_json::Value {
        let st = self.status();
        let owned_installed = st.service_owned_by_dauverse == Some(true);
        let owned_running = owned_installed && st.service_state == ServiceRunState::Running;
        let has_perm_pw = Config::has_permanent_password();
        let readiness_code = if st.external_service_collision_detected {
            "BLOCKED_EXTERNAL_RUSTDESK_SERVICE_COLLISION"
        } else if owned_running && st.unattended_access_enabled && has_perm_pw {
            "READY_PRELOGIN_AND_UNATTENDED"
        } else if owned_running {
            "SERVICE_RUNNING_AWAITING_UNATTENDED_OR_PASSWORD"
        } else {
            "PORTABLE_OR_USER_SESSION_ONLY"
        };
        serde_json::json!({
            "readiness_code": readiness_code,
            "windows_password_preserved": true,
            "windows_auto_login_disabled": true,
            "owned_service_installed": owned_installed,
            "owned_service_running": owned_running,
            "external_rustdesk_collision": st.external_service_collision_detected,
            "pre_login_winlogon_ready": owned_running,
            "lock_screen_uac_ready": owned_running,
            "auto_start_user_logon": st.auto_start_with_windows,
            "unattended_access_enabled": st.unattended_access_enabled,
            "permanent_password_set": has_perm_pw,
            "service_state": st.service_state,
        })
    }

    pub fn manage_owned_windows_service(
        &self,
        action: &str,
        user_confirmed: bool,
    ) -> Result<ServiceStartupState, String> {
        if !user_confirmed {
            return Err(
                "SECURITY_DENY_USER_CONFIRMATION_REQUIRED: Explicit user confirmation is required for Windows Service operations."
                    .to_owned(),
            );
        }
        let norm_action = action.trim().to_ascii_uppercase();
        if !matches!(
            norm_action.as_str(),
            "INSTALL_AND_START_ELEVATED" | "START_ELEVATED" | "STOP" | "UNINSTALL_ELEVATED"
        ) {
            return Err(format!("UNSUPPORTED_SERVICE_ACTION: {action}"));
        }

        let current_status = self.status();
        if current_status.external_service_collision_detected
            || current_status.service_owned_by_dauverse == Some(false)
        {
            return Err(
                "F03_EXTERNAL_RUSTDESK_SERVICE_COLLISION: An external RustDesk installation owns Windows Service 'RustDesk'; DAUVERSE refuses to modify or delete it."
                    .to_owned(),
            );
        }

        #[cfg(all(target_os = "windows", not(test)))]
        {
            let exe_path = std::env::current_exe()
                .map_err(|e| format!("SERVICE_CURRENT_EXE_FAILED: {e}"))?;
            let exe_dir = exe_path
                .parent()
                .ok_or_else(|| "SERVICE_EXE_DIR_MISSING".to_owned())?;
            check_no_symlink_or_reparse_component(exe_dir)?;
            let svc_exe = exe_dir.join("rustdesk.exe");
            let main_exe = exe_dir.join("DAUVERSE_REMOTE.exe");
            if !svc_exe.is_file() || !main_exe.is_file() {
                return Err(format!(
                    "SERVICE_BINARY_NOT_FOUND: Expected DAUVERSE_REMOTE.exe and rustdesk.exe inside '{}'",
                    exe_dir.display()
                ));
            }
            check_no_symlink_or_reparse_component(&svc_exe)?;

            if norm_action == "STOP" {
                if current_status.service_owned_by_dauverse != Some(true) {
                    return Err(
                        "SERVICE_NOT_REGISTERED_BY_DAUVERSE: Owned Windows Service is not registered."
                            .to_owned(),
                    );
                }
                stop_owned_windows_scm_service("RustDesk")?;
                return Ok(self.status());
            }

            let exe_dir_lc = exe_dir.to_string_lossy().replace('/', "\\").to_ascii_lowercase();
            let is_ephemeral_portable_dir =
                exe_dir_lc.contains("\\appdata\\local\\") || exe_dir_lc.contains("\\temp\\");
            if norm_action == "INSTALL_AND_START_ELEVATED"
                && (!crate::platform::is_installed() || is_ephemeral_portable_dir)
            {
                return Err(
                    "SERVICE_REQUIRES_NSIS_INSTALLATION: Run DAUVERSE_REMOTE_DESKTOP_V1_SETUP.exe from the installed Program Files directory before registering the system-wide pre-login Windows Service (portable extraction directories are not registered in SCM)."
                        .to_owned(),
                );
            }

            let svc_exe_str = svc_exe.to_string_lossy().replace('"', "");
            let cmd_line = match norm_action.as_str() {
                "INSTALL_AND_START_ELEVATED" => {
                    let _ = self.commit_security_options(&[("stop-service", "N")], false);
                    set_conservative_access_denied(false);
                    format!(
                        "/c sc create RustDesk binPath= \"\\\"{svc_exe_str}\\\" --service\" start= auto DisplayName= \"DAUVERSE Remote Desktop Service (RustDesk Engine)\" & sc failure RustDesk reset= 86400 actions= restart/5000/restart/15000/restart/30000 & sc start RustDesk"
                    )
                }
                "START_ELEVATED" => {
                    if current_status.service_owned_by_dauverse != Some(true) {
                        return Err(
                            "SERVICE_NOT_REGISTERED_BY_DAUVERSE: Install the owned Windows Service first."
                                .to_owned(),
                        );
                    }
                    let _ = self.commit_security_options(&[("stop-service", "N")], false);
                    set_conservative_access_denied(false);
                    "/c sc start RustDesk".to_owned()
                }
                "UNINSTALL_ELEVATED" => {
                    if current_status.service_owned_by_dauverse != Some(true) {
                        return Err(
                            "SERVICE_NOT_REGISTERED_BY_DAUVERSE: No owned Windows Service to uninstall."
                                .to_owned(),
                        );
                    }
                    "/c sc stop RustDesk & sc delete RustDesk".to_owned()
                }
                _ => return Err(format!("UNSUPPORTED_SERVICE_ACTION: {action}")),
            };

            let launched = crate::platform::windows::run_uac("cmd.exe", &cmd_line)
                .map_err(|e| format!("SERVICE_UAC_ELEVATION_FAILED: {e}"))?;
            if !launched {
                return Err(
                    "SERVICE_UAC_CANCELLED_OR_DENIED: Administrator UAC prompt was declined or failed."
                        .to_owned(),
                );
            }

            for _ in 0..25 {
                std::thread::sleep(Duration::from_millis(300));
                let st = self.status();
                match norm_action.as_str() {
                    "INSTALL_AND_START_ELEVATED" | "START_ELEVATED" => {
                        if st.service_owned_by_dauverse == Some(true)
                            && st.service_state == ServiceRunState::Running
                        {
                            let mut g = self.state.lock().unwrap();
                            g.boss_service_install_approved = true;
                            g.pre_login_session_helper_enabled = true;
                            drop(g);
                            return Ok(self.status());
                        }
                    }
                    "UNINSTALL_ELEVATED" => {
                        if st.service_owned_by_dauverse.is_none() {
                            let mut g = self.state.lock().unwrap();
                            g.pre_login_session_helper_enabled = false;
                            drop(g);
                            return Ok(self.status());
                        }
                    }
                    _ => {}
                }
            }
            Ok(self.status())
        }

        #[cfg(not(all(target_os = "windows", not(test))))]
        {
            Err(
                "WINDOWS_SCM_REQUIRES_WINDOWS_HOST: Windows Service Control Manager (SCM) operations are only executable on a native Windows host."
                    .to_owned(),
            )
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LanInterfaceInfo {
    pub interface_name: String,
    pub friendly_name: String,
    pub ipv4: String,
    pub netmask: String,
    pub mac: Option<String>,
    pub is_default_route: bool,
}

pub fn format_connection_id_display(raw_id: &str) -> String {
    let trimmed = raw_id.trim();
    if trimmed.len() >= 6 && trimmed.chars().all(|c| c.is_ascii_digit()) {
        let chars: Vec<char> = trimmed.chars().collect();
        let mut out = String::with_capacity(trimmed.len() + 4);
        let first_group = if chars.len() % 3 == 0 { 3 } else { chars.len() % 3 };
        for (idx, ch) in chars.iter().enumerate() {
            if idx > 0 && idx >= first_group && (idx - first_group) % 3 == 0 {
                out.push(' ');
            }
            out.push(*ch);
        }
        out
    } else {
        trimmed.to_owned()
    }
}

pub fn enumerate_active_lan_interfaces() -> Vec<LanInterfaceInfo> {
    static CACHE: OnceLock<Mutex<Option<(Instant, Vec<LanInterfaceInfo>)>>> = OnceLock::new();
    let cache_lock = CACHE.get_or_init(|| Mutex::new(None));
    if let Ok(guard) = cache_lock.lock() {
        if let Some((ts, ref cached)) = *guard {
            if ts.elapsed() < Duration::from_secs(5) {
                return cached.clone();
            }
        }
    }

    let default_if_name = default_net::get_default_interface()
        .ok()
        .map(|iface| iface.name);
    let mut seen_ips = HashSet::new();
    let mut items = Vec::new();
    for iface in default_net::get_interfaces() {
        if iface.is_loopback() {
            continue;
        }
        let is_default = default_if_name.as_deref() == Some(iface.name.as_str());
        let friendly = iface
            .friendly_name
            .clone()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| iface.name.clone());
        let mac_str = iface.mac_addr.map(|m| m.address().to_ascii_uppercase());
        for v4 in &iface.ipv4 {
            if v4.addr.is_loopback() || v4.addr.is_unspecified() || v4.addr.is_link_local() {
                continue;
            }
            let ip_str = v4.addr.to_string();
            if !seen_ips.insert(ip_str.clone()) {
                continue;
            }
            items.push(LanInterfaceInfo {
                interface_name: iface.name.clone(),
                friendly_name: friendly.clone(),
                ipv4: ip_str,
                netmask: v4.netmask.to_string(),
                mac: mac_str.clone(),
                is_default_route: is_default,
            });
        }
    }
    items.sort_by(|a, b| {
        b.is_default_route
            .cmp(&a.is_default_route)
            .then_with(|| a.interface_name.cmp(&b.interface_name))
            .then_with(|| a.ipv4.cmp(&b.ipv4))
    });
    if let Ok(mut guard) = cache_lock.lock() {
        *guard = Some((Instant::now(), items.clone()));
    }
    items
}

pub fn collect_connection_identity_snapshot(
    public_ip: Option<String>,
    public_ip_status: &str,
) -> serde_json::Value {
    let raw_id = Config::get_id();
    let formatted_id = format_connection_id_display(&raw_id);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let synced_temp_pw = crate::ui_interface::temporary_password();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let synced_temp_pw = String::new();
    let temp_pw = if !synced_temp_pw.trim().is_empty() {
        synced_temp_pw
    } else {
        hbb_common::password_security::temporary_password()
    };

    let lan_interfaces = enumerate_active_lan_interfaces();
    let lan_ips: Vec<String> = lan_interfaces.iter().map(|i| i.ipv4.clone()).collect();

    let service_stopped =
        hbb_common::config::option2bool("stop-service", &Config::get_option("stop-service"));
    let direct_ip_enabled = hbb_common::config::option2bool(
        hbb_common::config::keys::OPTION_DIRECT_SERVER,
        &Config::get_option(hbb_common::config::keys::OPTION_DIRECT_SERVER),
    );
    let direct_port = Config::get_option("direct-access-port")
        .trim()
        .parse::<u16>()
        .unwrap_or(21118);

    #[cfg(all(feature = "flutter", not(any(target_os = "android", target_os = "ios"))))]
    let (ui_status_num, ui_video_conns) = {
        let st = crate::ui_interface::get_connect_status();
        (st.status_num, st.video_conn_count)
    };
    #[cfg(not(all(feature = "flutter", not(any(target_os = "android", target_os = "ios")))))]
    let (ui_status_num, ui_video_conns) = {
        let raw = hbb_common::config::get_online_state();
        (if raw > 0 { 1 } else if raw < 0 { -1 } else { 0 }, 0usize)
    };

    let engine_conns = active_live_engine_connection_count().max(ui_video_conns);
    let effective_online_num = if service_stopped || is_conservative_access_denied() {
        -1
    } else if ui_status_num != 0 {
        ui_status_num
    } else {
        let raw = hbb_common::config::get_online_state();
        if raw > 0 {
            1
        } else if raw < 0 {
            -1
        } else {
            0
        }
    };

    let connection_status = if engine_conns > 0 {
        "CONNECTED"
    } else if effective_online_num < 0 {
        "OFFLINE"
    } else if effective_online_num > 0 {
        "ONLINE"
    } else {
        "CONNECTING"
    };

    serde_json::json!({
        "connection_id": raw_id,
        "formatted_id": formatted_id,
        "temporary_password": temp_pw,
        "permanent_password_configured": Config::has_permanent_password(),
        "lan_interfaces": lan_interfaces,
        "lan_ips": lan_ips,
        "public_ip": public_ip,
        "public_ip_status": public_ip_status,
        "direct_ip_access_enabled": direct_ip_enabled,
        "direct_ip_port": direct_port,
        "rendezvous_server": Config::get_rendezvous_server(),
        "using_public_rendezvous": crate::using_public_server(),
        "service_stopped": service_stopped,
        "active_sessions_count": engine_conns,
        "online_state_code": effective_online_num,
        "connection_status": connection_status,
    })
}

#[cfg(test)]
pub(crate) fn verify_post_revoke_os_truth(
    actual_approve_mode: &str,
    after_owned_by_dauverse: Option<bool>,
    after_service_state: ServiceRunState,
    after_run_key_present: bool,
    os_action_error: Option<String>,
) -> Result<(), String> {
    verify_post_revoke_os_truth_full(
        actual_approve_mode,
        after_owned_by_dauverse,
        after_service_state,
        after_run_key_present,
        0,
        os_action_error,
    )
}

pub(crate) fn verify_post_revoke_os_truth_full(
    actual_approve_mode: &str,
    after_owned_by_dauverse: Option<bool>,
    after_service_state: ServiceRunState,
    after_run_key_present: bool,
    remaining_live_connections: usize,
    os_action_error: Option<String>,
) -> Result<(), String> {
    if let Some(err) = os_action_error {
        return Err(err);
    }
    if remaining_live_connections > 0 {
        return Err(format!(
            "SERVICE_REVOKE_LIVE_CONNECTIONS_STILL_ACTIVE: {remaining_live_connections} connection(s) remain"
        ));
    }
    if actual_approve_mode != "click" {
        return Err(format!(
            "SERVICE_REVOKE_CONFIG_VERIFY_FAILED: expected durable approve-mode='click', got '{actual_approve_mode}'"
        ));
    }
    if after_run_key_present {
        return Err("SERVICE_REVOKE_RUN_KEY_STILL_PRESENT_AFTER_DELETE".to_owned());
    }
    if after_owned_by_dauverse == Some(true) && after_service_state != ServiceRunState::Stopped {
        return Err(format!(
            "SERVICE_REVOKE_OWNED_SCM_SERVICE_NOT_STOPPED: state={after_service_state:?}"
        ));
    }
    Ok(())
}

#[cfg(all(target_os = "windows", not(test)))]
fn stop_owned_windows_scm_service(service_name: &str) -> Result<(), String> {
    use windows_service::{
        service::{ServiceAccess, ServiceState},
        service_manager::{ServiceManager, ServiceManagerAccess},
    };

    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
        .map_err(|e| format!("SERVICE_REVOKE_SCM_CONNECT_FAILED: {e}"))?;
    let service = manager
        .open_service(service_name, ServiceAccess::STOP | ServiceAccess::QUERY_STATUS)
        .map_err(|e| format!("SERVICE_REVOKE_SCM_OPEN_FAILED: {e}"))?;

    let initial = service
        .query_status()
        .map_err(|e| format!("SERVICE_REVOKE_SCM_QUERY_FAILED: {e}"))?;
    if initial.current_state == ServiceState::Stopped {
        return Ok(());
    }
    if initial.current_state != ServiceState::StopPending {
        if let Err(stop_err) = service.stop() {
            let post = service
                .query_status()
                .map_err(|e| format!("SERVICE_REVOKE_SCM_STOP_FAILED: {stop_err}; query={e}"))?;
            if post.current_state != ServiceState::Stopped
                && post.current_state != ServiceState::StopPending
            {
                return Err(format!("SERVICE_REVOKE_SCM_STOP_FAILED: {stop_err}"));
            }
        }
    }

    for _ in 0..25 {
        let st = service
            .query_status()
            .map_err(|e| format!("SERVICE_REVOKE_SCM_POLL_FAILED: {e}"))?;
        if st.current_state == ServiceState::Stopped {
            return Ok(());
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    Err("SERVICE_REVOKE_SCM_STOP_TIMEOUT: owned service did not reach Stopped within 5s".to_owned())
}

#[cfg(target_os = "windows")]
fn query_windows_service_and_autorun_compat() -> (
    ServiceRunState,
    Option<bool>,
    bool,
    Option<String>,
    bool,
) {
    query_windows_service_ownership_and_run_state()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    struct ScopedPinnedAppName {
        prev_app_name: String,
        cfg_dir: Option<PathBuf>,
    }

    impl ScopedPinnedAppName {
        fn enter(prefix: &str) -> Self {
            let prev_app_name = hbb_common::config::APP_NAME.read().unwrap().clone();
            let unique_name = format!(
                "{}_{}",
                prefix,
                uuid::Uuid::new_v4().simple()
            );
            *hbb_common::config::APP_NAME.write().unwrap() = unique_name;
            set_conservative_access_denied(false);
            let cfg_file = Config2::file();
            let cfg_dir = cfg_file.parent().map(Path::to_path_buf);
            if let Some(ref dir) = cfg_dir {
                std::fs::create_dir_all(dir).unwrap();
            }
            Self {
                prev_app_name,
                cfg_dir,
            }
        }
    }

    impl Drop for ScopedPinnedAppName {
        fn drop(&mut self) {
            if let Some(ref dir) = self.cfg_dir {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700));
                    if let Ok(entries) = std::fs::read_dir(dir) {
                        for entry in entries.flatten() {
                            let _ = std::fs::set_permissions(
                                entry.path(),
                                std::fs::Permissions::from_mode(0o600),
                            );
                        }
                    }
                }
                let _ = std::fs::remove_dir_all(dir);
            }
            *hbb_common::config::APP_NAME.write().unwrap() = self.prev_app_name.clone();
            set_conservative_access_denied(false);
        }
    }

    #[test]
    fn f03_f08_verifies_service_ownership_os_truth_and_refuses_synthetic_revoke_success() {
        let _test_guard = GlobalTestSerialToken::acquire_sync();
        let _scoped_app = ScopedPinnedAppName::enter("DvSvcTruth");

        assert!(is_service_image_path_owned_by_install_dir(
            "\"C:\\Program Files\\DAUVERSE Remote Desktop\\rustdesk.exe\" --service",
            "C:\\Program Files\\DAUVERSE Remote Desktop"
        ));
        assert!(!is_service_image_path_owned_by_install_dir(
            "\"C:\\Program Files\\RustDesk\\rustdesk.exe\" --service",
            "C:\\Program Files\\DAUVERSE Remote Desktop"
        ));
        assert!(!is_service_image_path_owned_by_install_dir(
            "\"C:\\Program Files\\DAUVERSE Remote Desktop Evil\\rustdesk.exe\" --service",
            "C:\\Program Files\\DAUVERSE Remote Desktop"
        ));

        let ctrl = ServiceController::new();
        assert_eq!(ctrl.status().scm_service_name, "RustDesk");
        assert!(ctrl.configure_unattended(true, false).is_err());
        assert!(ctrl.set_auto_start(true, false).is_err());

        let st = ctrl.configure_unattended(true, true).unwrap();
        assert!(st.desired_unattended_enabled);
        assert!(st.unattended_access_enabled);
        assert!(st.config_persistence_healthy);
        assert!(st.system_tray_indicator_visible);
        assert!(st.defender_av_untouched);
        assert!(st.no_hidden_persistence);

        // Fresh controller observes persisted unattended state truthfully from durable Config2::file()
        let restarted_ctrl = ServiceController::new();
        assert!(restarted_ctrl.status().unattended_access_enabled);

        let _ = ctrl.set_auto_start(true, true).unwrap();
        let revoked = ctrl.revoke_all_access_immediately().unwrap();
        assert!(!revoked.unattended_access_enabled);
        assert!(!revoked.auto_start_with_windows);
        assert!(revoked.conservative_access_deny_latched);
        assert_eq!(
            hbb_common::config::Config::get_option("approve-mode"),
            "click"
        );
        let (disk_cfg2, disk_doc) = read_durable_config2_at(&Config2::file()).unwrap();
        assert!(disk_doc.is_some());
        assert_eq!(effective_option_from_config2(&disk_cfg2, "approve-mode"), "click");
        assert_eq!(effective_option_from_config2(&disk_cfg2, "enable-keyboard"), "N");
        assert_eq!(effective_option_from_config2(&disk_cfg2, "enable-clipboard"), "N");
        assert_eq!(effective_option_from_config2(&disk_cfg2, "enable-file-transfer"), "N");

        // F08 Negative 1: Owned SCM service still Running or Pending/Degraded after stop attempt MUST fail closed
        let err_running = verify_post_revoke_os_truth(
            "click",
            Some(true),
            ServiceRunState::Running,
            false,
            None,
        )
        .unwrap_err();
        assert!(err_running.starts_with("SERVICE_REVOKE_OWNED_SCM_SERVICE_NOT_STOPPED"));

        let err_pending = verify_post_revoke_os_truth(
            "click",
            Some(true),
            ServiceRunState::DegradedRecovering,
            false,
            None,
        )
        .unwrap_err();
        assert!(err_pending.starts_with("SERVICE_REVOKE_OWNED_SCM_SERVICE_NOT_STOPPED"));

        // F08 Negative 2: Access denied stopping SCM service MUST fail closed
        let err_denied = verify_post_revoke_os_truth(
            "click",
            Some(true),
            ServiceRunState::Running,
            false,
            Some("SERVICE_REVOKE_SCM_OPEN_FAILED: Access is denied".to_owned()),
        )
        .unwrap_err();
        assert!(err_denied.contains("SERVICE_REVOKE_SCM_OPEN_FAILED"));

        // F08 Negative 3: HKCU Run key still present after delete MUST fail closed
        let err_run = verify_post_revoke_os_truth(
            "click",
            None,
            ServiceRunState::NotInstalledPortableMode,
            true,
            None,
        )
        .unwrap_err();
        assert_eq!(err_run, "SERVICE_REVOKE_RUN_KEY_STILL_PRESENT_AFTER_DELETE");

        // F08 Negative 4: Live engine connection still active MUST fail closed
        let err_live = verify_post_revoke_os_truth_full(
            "click",
            None,
            ServiceRunState::NotInstalledPortableMode,
            false,
            1,
            None,
        )
        .unwrap_err();
        assert!(err_live.starts_with("SERVICE_REVOKE_LIVE_CONNECTIONS_STILL_ACTIVE"));

        // F03 Positive: External RustDesk service (owned == Some(false)) is left untouched and reported as portable/not-owned
        assert!(verify_post_revoke_os_truth(
            "click",
            Some(false),
            ServiceRunState::NotInstalledPortableMode,
            false,
            None,
        )
        .is_ok());
    }

    #[test]
    fn ft010_b03_live_engine_connection_revoke_cuts_capabilities_disconnects_and_fails_on_timeout() {
        let _test_guard = GlobalTestSerialToken::acquire_sync();
        let _scoped_app = ScopedPinnedAppName::enter("DvB03Revoke");
        assert_eq!(active_live_engine_connection_count(), 0);

        // 1. Establish two live authorized engine sessions:
        //    - Portable desktop session (keyboard + clipboard + file transfer)
        //    - Active port-forward session
        let (tx_desktop, mut rx_desktop) =
            hbb_common::tokio::sync::mpsc::unbounded_channel::<crate::ipc::Data>();
        let (tx_pf, mut rx_pf) =
            hbb_common::tokio::sync::mpsc::unbounded_channel::<crate::ipc::Data>();

        let guard_desktop = register_live_engine_connection(501, tx_desktop);
        let guard_pf = register_live_engine_connection(502, tx_pf);
        let desktop_revoked_flag = guard_desktop.revoked_flag();
        let pf_revoked_flag = guard_pf.revoked_flag();
        assert_eq!(active_live_engine_connection_count(), 2);
        assert!(!guard_desktop.is_revoked());
        assert!(!guard_pf.is_revoked());

        let desktop_worker = std::thread::spawn(move || {
            let mut saw_perm_disable = HashSet::new();
            let mut saw_close = false;
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline {
                if let Ok(msg) = rx_desktop.try_recv() {
                    match msg {
                        crate::ipc::Data::SwitchPermission { name, enabled } => {
                            assert!(!enabled);
                            saw_perm_disable.insert(name);
                        }
                        crate::ipc::Data::Close => {
                            saw_close = true;
                            break;
                        }
                        _ => {}
                    }
                } else {
                    std::thread::sleep(Duration::from_millis(5));
                }
            }
            assert!(saw_close, "desktop connection must receive Data::Close");
            assert!(saw_perm_disable.contains("keyboard"));
            assert!(saw_perm_disable.contains("clipboard"));
            assert!(saw_perm_disable.contains("file"));
            assert!(guard_desktop.is_revoked());
            drop(guard_desktop);
        });

        let pf_worker = std::thread::spawn(move || {
            let mut saw_close = false;
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline {
                if let Ok(msg) = rx_pf.try_recv() {
                    if matches!(msg, crate::ipc::Data::Close) {
                        saw_close = true;
                        break;
                    }
                } else {
                    std::thread::sleep(Duration::from_millis(5));
                }
            }
            assert!(saw_close, "port-forward tunnel must receive Data::Close");
            assert!(guard_pf.is_revoked());
            drop(guard_pf);
        });

        let ctrl = ServiceController::new();
        let post_revoke = ctrl
            .revoke_all_access_immediately()
            .expect("revoke must succeed after both live connections acknowledge disconnect");
        desktop_worker.join().unwrap();
        pf_worker.join().unwrap();

        assert_eq!(active_live_engine_connection_count(), 0);
        assert_eq!(post_revoke.active_engine_connections_count, 0);
        assert!(desktop_revoked_flag.load(Ordering::SeqCst));
        assert!(pf_revoked_flag.load(Ordering::SeqCst));
        assert!(is_conservative_access_denied());

        // 2. Subsequent/in-flight capability boundary check while conservative latch is active:
        //    even a newly registered connection starts immediately revoked until Boss re-authorizes!
        let (tx_late, _rx_late) =
            hbb_common::tokio::sync::mpsc::unbounded_channel::<crate::ipc::Data>();
        let guard_late = register_live_engine_connection(503, tx_late);
        assert!(guard_late.is_revoked());
        drop(guard_late);

        // 3. Negative timeout case: hung connection refuses to terminate -> MUST return Err
        //    while keeping conservative access denial active!
        set_conservative_access_denied(false);
        let (tx_hung, _rx_hung) =
            hbb_common::tokio::sync::mpsc::unbounded_channel::<crate::ipc::Data>();
        let hung_guard = register_live_engine_connection(504, tx_hung);
        let timeout_err = revoke_all_local_engine_connections(Duration::from_millis(80))
            .expect_err("hung live connection must fail revoke with timeout");
        assert!(timeout_err.contains("ENGINE_REVOKE_DISCONNECT_TIMEOUT"));
        assert!(hung_guard.is_revoked());
        assert!(is_conservative_access_denied());
        drop(hung_guard);
        assert_eq!(active_live_engine_connection_count(), 0);

        // 4. Cross-process local `--server` IPC ACK and failure/timeout verification
        #[cfg(unix)]
        {
            let sock_dir =
                std::env::temp_dir().join(format!("dv_ipc_rev_{}", uuid::Uuid::new_v4().simple()));
            std::fs::create_dir_all(&sock_dir).unwrap();
            let sock_ok = sock_dir.join("server_ok.sock");
            let listener_ok = std::os::unix::net::UnixListener::bind(&sock_ok).unwrap();
            let server_ok_handle = std::thread::spawn(move || {
                let (mut stream, _) = listener_ok.accept().unwrap();
                let mut codec = BytesCodec::new();
                let mut buf = BytesMut::new();
                let mut tmp = [0u8; 512];
                loop {
                    let n = stream.read(&mut tmp).unwrap();
                    buf.extend_from_slice(&tmp[..n]);
                    if let Some(frame) = codec.decode(&mut buf).unwrap() {
                        let req: crate::ipc::Data = serde_json::from_slice(&frame).unwrap();
                        assert!(matches!(req, crate::ipc::Data::DauverseEmergencyRevoke(None)));
                        let resp_vec = serde_json::to_vec(
                            &crate::ipc::Data::DauverseEmergencyRevoke(Some(Ok(2))),
                        )
                        .unwrap();
                        let mut out = BytesMut::new();
                        codec.encode(Bytes::from(resp_vec), &mut out).unwrap();
                        stream.write_all(&out).unwrap();
                        break;
                    }
                }
            });
            let ack = request_local_server_ipc_revoke_sync(
                sock_ok.to_str().unwrap(),
                Duration::from_secs(1),
            )
            .unwrap();
            assert_eq!(ack, Some(2));
            server_ok_handle.join().unwrap();

            // Hung IPC server -> MUST fail closed on read timeout
            let sock_hang = sock_dir.join("server_hang.sock");
            let listener_hang = std::os::unix::net::UnixListener::bind(&sock_hang).unwrap();
            let hang_handle = std::thread::spawn(move || {
                let (_stream, _) = listener_hang.accept().unwrap();
                std::thread::sleep(Duration::from_millis(250));
            });
            let hang_err = request_local_server_ipc_revoke_sync(
                sock_hang.to_str().unwrap(),
                Duration::from_millis(80),
            )
            .expect_err("unacknowledged IPC server must fail closed");
            assert!(
                hang_err.contains("IPC_REVOKE_READ_FAILED")
                    || hang_err.contains("IPC_REVOKE_EOF_BEFORE_ACK")
            );
            hang_handle.join().unwrap();

            // Nonexistent IPC socket -> portable no-daemon case returns Ok(None)
            assert_eq!(
                request_local_server_ipc_revoke_sync(
                    sock_dir.join("absent.sock").to_str().unwrap(),
                    Duration::from_millis(80)
                )
                .unwrap(),
                None
            );
            let _ = std::fs::remove_dir_all(&sock_dir);
        }
    }

    #[test]
    fn ft010_b04_durable_config2_persistence_fault_injection_and_credential_preservation() {
        let _test_guard = GlobalTestSerialToken::acquire_sync();
        let _scoped_app = ScopedPinnedAppName::enter("DvB04Durable");
        let cfg2_path = Config2::file();

        // 1. Seed actual pinned Config2::file() with encrypted credentials + trusted devices + socks
        let seeded_toml = r#"rendezvous_server = "hbbs.dauverse.internal:21116"
nat_type = 1
serial = 7
unlock_pin = "00encrypted_unlock_pin_do_not_lose"
trusted_devices = "legacy_trusted_blob_v1"
trusted_devices_v2 = "v2_trusted_grants_blob"

[socks]
proxy = "127.0.0.1:1080"
username = "boss_proxy"
password = "00encrypted_socks_password_do_not_lose"

[options]
approve-mode = "password"
verification-method = "use-both-passwords"
"#;
        std::fs::write(&cfg2_path, seeded_toml).unwrap();

        let ctrl = ServiceController::new();
        assert!(ctrl.status().unattended_access_enabled);

        // Durable revoke commits atomically to Config2::file() while preserving ALL credentials!
        let revoked_st = ctrl.revoke_all_access_immediately().unwrap();
        assert!(!revoked_st.unattended_access_enabled);
        assert!(revoked_st.config_persistence_healthy);

        // Verify via fresh disk reload (simulating full process restart!) AND pinned Config2::get_for_sync()
        let (reloaded_cfg2, reloaded_doc_opt) = read_durable_config2_at(&cfg2_path).unwrap();
        let reloaded_doc = reloaded_doc_opt.unwrap();
        assert_eq!(
            effective_option_from_config2(&reloaded_cfg2, "approve-mode"),
            "click"
        );
        assert_eq!(
            effective_option_from_config2(&reloaded_cfg2, "enable-keyboard"),
            "N"
        );
        assert_eq!(
            effective_option_from_config2(&reloaded_cfg2, "enable-clipboard"),
            "N"
        );
        assert_eq!(
            effective_option_from_config2(&reloaded_cfg2, "enable-file-transfer"),
            "N"
        );
        assert_eq!(
            reloaded_doc.get("unlock_pin").and_then(|v| v.as_str()),
            Some("00encrypted_unlock_pin_do_not_lose")
        );
        assert_eq!(
            reloaded_doc.get("trusted_devices").and_then(|v| v.as_str()),
            Some("legacy_trusted_blob_v1")
        );
        assert_eq!(
            reloaded_doc
                .get("trusted_devices_v2")
                .and_then(|v| v.as_str()),
            Some("v2_trusted_grants_blob")
        );
        assert_eq!(
            reloaded_doc
                .get("socks")
                .and_then(|s| s.get("password"))
                .and_then(|v| v.as_str()),
            Some("00encrypted_socks_password_do_not_lose")
        );
        #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
        {
            let synced = Config2::get_for_sync().unwrap();
            assert_eq!(effective_option_from_config2(&synced, "approve-mode"), "click");
        }

        // 2. Fault Injection A: Corrupt Config2 file / read-for-store error
        //    Must return Err, preserve raw file bytes (never wipe credentials!), and enforce conservative denial!
        set_conservative_access_denied(false);
        let corrupt_bytes =
            b"unlock_pin = \"00must_survive_corrupt_parse\"\ntrusted_devices_v2 = \"keep_v2\"\n[options\nbroken ===";
        std::fs::write(&cfg2_path, corrupt_bytes).unwrap();

        let enable_err = ctrl
            .configure_unattended(true, true)
            .expect_err("corrupt Config2 must reject unattended enable");
        assert!(enable_err.contains("CONFIG2_DURABLE_PARSE_FAILED"));
        assert_eq!(std::fs::read(&cfg2_path).unwrap(), corrupt_bytes);
        assert!(!ctrl.status().unattended_access_enabled);
        assert!(!ctrl.status().config_persistence_healthy);

        let revoke_corrupt_err = ctrl
            .revoke_all_access_immediately()
            .expect_err("corrupt Config2 must fail revoke readback instead of claiming success");
        assert!(revoke_corrupt_err.contains("CONFIG2_DURABLE_PARSE_FAILED"));
        assert_eq!(std::fs::read(&cfg2_path).unwrap(), corrupt_bytes);
        assert!(is_conservative_access_denied());
        assert!(!ctrl.status().unattended_access_enabled);

        // 3. Fault Injection B: Non-string trusted_devices_v2 field MUST fail closed (never drop V2 grants silently!)
        set_conservative_access_denied(false);
        let bad_td_v2 =
            b"unlock_pin = \"00keep\"\ntrusted_devices_v2 = 99999\n[options]\napprove-mode = \"password\"\n";
        std::fs::write(&cfg2_path, bad_td_v2).unwrap();
        let td_err = ctrl
            .revoke_all_access_immediately()
            .expect_err("malformed trusted_devices_v2 must fail closed without dropping grants");
        assert!(td_err.contains("CONFIG2_CORRUPT_TRUSTED_DEVICES_V2_FIELD"));
        assert_eq!(std::fs::read(&cfg2_path).unwrap(), bad_td_v2);
        assert!(is_conservative_access_denied());

        // 4. Fault Injection C (Unix): Access-denied (0o000 file) and Atomic-commit failure (0o500 parent dir)
        #[cfg(unix)]
        if unsafe { hbb_common::libc::geteuid() } != 0 {
            use std::os::unix::fs::PermissionsExt;
            set_conservative_access_denied(false);
            std::fs::write(&cfg2_path, seeded_toml).unwrap();

            // Access-denied on Config2::file()
            std::fs::set_permissions(&cfg2_path, std::fs::Permissions::from_mode(0o000)).unwrap();
            let acl_err = ctrl
                .revoke_all_access_immediately()
                .expect_err("unreadable Config2 must fail closed");
            assert!(acl_err.contains("CONFIG2_DURABLE_OPEN_FAILED"));
            assert!(is_conservative_access_denied());
            assert!(!ctrl.status().unattended_access_enabled);
            std::fs::set_permissions(&cfg2_path, std::fs::Permissions::from_mode(0o600)).unwrap();
            assert_eq!(std::fs::read_to_string(&cfg2_path).unwrap(), seeded_toml);

            // Atomic-commit failure (read-only parent directory 0o500 blocks temp file & rename)
            let parent_dir = cfg2_path.parent().unwrap();
            set_conservative_access_denied(false);
            std::fs::set_permissions(parent_dir, std::fs::Permissions::from_mode(0o500)).unwrap();
            let commit_err = ctrl
                .revoke_all_access_immediately()
                .expect_err("read-only config dir must fail atomic commit");
            assert!(commit_err.contains("CONFIG2_ATOMIC_COMMIT_FAILED"));
            assert!(is_conservative_access_denied());
            assert!(!ctrl.status().unattended_access_enabled);
            std::fs::set_permissions(parent_dir, std::fs::Permissions::from_mode(0o700)).unwrap();
            // Original file with credentials was never truncated or corrupted!
            assert_eq!(std::fs::read_to_string(&cfg2_path).unwrap(), seeded_toml);
        }

        // 5. Fault Injection D (Unix): Real kernel mid-write EFBIG / disk-quota exhaustion via RLIMIT_FSIZE in child process
        #[cfg(unix)]
        {
            let exe = std::env::current_exe().unwrap();
            let out = std::process::Command::new(exe)
                .arg("--exact")
                .arg("dauverse::service_ctrl::tests::ft010_b04_rlimit_fsize_mid_write_subprocess_entry")
                .arg("--nocapture")
                .env("DAUVERSE_RUN_RLIMIT_FSIZE_CHILD", "1")
                .output()
                .unwrap();
            assert!(
                out.status.success(),
                "RLIMIT_FSIZE child failed:\nstdout={}\nstderr={}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn ft010_b04_rlimit_fsize_mid_write_subprocess_entry() {
        if std::env::var("DAUVERSE_RUN_RLIMIT_FSIZE_CHILD").as_deref() != Ok("1") {
            return;
        }
        let _scoped_app = ScopedPinnedAppName::enter("DvB04Fsize");
        let cfg_path = Config2::file();
        let dir = cfg_path.parent().unwrap().to_path_buf();
        std::fs::create_dir_all(&dir).unwrap();
        let original = concat!(
            "unlock_pin = \"00encrypted_pin_survives_disk_full_write_error\"\n",
            "trusted_devices_v2 = \"v2_grants_survive_disk_full\"\n",
            "[options]\n",
            "approve-mode = \"click\"\n",
        );
        std::fs::write(&cfg_path, original).unwrap();
        Config::set_option("approve-mode".to_owned(), "click".to_owned());
        std::fs::write(&cfg_path, original).unwrap();
        assert!(original.len() > 96);

        let ctrl = ServiceController::new();

        // Enforce 32-byte kernel file-size limit (RLIMIT_FSIZE) and ignore SIGXFSZ so write() returns EFBIG
        unsafe {
            hbb_common::libc::signal(hbb_common::libc::SIGXFSZ, hbb_common::libc::SIG_IGN);
            let lim = hbb_common::libc::rlimit {
                rlim_cur: 32,
                rlim_max: 65536,
            };
            assert_eq!(
                hbb_common::libc::setrlimit(hbb_common::libc::RLIMIT_FSIZE, &lim),
                0
            );
        }

        // 1. configure_unattended(true, true) against live Config2::file() MUST fail without mutating in-memory CONFIG2
        let unatt_err = ctrl
            .configure_unattended(true, true)
            .expect_err("mid-write EFBIG on Config2::file() must fail configure_unattended");
        assert!(unatt_err.contains("CONFIG2_ATOMIC_COMMIT_FAILED"));
        assert_eq!(Config::get_option("approve-mode"), "click");

        // 2. revoke_all_access_immediately against live Config2::file() MUST fail closed and latch conservative denial
        let err = ctrl
            .revoke_all_access_immediately()
            .expect_err("mid-write EFBIG/disk-full must fail atomic Config2 revoke commit");
        assert!(err.contains("CONFIG2_ATOMIC_COMMIT_FAILED"));
        assert!(is_conservative_access_denied());

        // Restore soft limit before ScopedPinnedAppName drops and verify original file & credentials remained 100% intact
        unsafe {
            let lim = hbb_common::libc::rlimit {
                rlim_cur: 65536,
                rlim_max: 65536,
            };
            let _ = hbb_common::libc::setrlimit(hbb_common::libc::RLIMIT_FSIZE, &lim);
        }
        assert_eq!(std::fs::read_to_string(&cfg_path).unwrap(), original);
        let remaining_files: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .filter(|e| {
                e.file_name()
                    .to_string_lossy()
                    .contains("RustDesk2.toml.tmp")
            })
            .collect();
        assert!(remaining_files.is_empty());
    }
}

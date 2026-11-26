use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
};

const HMAC_BLOCK_SIZE: usize = 64;

pub fn sha256_bytes(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let out = hasher.finalize();
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&out);
    arr
}

pub fn sha256_hex(data: &[u8]) -> String {
    hex::encode(sha256_bytes(data))
}

pub fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = File::open(path).map_err(|e| format!("failed to open file: {e}"))?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file
            .read(&mut buf)
            .map_err(|e| format!("failed reading file: {e}"))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

pub fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; 32] {
    let mut key_block = [0u8; HMAC_BLOCK_SIZE];
    if key.len() > HMAC_BLOCK_SIZE {
        let hashed = sha256_bytes(key);
        key_block[..32].copy_from_slice(&hashed);
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }

    let mut ipad = [0x36u8; HMAC_BLOCK_SIZE];
    let mut opad = [0x5cu8; HMAC_BLOCK_SIZE];
    for i in 0..HMAC_BLOCK_SIZE {
        ipad[i] ^= key_block[i];
        opad[i] ^= key_block[i];
    }

    let mut inner = Sha256::new();
    inner.update(ipad);
    inner.update(message);
    let inner_digest = inner.finalize();

    let mut outer = Sha256::new();
    outer.update(opad);
    outer.update(inner_digest);
    let outer_digest = outer.finalize();

    let mut out = [0u8; 32];
    out.copy_from_slice(&outer_digest);
    out
}

pub fn hmac_sha256_hex(key: &[u8], message: &[u8]) -> String {
    hex::encode(hmac_sha256(key, message))
}

pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (&x, &y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

pub fn verify_hmac_sha256_hex(key: &[u8], message: &[u8], expected_hex: &str) -> bool {
    let Ok(expected_bytes) = hex::decode(expected_hex.trim()) else {
        return false;
    };
    let computed = hmac_sha256(key, message);
    constant_time_eq(&computed, &expected_bytes)
}

pub fn generate_nonce_hex() -> String {
    let u1 = uuid::Uuid::new_v4();
    let u2 = uuid::Uuid::new_v4();
    let mut combined = [0u8; 32];
    combined[..16].copy_from_slice(u1.as_bytes());
    combined[16..].copy_from_slice(u2.as_bytes());
    hex::encode(combined)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VaultBackend {
    WindowsDpapi,
    UnixAuthenticatedSealedFile,
}

impl VaultBackend {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::WindowsDpapi => "WINDOWS_DPAPI",
            Self::UnixAuthenticatedSealedFile => "UNIX_SEALED_0600_ENCRYPT_THEN_MAC",
        }
    }
}

pub fn active_vault_backend() -> VaultBackend {
    #[cfg(windows)]
    {
        VaultBackend::WindowsDpapi
    }
    #[cfg(not(windows))]
    {
        VaultBackend::UnixAuthenticatedSealedFile
    }
}

#[cfg(windows)]
pub fn protect_secret_bytes(plaintext: &[u8], entropy: &[u8]) -> Result<Vec<u8>, String> {
    use std::ptr::null_mut;
    use winapi::um::{
        dpapi::{CryptProtectData, CRYPTPROTECT_UI_FORBIDDEN},
        winbase::LocalFree,
        wincrypt::DATA_BLOB,
    };

    let mut in_buf = plaintext.to_vec();
    let mut ent_buf = entropy.to_vec();
    let mut in_blob = DATA_BLOB {
        cbData: in_buf.len() as u32,
        pbData: if in_buf.is_empty() {
            null_mut()
        } else {
            in_buf.as_mut_ptr()
        },
    };
    let mut ent_blob = DATA_BLOB {
        cbData: ent_buf.len() as u32,
        pbData: if ent_buf.is_empty() {
            null_mut()
        } else {
            ent_buf.as_mut_ptr()
        },
    };
    let mut out_blob = DATA_BLOB {
        cbData: 0,
        pbData: null_mut(),
    };

    let ok = unsafe {
        CryptProtectData(
            &mut in_blob,
            null_mut(),
            if entropy.is_empty() {
                null_mut()
            } else {
                &mut ent_blob
            },
            null_mut(),
            null_mut(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut out_blob,
        )
    };
    if ok == 0 {
        return Err("DPAPI CryptProtectData failed".to_owned());
    }
    let out = unsafe {
        let slice = std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize);
        let vec = slice.to_vec();
        LocalFree(out_blob.pbData as *mut _);
        vec
    };
    Ok(out)
}

#[cfg(windows)]
pub fn unprotect_secret_bytes(ciphertext: &[u8], entropy: &[u8]) -> Result<Vec<u8>, String> {
    use std::ptr::null_mut;
    use winapi::um::{
        dpapi::{CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN},
        winbase::LocalFree,
        wincrypt::DATA_BLOB,
    };

    let mut in_buf = ciphertext.to_vec();
    let mut ent_buf = entropy.to_vec();
    let mut in_blob = DATA_BLOB {
        cbData: in_buf.len() as u32,
        pbData: if in_buf.is_empty() {
            null_mut()
        } else {
            in_buf.as_mut_ptr()
        },
    };
    let mut ent_blob = DATA_BLOB {
        cbData: ent_buf.len() as u32,
        pbData: if ent_buf.is_empty() {
            null_mut()
        } else {
            ent_buf.as_mut_ptr()
        },
    };
    let mut out_blob = DATA_BLOB {
        cbData: 0,
        pbData: null_mut(),
    };

    let ok = unsafe {
        CryptUnprotectData(
            &mut in_blob,
            null_mut(),
            if entropy.is_empty() {
                null_mut()
            } else {
                &mut ent_blob
            },
            null_mut(),
            null_mut(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut out_blob,
        )
    };
    if ok == 0 {
        return Err("DPAPI CryptUnprotectData failed or tampered blob".to_owned());
    }
    let out = unsafe {
        let slice = std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize);
        let vec = slice.to_vec();
        LocalFree(out_blob.pbData as *mut _);
        vec
    };
    Ok(out)
}

#[cfg(not(windows))]
fn derive_unix_machine_key_v2(salt: &[u8; 16], entropy: &[u8]) -> [u8; 32] {
    let machine_id = fs::read_to_string("/etc/machine-id")
        .or_else(|_| fs::read_to_string("/var/lib/dbus/machine-id"))
        .unwrap_or_else(|_| "dauverse-linux-local-vault-v2".to_owned());
    let uid_str = std::env::var("USER").unwrap_or_else(|_| "antigravity".to_owned());
    let mut password_mat = Vec::with_capacity(machine_id.len() + uid_str.len() + entropy.len() + 32);
    password_mat.extend_from_slice(b"DAUVERSE_SEAL_KEY_V2:");
    password_mat.extend_from_slice(machine_id.trim().as_bytes());
    password_mat.push(b':');
    password_mat.extend_from_slice(uid_str.as_bytes());
    password_mat.push(b':');
    password_mat.extend_from_slice(entropy);

    // PBKDF2-HMAC-SHA256 single-block (32-byte dkLen, 10,000 iterations)
    let mut salt_block = [0u8; 20];
    salt_block[..16].copy_from_slice(salt);
    salt_block[16..20].copy_from_slice(&1u32.to_be_bytes());
    let mut u = hmac_sha256(&password_mat, &salt_block);
    let mut dk = u;
    for _ in 1..10_000 {
        u = hmac_sha256(&password_mat, &u);
        for (d, x) in dk.iter_mut().zip(u.iter()) {
            *d ^= *x;
        }
    }
    dk
}

#[cfg(not(windows))]
fn keystream_xor(enc_key: &[u8; 32], nonce: &[u8; 16], input: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(input.len());
    let mut counter = 0u64;
    for chunk in input.chunks(32) {
        let mut block_in = [0u8; 24];
        block_in[..16].copy_from_slice(nonce);
        block_in[16..24].copy_from_slice(&counter.to_le_bytes());
        let ks = hmac_sha256(enc_key, &block_in);
        for (i, &b) in chunk.iter().enumerate() {
            out.push(b ^ ks[i]);
        }
        counter = counter.wrapping_add(1);
    }
    out
}

#[cfg(not(windows))]
pub fn protect_secret_bytes(plaintext: &[u8], entropy: &[u8]) -> Result<Vec<u8>, String> {
    const MAGIC: &[u8; 8] = b"DVSEAL02";
    let salt: [u8; 16] = *uuid::Uuid::new_v4().as_bytes();
    let nonce: [u8; 16] = *uuid::Uuid::new_v4().as_bytes();
    let master = derive_unix_machine_key_v2(&salt, entropy);
    let enc_key = hmac_sha256(&master, b"enc");
    let mac_key = hmac_sha256(&master, b"mac");
    let ct = keystream_xor(&enc_key, &nonce, plaintext);

    let mut body = Vec::with_capacity(8 + 16 + 16 + ct.len() + 32);
    body.extend_from_slice(MAGIC);
    body.extend_from_slice(&salt);
    body.extend_from_slice(&nonce);
    body.extend_from_slice(&ct);
    let tag = hmac_sha256(&mac_key, &body);
    body.extend_from_slice(&tag);
    Ok(body)
}

#[cfg(not(windows))]
pub fn unprotect_secret_bytes(sealed: &[u8], entropy: &[u8]) -> Result<Vec<u8>, String> {
    const MAGIC: &[u8; 8] = b"DVSEAL02";
    if sealed.len() < 8 + 16 + 16 + 32 {
        return Err("sealed secret truncated".to_owned());
    }
    if &sealed[..8] != MAGIC {
        return Err("invalid sealed secret header".to_owned());
    }
    let tag_offset = sealed.len() - 32;
    let body = &sealed[..tag_offset];
    let provided_tag = &sealed[tag_offset..];

    let mut salt = [0u8; 16];
    salt.copy_from_slice(&sealed[8..24]);
    let mut nonce = [0u8; 16];
    nonce.copy_from_slice(&sealed[24..40]);

    let master = derive_unix_machine_key_v2(&salt, entropy);
    let enc_key = hmac_sha256(&master, b"enc");
    let mac_key = hmac_sha256(&master, b"mac");
    let expected_tag = hmac_sha256(&mac_key, body);
    if !constant_time_eq(&expected_tag, provided_tag) {
        return Err("sealed secret MAC verification failed (tampered or wrong entropy)".to_owned());
    }
    let ct = &sealed[40..tag_offset];
    Ok(keystream_xor(&enc_key, &nonce, ct))
}

pub fn default_durable_app_data_dir() -> PathBuf {
    if let Ok(explicit) = std::env::var("DAUVERSE_DATA_DIR") {
        let trimmed = explicit.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed);
        }
    }
    #[cfg(windows)]
    {
        if let Ok(local_app_data) = std::env::var("LOCALAPPDATA") {
            let trimmed = local_app_data.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed)
                    .join("DAUVERSE")
                    .join("RemoteDesktopV1");
            }
        }
        if let Ok(app_data) = std::env::var("APPDATA") {
            let trimmed = app_data.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed)
                    .join("DAUVERSE")
                    .join("RemoteDesktopV1");
            }
        }
        if let Ok(profile) = std::env::var("USERPROFILE") {
            let trimmed = profile.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed)
                    .join("AppData")
                    .join("Local")
                    .join("DAUVERSE")
                    .join("RemoteDesktopV1");
            }
        }
        std::env::temp_dir().join("dauverse_remote_v1")
    }
    #[cfg(not(windows))]
    {
        if let Ok(xdg) = std::env::var("XDG_DATA_HOME") {
            let trimmed = xdg.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed).join("dauverse_remote_v1");
            }
        }
        if let Ok(home) = std::env::var("HOME") {
            let trimmed = home.trim();
            if !trimmed.is_empty() {
                return PathBuf::from(trimmed)
                    .join(".local")
                    .join("share")
                    .join("dauverse_remote_v1");
            }
        }
        std::env::temp_dir().join("dauverse_remote_v1")
    }
}

pub fn check_no_symlink_or_reparse_component(path: &Path) -> Result<(), String> {
    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => {
            return Err(format!(
                "SECURITY_STAT_FAILED: failed inspecting '{}': {e}",
                path.display()
            ));
        }
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

#[cfg(any(windows, test))]
#[derive(Debug, PartialEq, Eq)]
enum WinVolumeAuthority {
    Drive(char),
    Unc { server: String, share: String },
}

#[cfg(any(windows, test))]
fn parse_windows_normalized_path(raw: &str) -> Result<(WinVolumeAuthority, Vec<String>), String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed.contains('\0') {
        return Err("SECURITY_REJECT_INVALID_WINDOWS_PATH: empty or NUL path".to_owned());
    }
    if trimmed.starts_with(r"\\.\") || trimmed.starts_with("//./") {
        return Err(format!(
            "SECURITY_REJECT_DEVICE_NAMESPACE: raw device path '{}' forbidden",
            raw
        ));
    }

    let unified = trimmed.replace('/', "\\");
    let unc_rest = unified
        .strip_prefix(r"\\?\UNC\")
        .or_else(|| unified.strip_prefix(r"\\?\unc\"))
        .or_else(|| unified.strip_prefix(r"\??\UNC\"))
        .or_else(|| unified.strip_prefix(r"\??\unc\"))
        .or_else(|| {
            if unified.starts_with(r"\\?\") || unified.starts_with(r"\??\") {
                None
            } else {
                unified.strip_prefix(r"\\")
            }
        });
    let (authority, remainder) = if let Some(rest) = unc_rest {
        let mut iter = rest.split('\\').filter(|s| !s.is_empty());
        let Some(server) = iter.next() else {
            return Err(format!("SECURITY_REJECT_MALFORMED_UNC: missing server in '{raw}'"));
        };
        let Some(share) = iter.next() else {
            return Err(format!("SECURITY_REJECT_MALFORMED_UNC: missing share in '{raw}'"));
        };
        if server == "?"
            || server == "."
            || server == ".."
            || share == "."
            || share == ".."
            || server.contains(':')
            || share.contains(':')
        {
            return Err(format!("SECURITY_REJECT_MALFORMED_UNC: invalid UNC authority in '{raw}'"));
        }
        let rem: Vec<&str> = iter.collect();
        (
            WinVolumeAuthority::Unc {
                server: server.to_ascii_lowercase(),
                share: share.to_ascii_lowercase(),
            },
            rem.join("\\"),
        )
    } else {
        let stripped = unified
            .strip_prefix(r"\\?\")
            .or_else(|| unified.strip_prefix(r"\??\"))
            .unwrap_or(&unified);
        let bytes = stripped.as_bytes();
        if bytes.len() < 2 || !bytes[0].is_ascii_alphabetic() || bytes[1] != b':' {
            return Err(format!(
                "SECURITY_REJECT_NON_ABSOLUTE_WINDOWS_PATH: '{}' lacks drive or UNC authority",
                raw
            ));
        }
        let after_colon = &stripped[2..];
        if !after_colon.is_empty() && !after_colon.starts_with('\\') {
            return Err(format!(
                "SECURITY_REJECT_DRIVE_RELATIVE_PATH: '{}' is drive-relative",
                raw
            ));
        }
        (
            WinVolumeAuthority::Drive((bytes[0] as char).to_ascii_lowercase()),
            after_colon.trim_start_matches('\\').to_owned(),
        )
    };

    let mut components = Vec::new();
    if !remainder.is_empty() {
        for raw_seg in remainder.split('\\') {
            if raw_seg.is_empty() {
                continue;
            }
            if raw_seg == "." || raw_seg == ".." {
                return Err(format!(
                    "SECURITY_REJECT_PATH_TRAVERSAL: dot traversal segment in '{raw}'"
                ));
            }
            if raw_seg.contains(':') {
                return Err(format!(
                    "SECURITY_REJECT_ADS_STREAM: alternate data stream forbidden in '{raw}'"
                ));
            }
            if raw_seg.ends_with('.') || raw_seg.ends_with(' ') {
                return Err(format!(
                    "SECURITY_REJECT_AMBIGUOUS_WINDOWS_SEGMENT: trailing dot/space in '{raw}'"
                ));
            }
            components.push(raw_seg.to_ascii_lowercase());
        }
    }
    Ok((authority, components))
}

#[cfg(any(windows, test))]
pub fn verify_windows_final_path_confined(final_raw: &str, root_raw: &str) -> Result<(), String> {
    let (final_auth, final_comps) = parse_windows_normalized_path(final_raw)?;
    let (root_auth, root_comps) = parse_windows_normalized_path(root_raw)?;
    if final_auth != root_auth {
        return Err(format!(
            "SECURITY_REJECT_HANDLE_ESCAPE: volume mismatch between '{}' and authorized root '{}'",
            final_raw, root_raw
        ));
    }
    if final_comps.len() <= root_comps.len() {
        return Err(format!(
            "SECURITY_REJECT_HANDLE_ESCAPE: handle '{}' is not strictly beneath authorized root '{}'",
            final_raw, root_raw
        ));
    }
    for (idx, root_seg) in root_comps.iter().enumerate() {
        if &final_comps[idx] != root_seg {
            return Err(format!(
                "SECURITY_REJECT_HANDLE_ESCAPE: handle resolved to '{}' outside authorized root '{}'",
                final_raw, root_raw
            ));
        }
    }
    Ok(())
}

#[cfg(windows)]
pub fn query_windows_final_handle_path(file: &File) -> Result<String, String> {
    use std::os::windows::io::AsRawHandle;
    use winapi::um::fileapi::GetFinalPathNameByHandleW;

    const MAX_FINAL_PATH_WCHARS: usize = 32_768;
    let mut buf = vec![0u16; 1024];
    let first_len = unsafe {
        GetFinalPathNameByHandleW(
            file.as_raw_handle() as *mut _,
            buf.as_mut_ptr(),
            buf.len() as u32,
            0,
        )
    } as usize;
    if first_len == 0 {
        return Err(format!(
            "SECURITY_REJECT_HANDLE_FINAL_PATH_UNAVAILABLE: GetFinalPathNameByHandleW returned 0 ({})",
            std::io::Error::last_os_error()
        ));
    }
    if first_len < buf.len() {
        return String::from_utf16(&buf[..first_len]).map_err(|e| {
            format!("SECURITY_REJECT_INVALID_UTF16_FINAL_PATH: GetFinalPathNameByHandleW invalid UTF-16: {e}")
        });
    }
    if first_len >= MAX_FINAL_PATH_WCHARS {
        return Err(format!(
            "SECURITY_REJECT_HANDLE_FINAL_PATH_OVERFLOW: required buffer {} exceeds {}",
            first_len, MAX_FINAL_PATH_WCHARS
        ));
    }
    buf.resize(first_len + 1, 0);
    let second_len = unsafe {
        GetFinalPathNameByHandleW(
            file.as_raw_handle() as *mut _,
            buf.as_mut_ptr(),
            buf.len() as u32,
            0,
        )
    } as usize;
    if second_len == 0 || second_len >= buf.len() {
        return Err(format!(
            "SECURITY_REJECT_HANDLE_FINAL_PATH_RETRY_FAILED: second_len={second_len}, cap={}",
            buf.len()
        ));
    }
    String::from_utf16(&buf[..second_len]).map_err(|e| {
        format!("SECURITY_REJECT_INVALID_UTF16_FINAL_PATH: GetFinalPathNameByHandleW invalid UTF-16: {e}")
    })
}

pub fn ensure_private_dir(dir: &Path) -> Result<(), String> {
    check_no_symlink_or_reparse_component(dir)?;
    let existed = dir.exists();
    fs::create_dir_all(dir).map_err(|e| format!("failed creating directory '{}': {e}", dir.display()))?;
    check_no_symlink_or_reparse_component(dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::{MetadataExt, PermissionsExt};
        let meta = fs::symlink_metadata(dir)
            .map_err(|e| format!("failed stating directory '{}': {e}", dir.display()))?;
        let euid = unsafe { hbb_common::libc::geteuid() };
        if !existed || meta.uid() == euid {
            fs::set_permissions(dir, fs::Permissions::from_mode(0o700))
                .map_err(|e| format!("failed enforcing 0700 permissions on '{}': {e}", dir.display()))?;
        }
    }
    #[cfg(not(unix))]
    let _ = existed;
    Ok(())
}

pub fn write_atomic_bytes(path: &Path, data: &[u8], private_mode: bool) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("missing parent directory for '{}'", path.display()))?;
    if private_mode {
        ensure_private_dir(parent)?;
    } else {
        check_no_symlink_or_reparse_component(parent)?;
        fs::create_dir_all(parent)
            .map_err(|e| format!("failed creating directory '{}': {e}", parent.display()))?;
        check_no_symlink_or_reparse_component(parent)?;
    }
    check_no_symlink_or_reparse_component(path)?;

    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("state");
    let tmp_path = parent.join(format!(".{file_name}.tmp.{}", uuid::Uuid::new_v4()));

    let write_res: Result<(), String> = (|| {
        #[cfg(unix)]
        {
            use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
            let mode = if private_mode { 0o600 } else { 0o644 };
            let mut opts = fs::OpenOptions::new();
            opts.write(true)
                .create_new(true)
                .mode(mode)
                .custom_flags(hbb_common::libc::O_NOFOLLOW);
            let mut f = opts
                .open(&tmp_path)
                .map_err(|e| format!("failed opening atomic temp file: {e}"))?;
            f.set_permissions(fs::Permissions::from_mode(mode))
                .map_err(|e| format!("failed setting file permissions: {e}"))?;
            f.write_all(data)
                .map_err(|e| format!("failed writing atomic temp file: {e}"))?;
            f.sync_all()
                .map_err(|e| format!("failed syncing atomic temp file: {e}"))?;
        }
        #[cfg(windows)]
        {
            use std::os::windows::fs::{MetadataExt, OpenOptionsExt};
            let _ = private_mode;
            const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
            const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
            let canon_parent = parent
                .canonicalize()
                .map_err(|e| format!("failed canonicalizing atomic write parent: {e}"))?;
            let mut f = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
                .open(&tmp_path)
                .map_err(|e| format!("failed opening atomic temp file: {e}"))?;
            let meta = f
                .metadata()
                .map_err(|e| format!("failed reading atomic temp metadata: {e}"))?;
            if (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 || !meta.file_type().is_file() {
                return Err("SECURITY_REJECT_REPARSE_HANDLE: atomic temp handle is reparse or non-regular".to_owned());
            }
            let final_handle_path = query_windows_final_handle_path(&f)?;
            verify_windows_final_path_confined(&final_handle_path, &canon_parent.to_string_lossy())?;
            f.write_all(data)
                .map_err(|e| format!("failed writing atomic temp file: {e}"))?;
            f.sync_all()
                .map_err(|e| format!("failed syncing atomic temp file: {e}"))?;
        }
        #[cfg(not(any(unix, windows)))]
        {
            let _ = private_mode;
            let mut f = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&tmp_path)
                .map_err(|e| format!("failed opening atomic temp file: {e}"))?;
            f.write_all(data)
                .map_err(|e| format!("failed writing atomic temp file: {e}"))?;
            f.sync_all()
                .map_err(|e| format!("failed syncing atomic temp file: {e}"))?;
        }
        check_no_symlink_or_reparse_component(parent)?;
        check_no_symlink_or_reparse_component(path)?;
        fs::rename(&tmp_path, path)
            .map_err(|e| format!("failed atomic rename into '{}': {e}", path.display()))?;
        Ok(())
    })();

    if write_res.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }
    write_res
}

pub fn open_no_follow_regular_file(path: &Path) -> Result<(File, u64), String> {
    check_no_symlink_or_reparse_component(path)?;
    #[cfg(unix)]
    let file = {
        use std::os::unix::fs::OpenOptionsExt;
        fs::OpenOptions::new()
            .read(true)
            .custom_flags(hbb_common::libc::O_NOFOLLOW)
            .open(path)
            .map_err(|e| format!("SECURITY_OPEN_NOFOLLOW_FAILED '{}': {e}", path.display()))?
    };
    #[cfg(windows)]
    let file = {
        use std::os::windows::fs::OpenOptionsExt;
        const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
        fs::OpenOptions::new()
            .read(true)
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .open(path)
            .map_err(|e| format!("SECURITY_OPEN_NOFOLLOW_FAILED '{}': {e}", path.display()))?
    };
    #[cfg(not(any(unix, windows)))]
    let file = File::open(path).map_err(|e| format!("failed opening '{}': {e}", path.display()))?;

    let meta = file
        .metadata()
        .map_err(|e| format!("failed reading open handle metadata '{}': {e}", path.display()))?;
    if meta.file_type().is_symlink() || !meta.file_type().is_file() {
        return Err(format!(
            "SECURITY_REJECT_NON_REGULAR_HANDLE: '{}' is not a regular file",
            path.display()
        ));
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
        if (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 {
            return Err(format!(
                "SECURITY_REJECT_REPARSE_HANDLE: open handle '{}' is a reparse point",
                path.display()
            ));
        }
    }
    Ok((file, meta.len()))
}

pub fn sha256_file_confined_no_follow(
    authorized_root: &Path,
    target_path: &Path,
) -> Result<(String, u64), String> {
    check_no_symlink_or_reparse_component(authorized_root)?;
    let canon_root = authorized_root
        .canonicalize()
        .map_err(|e| format!("failed canonicalizing authorized root: {e}"))?;

    let parent = target_path
        .parent()
        .ok_or_else(|| "missing target parent directory".to_owned())?;
    check_no_symlink_or_reparse_component(parent)?;
    let canon_parent = parent
        .canonicalize()
        .map_err(|e| format!("failed canonicalizing target parent: {e}"))?;
    if !canon_parent.starts_with(&canon_root) {
        return Err("SECURITY_REJECT_OUTSIDE_AUTHORIZED_ROOT: parent escapes authorized root".to_owned());
    }

    if let Ok(rel) = canon_parent.strip_prefix(&canon_root) {
        let mut cursor = canon_root.clone();
        for comp in rel.components() {
            if let Component::Normal(seg) = comp {
                cursor.push(seg);
                check_no_symlink_or_reparse_component(&cursor)?;
            }
        }
    }

    let file_name = target_path
        .file_name()
        .ok_or_else(|| "missing target file name".to_owned())?;
    if let Some(name_str) = file_name.to_str() {
        if name_str.contains(':') || name_str.ends_with('.') || name_str.ends_with(' ') {
            return Err(format!(
                "SECURITY_REJECT_UNSAFE_FILENAME: refusing ADS or ambiguous leaf '{name_str}'"
            ));
        }
    }
    let confined_target = canon_parent.join(file_name);
    let (mut file, expected_len) = open_no_follow_regular_file(&confined_target)?;

    #[cfg(windows)]
    {
        let final_str = query_windows_final_handle_path(&file)?;
        verify_windows_final_path_confined(&final_str, &canon_root.to_string_lossy())?;
    }

    let mut hasher = Sha256::new();
    let mut read_total = 0u64;
    let mut chunk = [0u8; 64 * 1024];
    loop {
        let n = file
            .read(&mut chunk)
            .map_err(|e| format!("failed reading confined file: {e}"))?;
        if n == 0 {
            break;
        }
        hasher.update(&chunk[..n]);
        read_total += n as u64;
    }
    if read_total != expected_len {
        return Err(format!(
            "INTEGRITY_READ_LENGTH_CHANGED: metadata {} != streamed {}",
            expected_len, read_total
        ));
    }
    Ok((hex::encode(hasher.finalize()), read_total))
}

pub fn write_sealed_secret_file(path: &Path, plaintext: &[u8], entropy: &[u8]) -> Result<(), String> {
    let sealed = protect_secret_bytes(plaintext, entropy)?;
    write_atomic_bytes(path, &sealed, true)
}

pub fn read_sealed_secret_file(path: &Path, entropy: &[u8]) -> Result<Vec<u8>, String> {
    let (mut file, _len) = open_no_follow_regular_file(path)?;
    let mut sealed = Vec::new();
    file.read_to_end(&mut sealed)
        .map_err(|e| format!("failed reading vault file: {e}"))?;
    unprotect_secret_bytes(&sealed, entropy)
}

pub fn redact_sensitive(input: &str) -> String {
    let mut out = input.to_owned();
    let prefixes = [
        "sk-ant-",
        "sk-proj-",
        "sk-",
        "ghp_",
        "gho_",
        "ghs_",
        "github_pat_",
        "AIza",
        "xoxb-",
        "xoxp-",
    ];
    for prefix in prefixes {
        let mut search_from = 0usize;
        while let Some(rel) = out[search_from..].find(prefix) {
            let start = search_from + rel;
            let mut end = start + prefix.len();
            let bytes = out.as_bytes();
            while end < bytes.len() {
                let c = bytes[end];
                if c.is_ascii_alphanumeric() || c == b'_' || c == b'-' {
                    end += 1;
                } else {
                    break;
                }
            }
            if end > start + prefix.len() + 3 {
                out.replace_range(start..end, "[REDACTED_TOKEN]");
                search_from = start + "[REDACTED_TOKEN]".len();
            } else {
                search_from = end;
            }
        }
    }

    let kv_markers = [
        "password=",
        "passwd=",
        "secret=",
        "api_key=",
        "apikey=",
        "oauth_token=",
        "access_token=",
        "session_token=",
        "cookie=",
        "Bearer ",
    ];
    for marker in kv_markers {
        let lower = out.to_ascii_lowercase();
        let marker_lower = marker.to_ascii_lowercase();
        if let Some(idx) = lower.find(&marker_lower) {
            let val_start = idx + marker.len();
            let mut val_end = val_start;
            let bytes = out.as_bytes();
            while val_end < bytes.len() {
                let c = bytes[val_end];
                if c.is_ascii_whitespace() || c == b'&' || c == b';' || c == b'"' || c == b'\'' {
                    break;
                }
                val_end += 1;
            }
            if val_end > val_start {
                out.replace_range(val_start..val_end, "[REDACTED]");
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfc4231_hmac_sha256_vectors() {
        let key1 = [0x0bu8; 20];
        let data1 = b"Hi There";
        assert_eq!(
            hmac_sha256_hex(&key1, data1),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        );

        let key2 = b"Jefe";
        let data2 = b"what do ya want for nothing?";
        assert_eq!(
            hmac_sha256_hex(key2, data2),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );

        let key6 = [0xaau8; 131];
        let data6 = b"Test Using Larger Than Block-Size Key - Hash Key First";
        assert_eq!(
            hmac_sha256_hex(&key6, data6),
            "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
        );
    }

    #[test]
    fn seal_unseal_and_reject_tampering() {
        let secret = b"super-secret-unattended-token-v1";
        let entropy = b"device-pair-ctx";
        let mut sealed = protect_secret_bytes(secret, entropy).unwrap();
        assert_ne!(sealed.as_slice(), secret);
        assert!(!String::from_utf8_lossy(&sealed).contains("super-secret"));

        let opened = unprotect_secret_bytes(&sealed, entropy).unwrap();
        assert_eq!(opened, secret);

        assert!(unprotect_secret_bytes(&sealed, b"wrong-entropy").is_err());

        let flip_idx = sealed.len() / 2;
        sealed[flip_idx] ^= 0x55;
        assert!(unprotect_secret_bytes(&sealed, entropy).is_err());
    }

    #[test]
    fn redacts_tokens_and_credentials() {
        let raw = concat!(
            "Job failed with ",
            "sk-ant-",
            "api03-ABCDEF123456789 and Bearer eyJhbGciOiJIUzI1NiJ9 and password=MyPlainPassword123 in output"
        );
        let clean = redact_sensitive(raw);
        assert!(!clean.contains("ABCDEF123456789"));
        assert!(!clean.contains("eyJhbGciOiJIUzI1NiJ9"));
        assert!(!clean.contains("MyPlainPassword123"));
        assert!(clean.contains("[REDACTED_TOKEN]"));
        assert!(clean.contains("[REDACTED]"));
    }

    #[test]
    fn atomic_write_and_confined_nofollow_rejects_symlink_swap() {
        let dir = std::env::temp_dir().join(format!("dv_atomic_{}", uuid::Uuid::new_v4()));
        ensure_private_dir(&dir).unwrap();
        let target = dir.join("state.json");
        write_atomic_bytes(&target, b"{\"v\":1}", true).unwrap();
        write_atomic_bytes(&target, b"{\"v\":2}", true).unwrap();
        let (sha, size) = sha256_file_confined_no_follow(&dir, &target).unwrap();
        assert_eq!(size, 7);
        assert_eq!(sha, sha256_hex(b"{\"v\":2}"));

        #[cfg(unix)]
        {
            let outside = std::env::temp_dir().join(format!("dv_out_{}.txt", uuid::Uuid::new_v4()));
            fs::write(&outside, b"secret-outside").unwrap();
            let swapped = dir.join("swapped.txt");
            std::os::unix::fs::symlink(&outside, &swapped).unwrap();
            assert!(sha256_file_confined_no_follow(&dir, &swapped).is_err());
            assert!(write_atomic_bytes(&swapped, b"overwrite", true).is_err());
            fs::remove_file(&outside).ok();
        }
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn f14_windows_final_path_confinement_enforces_component_boundary_unc_and_ads() {
        assert!(verify_windows_final_path_confined(
            r"\\?\E:\QA\allowed\sub\payload.bin",
            r"\\?\E:\QA\allowed"
        )
        .is_ok());
        assert!(verify_windows_final_path_confined(
            r"E:\QA\ALLOWED\sub\payload.bin",
            r"\\?\e:\qa\allowed"
        )
        .is_ok());

        assert!(verify_windows_final_path_confined(
            r"\\?\E:\QA\allowed-elsewhere\file.bin",
            r"\\?\E:\QA\allowed"
        )
        .is_err());
        assert!(verify_windows_final_path_confined(
            r"\\?\E:\QA\allowed",
            r"\\?\E:\QA\allowed"
        )
        .is_err());
        assert!(verify_windows_final_path_confined(
            r"\\?\C:\QA\allowed\file.bin",
            r"\\?\E:\QA\allowed"
        )
        .is_err());

        assert!(verify_windows_final_path_confined(
            r"\\?\UNC\filesrv\share\allowed\dir\ok.bin",
            r"\\filesrv\share\allowed"
        )
        .is_ok());
        assert!(verify_windows_final_path_confined(
            r"\\?\UNC\filesrv\share\allowed-other\ok.bin",
            r"\\filesrv\share\allowed"
        )
        .is_err());
        assert!(verify_windows_final_path_confined(
            r"\\?\UNC\filesrv\other_share\allowed\ok.bin",
            r"\\filesrv\share\allowed"
        )
        .is_err());

        assert!(verify_windows_final_path_confined(
            r"\\?\E:\QA\allowed\file.bin:Zone.Identifier",
            r"\\?\E:\QA\allowed"
        )
        .is_err());
        assert!(verify_windows_final_path_confined(
            r"\\?\E:\QA\allowed\file.bin:$DATA",
            r"\\?\E:\QA\allowed"
        )
        .is_err());
        assert!(verify_windows_final_path_confined(
            r"\\.\PhysicalDrive0",
            r"\\?\E:\QA\allowed"
        )
        .is_err());
        assert!(verify_windows_final_path_confined(
            r"\\?\E:\QA\allowed\..\outside\file.bin",
            r"\\?\E:\QA\allowed"
        )
        .is_err());

        let deep_seg = "a".repeat(220);
        let long_valid = format!(
            r"\\?\E:\QA\allowed\{0}\{0}\{0}\{0}\{0}\deep.bin",
            deep_seg
        );
        assert!(long_valid.len() > 1100);
        assert!(verify_windows_final_path_confined(&long_valid, r"\\?\E:\QA\allowed").is_ok());
        let long_escape = format!(
            r"\\?\E:\QA\allowed-escape\{0}\{0}\{0}\{0}\{0}\deep.bin",
            deep_seg
        );
        assert!(verify_windows_final_path_confined(&long_escape, r"\\?\E:\QA\allowed").is_err());
    }
}

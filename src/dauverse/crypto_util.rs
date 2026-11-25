use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::Read,
    path::Path,
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
        dpapi::CryptProtectData,
        winbase::LocalFree,
        wincrypt::{CRYPTPROTECT_UI_FORBIDDEN, DATA_BLOB},
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
        dpapi::CryptUnprotectData,
        winbase::LocalFree,
        wincrypt::{CRYPTPROTECT_UI_FORBIDDEN, DATA_BLOB},
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

pub fn write_sealed_secret_file(path: &Path, plaintext: &[u8], entropy: &[u8]) -> Result<(), String> {
    use std::io::Write;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("failed creating vault dir: {e}"))?;
    }
    let sealed = protect_secret_bytes(plaintext, entropy)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)
            .map_err(|e| format!("failed opening 0600 vault file: {e}"))?;
        f.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|e| format!("failed enforcing 0600 permissions: {e}"))?;
        f.write_all(&sealed)
            .map_err(|e| format!("failed writing vault bytes: {e}"))?;
        f.sync_all()
            .map_err(|e| format!("failed syncing vault file: {e}"))?;
    }
    #[cfg(not(unix))]
    {
        fs::write(path, &sealed).map_err(|e| format!("failed writing vault file: {e}"))?;
    }
    Ok(())
}

pub fn read_sealed_secret_file(path: &Path, entropy: &[u8]) -> Result<Vec<u8>, String> {
    let sealed = fs::read(path).map_err(|e| format!("failed reading vault file: {e}"))?;
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
}

use super::crypto_util::{check_no_symlink_or_reparse_component, sha256_file};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const DAUVERSE_PRODUCT_VERSION: &str = "1.0.0-rc4.3";
pub const DAUVERSE_RELEASE_CANDIDATE: &str = "RC4.3";
pub const DAUVERSE_DISPLAY_VERSION: &str = "V1.0 RC4.3";
pub const UPSTREAM_ENGINE_VERSION: &str = "1.5.3";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SignatureStatus {
    VerifiedTrustedPublisher,
    UnsignedBuild,
    UnverifiedPublisher,
    InvalidOrTamperedSignature,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdatePackageDescriptor {
    pub version: String,
    pub download_url: String,
    pub expected_sha256: String,
    pub signature_status: SignatureStatus,
    pub release_notes_vi: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateVerificationResult {
    pub safe_for_auto_update: bool,
    pub safe_for_manual_owner_install: bool,
    pub status_code: String,
    pub computed_sha256: Option<String>,
    pub signature_status: SignatureStatus,
    pub reason: String,
}

pub fn parse_semver_triplet(v: &str) -> Result<(u32, u32, u32), String> {
    let clean = v.trim().trim_start_matches('v').split('+').next().unwrap_or("");
    let clean = clean.split('-').next().unwrap_or("");
    let parts: Vec<&str> = clean.split('.').collect();
    if parts.len() != 3 {
        return Err(format!("invalid semantic version '{v}'"));
    }
    let major = parts[0].parse::<u32>().map_err(|_| "bad major".to_owned())?;
    let minor = parts[1].parse::<u32>().map_err(|_| "bad minor".to_owned())?;
    let patch = parts[2].parse::<u32>().map_err(|_| "bad patch".to_owned())?;
    Ok((major, minor, patch))
}

pub fn inspect_artifact_publisher_signature(artifact_path: &Path) -> SignatureStatus {
    if check_no_symlink_or_reparse_component(artifact_path).is_err() {
        return SignatureStatus::InvalidOrTamperedSignature;
    }

    #[cfg(windows)]
    {
        let pinned_thumb = std::env::var("DAUVERSE_TRUSTED_PUBLISHER_THUMBPRINT")
            .unwrap_or_default()
            .trim()
            .to_ascii_uppercase();
        let ps_arg = format!(
            "$s = Get-AuthenticodeSignature -LiteralPath '{}'; $tp = if ($s.SignerCertificate) {{ $s.SignerCertificate.Thumbprint }} else {{ '' }}; Write-Output \"$($s.Status)|$tp\"",
            artifact_path.to_string_lossy().replace('\'', "''")
        );
        if let Ok(out) = std::process::Command::new("powershell")
            .args(["-NoProfile", "-NonInteractive", "-Command", &ps_arg])
            .output()
        {
            let stdout = String::from_utf8_lossy(&out.stdout);
            let line = stdout.trim();
            let mut parts = line.splitn(2, '|');
            let status = parts.next().unwrap_or("");
            let thumb = parts.next().unwrap_or("").trim().to_ascii_uppercase();
            return match status {
                "NotSigned" => SignatureStatus::UnsignedBuild,
                "HashMismatch" | "NotTrusted" => SignatureStatus::InvalidOrTamperedSignature,
                "Valid" => {
                    if pinned_thumb.len() == 40 && thumb == pinned_thumb {
                        SignatureStatus::VerifiedTrustedPublisher
                    } else {
                        SignatureStatus::UnverifiedPublisher
                    }
                }
                _ => SignatureStatus::UnsignedBuild,
            };
        }
        SignatureStatus::UnsignedBuild
    }

    #[cfg(not(windows))]
    {
        let sig_sidecar = Path::new(&format!("{}.sig", artifact_path.display())).to_path_buf();
        if sig_sidecar.exists() {
            return SignatureStatus::InvalidOrTamperedSignature;
        }
        SignatureStatus::UnsignedBuild
    }
}

pub fn verify_local_update_artifact(
    current_version: &str,
    descriptor: &UpdatePackageDescriptor,
    artifact_path: &Path,
) -> UpdateVerificationResult {
    let observed_sig = if descriptor.signature_status == SignatureStatus::InvalidOrTamperedSignature {
        SignatureStatus::InvalidOrTamperedSignature
    } else {
        inspect_artifact_publisher_signature(artifact_path)
    };

    let Ok(cur) = parse_semver_triplet(current_version) else {
        return UpdateVerificationResult {
            safe_for_auto_update: false,
            safe_for_manual_owner_install: false,
            status_code: "INVALID_CURRENT_VERSION".to_owned(),
            computed_sha256: None,
            signature_status: observed_sig,
            reason: "Current version string is malformed.".to_owned(),
        };
    };
    let Ok(cand) = parse_semver_triplet(&descriptor.version) else {
        return UpdateVerificationResult {
            safe_for_auto_update: false,
            safe_for_manual_owner_install: false,
            status_code: "INVALID_CANDIDATE_VERSION".to_owned(),
            computed_sha256: None,
            signature_status: observed_sig,
            reason: "Candidate version string is malformed.".to_owned(),
        };
    };

    if cand < cur {
        return UpdateVerificationResult {
            safe_for_auto_update: false,
            safe_for_manual_owner_install: false,
            status_code: "SECURITY_REJECT_DOWNGRADE_ATTACK".to_owned(),
            computed_sha256: None,
            signature_status: observed_sig,
            reason: format!(
                "Anti-downgrade blocked candidate {} (< current {}). Use explicit documented Rollback Procedure instead.",
                descriptor.version, current_version
            ),
        };
    }

    if !descriptor.download_url.starts_with("https://") {
        return UpdateVerificationResult {
            safe_for_auto_update: false,
            safe_for_manual_owner_install: false,
            status_code: "SECURITY_REJECT_INSECURE_TRANSPORT".to_owned(),
            computed_sha256: None,
            signature_status: observed_sig,
            reason: "Update URLs must use HTTPS.".to_owned(),
        };
    }

    if let Err(e) = check_no_symlink_or_reparse_component(artifact_path) {
        return UpdateVerificationResult {
            safe_for_auto_update: false,
            safe_for_manual_owner_install: false,
            status_code: "SECURITY_REJECT_UNSAFE_ARTIFACT_PATH".to_owned(),
            computed_sha256: None,
            signature_status: SignatureStatus::InvalidOrTamperedSignature,
            reason: e,
        };
    }

    let actual_sha = match sha256_file(artifact_path) {
        Ok(h) => h,
        Err(e) => {
            return UpdateVerificationResult {
                safe_for_auto_update: false,
                safe_for_manual_owner_install: false,
                status_code: "ARTIFACT_UNREADABLE".to_owned(),
                computed_sha256: None,
                signature_status: observed_sig,
                reason: e,
            };
        }
    };

    if !actual_sha.eq_ignore_ascii_case(descriptor.expected_sha256.trim()) {
        return UpdateVerificationResult {
            safe_for_auto_update: false,
            safe_for_manual_owner_install: false,
            status_code: "SECURITY_REJECT_SHA256_MISMATCH".to_owned(),
            computed_sha256: Some(actual_sha),
            signature_status: observed_sig,
            reason: "Artifact SHA-256 hash does not match signed manifest.".to_owned(),
        };
    }

    match observed_sig {
        SignatureStatus::VerifiedTrustedPublisher => UpdateVerificationResult {
            safe_for_auto_update: cand > cur,
            safe_for_manual_owner_install: true,
            status_code: "VERIFIED_SIGNED_UPDATE_READY".to_owned(),
            computed_sha256: Some(actual_sha),
            signature_status: SignatureStatus::VerifiedTrustedPublisher,
            reason: "Both SHA-256 integrity and pinned publisher Authenticode signature verified independently.".to_owned(),
        },
        SignatureStatus::UnsignedBuild | SignatureStatus::UnverifiedPublisher => {
            let caller_claimed_trusted =
                descriptor.signature_status == SignatureStatus::VerifiedTrustedPublisher;
            let code = if caller_claimed_trusted {
                "UNSIGNED_BUILD_CALLER_CLAIM_OVERRIDDEN_MANUAL_ONLY"
            } else {
                "UNSIGNED_BUILD_MANUAL_ONLY"
            };
            UpdateVerificationResult {
                safe_for_auto_update: false,
                safe_for_manual_owner_install: true,
                status_code: code.to_owned(),
                computed_sha256: Some(actual_sha),
                signature_status: observed_sig,
                reason: "Independent publisher check found no pinned Authenticode signature (caller enum ignored); automatic update remains HARD-DISABLED. Manual Boss-approved SHA-256 install only.".to_owned(),
            }
        }
        SignatureStatus::InvalidOrTamperedSignature => UpdateVerificationResult {
            safe_for_auto_update: false,
            safe_for_manual_owner_install: false,
            status_code: "SECURITY_REJECT_INVALID_SIGNATURE".to_owned(),
            computed_sha256: Some(actual_sha),
            signature_status: SignatureStatus::InvalidOrTamperedSignature,
            reason: "Cryptographic signature verification failed.".to_owned(),
        },
    }
}

pub fn current_release_status() -> serde_json::Value {
    serde_json::json!({
        "product_name": "DAUVERSE REMOTE DESKTOP",
        "short_name": "DAUVERSE REMOTE",
        "product_version": DAUVERSE_PRODUCT_VERSION,
        "release_candidate": DAUVERSE_RELEASE_CANDIDATE,
        "display_version": DAUVERSE_DISPLAY_VERSION,
        "upstream_engine_base": UPSTREAM_ENGINE_VERSION,
        "code_signing_status": "UNSIGNED",
        "auto_update_enabled": false,
        "auto_update_policy": "Disabled until official Authenticode certificate is provisioned and pinned; manual SHA-256 verified update and rollback supported.",
        "rollback_supported": true,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f12_blocks_downgrade_tampered_hash_and_ignores_spoofed_caller_signature_enum() {
        let tmp = std::env::temp_dir().join(format!("dv_upd_{}.bin", uuid::Uuid::new_v4()));
        let bytes = b"DAUVERSE_RELEASE_CANDIDATE_BINARY_BYTES";
        std::fs::write(&tmp, bytes).unwrap();
        let sha = super::super::crypto_util::sha256_hex(bytes);

        let downgrade = UpdatePackageDescriptor {
            version: "0.9.0".to_owned(),
            download_url: "https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/releases/download/v0.9.0/pkg.exe".to_owned(),
            expected_sha256: sha.clone(),
            signature_status: SignatureStatus::VerifiedTrustedPublisher,
            release_notes_vi: "Old".to_owned(),
        };
        let r_down = verify_local_update_artifact("1.0.0", &downgrade, &tmp);
        assert_eq!(r_down.status_code, "SECURITY_REJECT_DOWNGRADE_ATTACK");
        assert!(!r_down.safe_for_auto_update && !r_down.safe_for_manual_owner_install);

        let tampered = UpdatePackageDescriptor {
            version: "1.1.0".to_owned(),
            download_url: "https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/releases/download/v1.1.0/pkg.exe".to_owned(),
            expected_sha256: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".to_owned(),
            signature_status: SignatureStatus::VerifiedTrustedPublisher,
            release_notes_vi: "Tampered".to_owned(),
        };
        let r_tamper = verify_local_update_artifact("1.0.0", &tampered, &tmp);
        assert_eq!(r_tamper.status_code, "SECURITY_REJECT_SHA256_MISMATCH");

        // F12 counterexample: caller falsely claims VerifiedTrustedPublisher on an unsigned file
        let spoofed_signed = UpdatePackageDescriptor {
            version: "1.1.0".to_owned(),
            download_url: "https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/releases/download/v1.1.0/pkg.exe".to_owned(),
            expected_sha256: sha.clone(),
            signature_status: SignatureStatus::VerifiedTrustedPublisher,
            release_notes_vi: "Caller lies about publisher signature".to_owned(),
        };
        let r_spoof = verify_local_update_artifact("1.0.0", &spoofed_signed, &tmp);
        assert!(!r_spoof.safe_for_auto_update);
        assert_ne!(r_spoof.signature_status, SignatureStatus::VerifiedTrustedPublisher);
        assert_eq!(
            r_spoof.status_code,
            "UNSIGNED_BUILD_CALLER_CLAIM_OVERRIDDEN_MANUAL_ONLY"
        );

        let unsigned_cand = UpdatePackageDescriptor {
            version: "1.0.1".to_owned(),
            download_url: "https://github.com/trongtuanhoang1-art/DAUVERSE_REMOTE_DESKTOP/releases/download/v1.0.1/pkg.exe".to_owned(),
            expected_sha256: sha,
            signature_status: SignatureStatus::UnsignedBuild,
            release_notes_vi: "Unsigned RC".to_owned(),
        };
        let r_unsigned = verify_local_update_artifact("1.0.0", &unsigned_cand, &tmp);
        assert!(!r_unsigned.safe_for_auto_update);
        assert!(r_unsigned.safe_for_manual_owner_install);
        assert_eq!(r_unsigned.status_code, "UNSIGNED_BUILD_MANUAL_ONLY");

        std::fs::remove_file(&tmp).ok();
    }
}

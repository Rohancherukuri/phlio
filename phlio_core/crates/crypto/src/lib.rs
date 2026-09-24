//! `phlio-crypto` — signing, verification, and secure ID generation.
//!
//! This crate backs the parts of Phlio Trust / Phlio Core that must be
//! deterministic and hard to get subtly wrong: signing payment/session
//! payloads, verifying webhook-style callbacks, and generating IDs that are
//! sortable, unique, and safe to expose to clients.
//!
//! It deliberately does NOT decide *whether* an action is authorized — that
//! stays in the backend's policy layer (see Phlio_Production_Architecture.md
//! section 18, "Phlio Guard"). This crate only provides the primitives.

use hmac::{Hmac, Mac};
use phlio_common::{PhlioError, PhlioResult};
use rand::RngCore;
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

/// Signs `payload` with `secret` using HMAC-SHA256 and returns a lowercase
/// hex-encoded signature.
///
/// Used anywhere Phlio needs to prove a message was produced by a trusted
/// party without needing full asymmetric crypto — e.g. signed deep links,
/// short-lived action tokens the Agent hands back to the client, or
/// internal service-to-service request signing.
pub fn sign(secret: &[u8], payload: &[u8]) -> PhlioResult<String> {
    let mut mac = HmacSha256::new_from_slice(secret)
        .map_err(|_| PhlioError::new("invalid_key", "HMAC key has invalid length"))?;
    mac.update(payload);
    let signature = hex::encode(mac.finalize().into_bytes());
    // Never log `secret` or `payload` — only shape/length, so a log line
    // is useful for debugging ("did signing run at all?") without ever
    // becoming a place secrets could leak into log aggregation.
    log::debug!("crypto.signed payload_len={} signature_len={}", payload.len(), signature.len());
    Ok(signature)
}

/// Verifies that `signature` (lowercase hex) matches `payload` signed with
/// `secret`. Uses the constant-time comparison built into the `hmac` crate
/// (`verify_slice`) to avoid timing side-channels.
pub fn verify(secret: &[u8], payload: &[u8], signature_hex: &str) -> PhlioResult<bool> {
    let mut mac = HmacSha256::new_from_slice(secret)
        .map_err(|_| PhlioError::new("invalid_key", "HMAC key has invalid length"))?;
    mac.update(payload);
    let expected = hex::decode(signature_hex)
        .map_err(|_| PhlioError::new("invalid_signature", "signature is not valid hex"))?;
    let valid = mac.verify_slice(&expected).is_ok();
    if !valid {
        // A failed verification is worth a WARN, not a DEBUG — it's either
        // a bug upstream or someone probing with a forged signature.
        log::warn!("crypto.verify_failed payload_len={}", payload.len());
    }
    Ok(valid)
}

/// Generates a 128-bit cryptographically random ID, hex-encoded, prefixed
/// with a short domain tag (e.g. "usr", "pst", "rm", "art") so IDs are
/// self-describing in logs without leaking sequential information the way
/// an auto-increment integer would.
///
/// This is intentionally simple (random, not time-sortable like ULID) so
/// that it cannot be used to infer creation order or record counts — a
/// requirement carried over from the Phlio Guard / privacy principles in
/// the architecture document.
pub fn generate_id(prefix: &str) -> String {
    let mut bytes = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut bytes);
    let id = format!("{prefix}_{}", hex::encode(bytes));
    log::trace!("crypto.id_generated prefix={prefix}");
    id
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_and_verify_round_trip() {
        let secret = b"super-secret-signing-key";
        let payload = b"user_id=usr_123&action=book_movie";
        let signature = sign(secret, payload).unwrap();
        assert!(verify(secret, payload, &signature).unwrap());
    }

    #[test]
    fn verify_rejects_tampered_payload() {
        let secret = b"super-secret-signing-key";
        let signature = sign(secret, b"amount=100").unwrap();
        assert!(!verify(secret, b"amount=100000", &signature).unwrap());
    }

    #[test]
    fn verify_rejects_wrong_secret() {
        let signature = sign(b"secret-a", b"payload").unwrap();
        assert!(!verify(b"secret-b", b"payload", &signature).unwrap());
    }

    #[test]
    fn generated_ids_are_unique_and_prefixed() {
        let a = generate_id("usr");
        let b = generate_id("usr");
        assert_ne!(a, b);
        assert!(a.starts_with("usr_"));
        // prefix + '_' + 32 hex chars (16 bytes)
        assert_eq!(a.len(), "usr_".len() + 32);
    }
}

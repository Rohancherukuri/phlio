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
use sha1::Sha1;
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

// ---------------------------------------------------------------------------
// TOTP (RFC 6238) — the second factor behind Settings → Two-factor auth.
// ---------------------------------------------------------------------------

/// Seconds per TOTP time step (RFC 6238 default, what authenticator apps use).
pub const TOTP_STEP_SECS: u64 = 30;
/// Digits per code.
pub const TOTP_DIGITS: u32 = 6;

/// Decodes an RFC 4648 base32 string (case-insensitive, padding and spaces
/// optional) — the format authenticator apps show and `otpauth://` URIs carry.
pub fn base32_decode(input: &str) -> PhlioResult<Vec<u8>> {
    let mut out = Vec::with_capacity(input.len() * 5 / 8);
    let (mut buffer, mut bits) = (0u32, 0u32);
    for ch in input.bytes() {
        let value = match ch {
            b'A'..=b'Z' => ch - b'A',
            b'a'..=b'z' => ch - b'a',
            b'2'..=b'7' => ch - b'2' + 26,
            b'=' | b' ' | b'-' => continue,
            _ => return Err(PhlioError::new("invalid_secret", "secret is not valid base32")),
        } as u32;
        buffer = (buffer << 5) | value;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    if out.is_empty() {
        return Err(PhlioError::new("invalid_secret", "secret is empty"));
    }
    Ok(out)
}

/// The 6-digit code for one time step (HOTP over HMAC-SHA1, RFC 4226 §5.3).
pub fn totp_code(key: &[u8], step: u64) -> PhlioResult<String> {
    let mut mac = Hmac::<Sha1>::new_from_slice(key)
        .map_err(|_| PhlioError::new("invalid_key", "TOTP key has invalid length"))?;
    mac.update(&step.to_be_bytes());
    let digest = mac.finalize().into_bytes();
    let offset = (digest[digest.len() - 1] & 0x0f) as usize;
    let value = u32::from_be_bytes([
        digest[offset] & 0x7f,
        digest[offset + 1],
        digest[offset + 2],
        digest[offset + 3],
    ]);
    Ok(format!("{:0width$}", value % 10u32.pow(TOTP_DIGITS), width = TOTP_DIGITS as usize))
}

/// Returns the time step `code` belongs to — the current one, or one step
/// either side to tolerate clock drift — or `None` when it matches none.
///
/// Every candidate is compared in constant time and all three are always
/// checked, so response timing does not reveal which window (if any) matched.
/// Callers must store the returned step and reject it next time (replay guard).
pub fn totp_matching_step(secret_b32: &str, code: &str, unix_now: u64) -> PhlioResult<Option<u64>> {
    let code: String = code.chars().filter(|c| !c.is_whitespace()).collect();
    if code.len() != TOTP_DIGITS as usize || !code.bytes().all(|b| b.is_ascii_digit()) {
        return Ok(None);
    }
    let key = base32_decode(secret_b32)?;
    let current = unix_now / TOTP_STEP_SECS;
    let mut found = None;
    for step in [current, current.saturating_sub(1), current + 1] {
        let candidate = totp_code(&key, step)?;
        if constant_time_eq(candidate.as_bytes(), code.as_bytes()) && found.is_none() {
            found = Some(step);
        }
    }
    Ok(found)
}

/// Compares two byte strings without short-circuiting on the first
/// difference (length is not secret, so it may return early on that).
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// Lowercase hex SHA-256 — used for hashing backup codes and refresh tokens
/// before they are stored, so a database leak never exposes usable secrets.
pub fn sha256_hex(data: &[u8]) -> String {
    use sha2::Digest;
    hex::encode(Sha256::digest(data))
}

#[cfg(test)]
mod totp_tests {
    use super::*;

    // RFC 6238 Appendix B test vector (SHA-1, seed "12345678901234567890").
    const RFC_SECRET: &str = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

    #[test]
    fn rfc6238_vectors() {
        let key = base32_decode(RFC_SECRET).unwrap();
        assert_eq!(key, b"12345678901234567890");
        // T = 59s → 94287082 (8 digits) → last 6 digits "287082".
        assert_eq!(totp_code(&key, 59 / 30).unwrap(), "287082");
        assert_eq!(totp_code(&key, 1111111109 / 30).unwrap(), "081804");
        assert_eq!(totp_code(&key, 2000000000 / 30).unwrap(), "279037");
    }

    #[test]
    fn matching_step_accepts_drift_and_rejects_garbage() {
        let now = 1111111109;
        assert_eq!(totp_matching_step(RFC_SECRET, "081 804", now).unwrap(), Some(now / 30));
        assert_eq!(totp_matching_step(RFC_SECRET, "081804", now + 30).unwrap(), Some(now / 30));
        assert_eq!(totp_matching_step(RFC_SECRET, "000000", now).unwrap(), None);
        assert_eq!(totp_matching_step(RFC_SECRET, "12ab56", now).unwrap(), None);
        assert!(totp_matching_step("!!!", "123456", now).is_err());
    }

    #[test]
    fn constant_time_eq_works() {
        assert!(constant_time_eq(b"abc", b"abc"));
        assert!(!constant_time_eq(b"abc", b"abd"));
        assert!(!constant_time_eq(b"abc", b"ab"));
    }
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

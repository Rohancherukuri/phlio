//! `phlio-common` — shared value types and error handling.
//!
//! Every other crate in the `phlio_core` workspace depends on this one so
//! that error shapes and small value objects stay consistent across the
//! engine, instead of every crate inventing its own `Result`/`Error` pair.

use serde::{Deserialize, Serialize};
use std::fmt;

/// The single error type returned by any `phlio_core` crate.
///
/// Kept intentionally small and serializable so the CLI layer can turn it
/// straight into the JSON error envelope that the Python backend expects.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhlioError {
    /// Machine-readable error code, e.g. "invalid_signature".
    pub code: String,
    /// Human-readable explanation, safe to log (never contains secrets).
    pub message: String,
}

impl PhlioError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

impl fmt::Display for PhlioError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} ({})", self.message, self.code)
    }
}

impl std::error::Error for PhlioError {}

/// Convenience alias used throughout the workspace.
pub type PhlioResult<T> = Result<T, PhlioError>;

/// Money is always represented as an integer amount of the smallest currency
/// unit (paise for INR) plus an ISO 4217 currency code. This avoids the
/// classic floating-point rounding bugs in anything that touches payments.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Money {
    /// Amount in the smallest unit of the currency (e.g. paise, cents).
    pub minor_units: i64,
    /// ISO 4217 currency code, e.g. "INR".
    pub currency: [u8; 3],
}

impl Money {
    pub fn new(minor_units: i64, currency: &str) -> PhlioResult<Self> {
        let bytes = currency.as_bytes();
        if bytes.len() != 3 {
            return Err(PhlioError::new(
                "invalid_currency",
                "currency must be a 3-letter ISO 4217 code",
            ));
        }
        let mut code = [0u8; 3];
        code.copy_from_slice(bytes);
        Ok(Self {
            minor_units,
            currency: code,
        })
    }

    pub fn currency_code(&self) -> String {
        String::from_utf8_lossy(&self.currency).to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn money_round_trips_currency_code() {
        let m = Money::new(150_00, "INR").unwrap();
        assert_eq!(m.currency_code(), "INR");
        assert_eq!(m.minor_units, 15000);
    }

    #[test]
    fn money_rejects_bad_currency_code() {
        let err = Money::new(100, "RUPEE").unwrap_err();
        assert_eq!(err.code, "invalid_currency");
    }
}

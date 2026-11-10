//! `phlio_native` — the `phlio_core` crates as an in-process Python module.
//!
//! The backend used to reach Rust by spawning the `phlio-core` CLI for every
//! call (fork + exec + JSON over pipes: roughly 1–3 ms each, paid on every
//! post, comment, message and sign-up that needs an ID). Loading the same code
//! as an extension module turns that into a plain function call of a few
//! hundred nanoseconds, with identical behaviour because both front-ends wrap
//! the very same crates.
//!
//! Exposed to Python (see `backend/app/infrastructure/core_engine/native.py`):
//!
//! | function / class                         | backed by                          |
//! |------------------------------------------|------------------------------------|
//! | `generate_id(prefix) -> str`             | `phlio_crypto::generate_id`        |
//! | `sign(secret, payload) -> str`           | `phlio_crypto::sign` (HMAC-SHA256) |
//! | `verify(secret, payload, sig) -> bool`   | `phlio_crypto::verify` (const-time)|
//! | `constant_time_eq(a, b) -> bool`         | `phlio_crypto::constant_time_eq`   |
//! | `sha256_hex(data) -> str`                | `phlio_crypto::sha256_hex`         |
//! | `totp_matching_step(secret, code, now)`  | `phlio_crypto::totp_matching_step` |
//! | `score_risk(event: dict) -> dict`        | `phlio_risk_features::score_event` |
//! | `Throttle(...)`                          | `phlio_guard::Throttle`            |
//!
//! # Safety and robustness
//!
//! * No `unsafe` in this crate; PyO3 handles the FFI boundary.
//! * Errors become `ValueError` with the crate's error code, never a crash.
//! * Built with `panic = "unwind"` (profile `release-native`) so an unexpected
//!   panic surfaces as a Python exception instead of aborting the server.
//! * CPU-bound work on caller-sized input (hashing, signing) releases the GIL,
//!   so other requests keep running on other threads meanwhile.
//! * Secrets are accepted as `str` or `bytes` and are never logged.

// PyO3 0.22's `#[pyfunction]` expansion trips this lint on `PyResult` returns
// (fixed upstream in 0.23); it is a false positive, not a real conversion.
#![allow(clippy::useless_conversion)]

use phlio_common::PhlioError;
use phlio_guard::{Throttle as RustThrottle, ThrottleConfig};
use phlio_risk_features::{score_event, RiskDecision, RiskEvent};
use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use pyo3::types::{PyBytes, PyDict, PyString};

/// Version of this module, so the backend can log which build is loaded.
const VERSION: &str = env!("CARGO_PKG_VERSION");

fn to_py_err(err: PhlioError) -> PyErr {
    PyValueError::new_err(format!("{}: {}", err.code, err.message))
}

/// Accepts `str` (UTF-8 encoded) or `bytes` for secrets and payloads.
fn as_bytes(value: &Bound<'_, PyAny>) -> PyResult<Vec<u8>> {
    if let Ok(s) = value.downcast::<PyString>() {
        Ok(s.to_cow()?.as_bytes().to_vec())
    } else if let Ok(b) = value.downcast::<PyBytes>() {
        Ok(b.as_bytes().to_vec())
    } else {
        Err(PyValueError::new_err("expected str or bytes"))
    }
}

/// `generate_id("usr") -> "usr_<32 hex chars>"` — 128 random bits.
#[pyfunction]
fn generate_id(prefix: &str) -> PyResult<String> {
    if prefix.is_empty() || prefix.len() > 16 || !prefix.bytes().all(|b| b.is_ascii_alphanumeric()) {
        return Err(PyValueError::new_err("prefix must be 1-16 ASCII letters or digits"));
    }
    Ok(phlio_crypto::generate_id(prefix))
}

/// HMAC-SHA256 of `payload` under `secret`, lowercase hex.
#[pyfunction]
fn sign(py: Python<'_>, secret: &Bound<'_, PyAny>, payload: &Bound<'_, PyAny>) -> PyResult<String> {
    let (secret, payload) = (as_bytes(secret)?, as_bytes(payload)?);
    py.allow_threads(|| phlio_crypto::sign(&secret, &payload)).map_err(to_py_err)
}

/// Constant-time check of an HMAC-SHA256 hex signature. Malformed hex is
/// simply "not valid" (False), so callers can't distinguish failure modes.
#[pyfunction]
fn verify(
    py: Python<'_>,
    secret: &Bound<'_, PyAny>,
    payload: &Bound<'_, PyAny>,
    signature: &str,
) -> PyResult<bool> {
    let (secret, payload) = (as_bytes(secret)?, as_bytes(payload)?);
    let signature = signature.to_owned();
    Ok(py
        .allow_threads(|| phlio_crypto::verify(&secret, &payload, &signature))
        .unwrap_or(false))
}

/// Timing-safe equality for tokens, codes and digests.
#[pyfunction]
fn constant_time_eq(a: &Bound<'_, PyAny>, b: &Bound<'_, PyAny>) -> PyResult<bool> {
    Ok(phlio_crypto::constant_time_eq(&as_bytes(a)?, &as_bytes(b)?))
}

/// Lowercase hex SHA-256.
#[pyfunction]
fn sha256_hex(py: Python<'_>, data: &Bound<'_, PyAny>) -> PyResult<String> {
    let data = as_bytes(data)?;
    Ok(py.allow_threads(|| phlio_crypto::sha256_hex(&data)))
}

/// The TOTP step `code` matches (now ± one step), or `None`.
/// Raises `ValueError` if `secret` is not base32.
#[pyfunction]
#[pyo3(signature = (secret, code, now))]
fn totp_matching_step(secret: &str, code: &str, now: f64) -> PyResult<Option<u64>> {
    if !now.is_finite() || now < 0.0 {
        return Err(PyValueError::new_err("now must be a non-negative unix time"));
    }
    phlio_crypto::totp_matching_step(secret, code, now as u64).map_err(to_py_err)
}

fn get_or<'py, T: FromPyObject<'py>>(event: &Bound<'py, PyDict>, key: &str, default: T) -> PyResult<T> {
    match event.get_item(key)? {
        Some(v) if !v.is_none() => v
            .extract()
            .map_err(|_| PyValueError::new_err(format!("invalid_feature: {key} has the wrong type"))),
        _ => Ok(default),
    }
}

/// Rules-based risk score. Takes the same dict the CLI's `score-risk` reads
/// (missing keys use the same defaults as the Python fallback) and returns
/// `{"score": int, "decision": "Allow"|"Review"|"Block", "reasons": [str]}`.
#[pyfunction]
fn score_risk<'py>(py: Python<'py>, event: &Bound<'py, PyDict>) -> PyResult<Bound<'py, PyDict>> {
    let event = RiskEvent {
        velocity_count: get_or(event, "velocity_count", 0u32)?,
        account_age_days: get_or(event, "account_age_days", 0u32)?,
        is_known_device: get_or(event, "is_known_device", true)?,
        amount_minor_units: get_or(event, "amount_minor_units", 0i64)?,
        is_unusual_location: get_or(event, "is_unusual_location", false)?,
        recent_failed_auth_attempts: get_or(event, "recent_failed_auth_attempts", 0u32)?,
    };
    let result = score_event(&event).map_err(to_py_err)?;
    let out = PyDict::new_bound(py);
    out.set_item("score", result.score)?;
    out.set_item(
        "decision",
        match result.decision {
            RiskDecision::Allow => "Allow",
            RiskDecision::Review => "Review",
            RiskDecision::Block => "Block",
        },
    )?;
    out.set_item("reasons", result.reasons)?;
    Ok(out)
}

/// Brute-force guard: failures per key with exponential lockouts.
///
/// ```python
/// t = Throttle(max_failures=5, window_secs=900, lockout_secs=60, max_lockout_secs=3600)
/// if (wait := t.retry_after(key, time.time())) > 0: reject(wait)
/// ... on bad password: t.record_failure(key, time.time())
/// ... on success:      t.reset(key)
/// ```
#[pyclass(name = "Throttle", frozen)]
struct PyThrottle {
    inner: RustThrottle,
}

#[pymethods]
impl PyThrottle {
    #[new]
    #[pyo3(signature = (max_failures=5, window_secs=900.0, lockout_secs=60.0, max_lockout_secs=3600.0, max_keys=100_000))]
    fn new(max_failures: u32, window_secs: f64, lockout_secs: f64, max_lockout_secs: f64, max_keys: usize) -> PyResult<Self> {
        let valid = max_failures > 0
            && max_keys > 0
            && [window_secs, lockout_secs, max_lockout_secs].iter().all(|v| v.is_finite() && *v > 0.0);
        if !valid {
            return Err(PyValueError::new_err("throttle limits must be positive"));
        }
        Ok(Self {
            inner: RustThrottle::new(ThrottleConfig { max_failures, window_secs, lockout_secs, max_lockout_secs, max_keys }),
        })
    }

    /// Seconds the key stays locked (0.0 = may try now).
    fn retry_after(&self, key: &str, now: f64) -> f64 {
        self.inner.retry_after(key, now)
    }

    /// Records a failure; returns the lockout length if the key is now locked.
    fn record_failure(&self, key: &str, now: f64) -> f64 {
        self.inner.record_failure(key, now)
    }

    /// Forgets the key (after a successful sign-in).
    fn reset(&self, key: &str) {
        self.inner.reset(key)
    }

    fn __len__(&self) -> usize {
        self.inner.len()
    }
}

#[pymodule]
fn phlio_native(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add("__version__", VERSION)?;
    m.add_function(wrap_pyfunction!(generate_id, m)?)?;
    m.add_function(wrap_pyfunction!(sign, m)?)?;
    m.add_function(wrap_pyfunction!(verify, m)?)?;
    m.add_function(wrap_pyfunction!(constant_time_eq, m)?)?;
    m.add_function(wrap_pyfunction!(sha256_hex, m)?)?;
    m.add_function(wrap_pyfunction!(totp_matching_step, m)?)?;
    m.add_function(wrap_pyfunction!(score_risk, m)?)?;
    m.add_class::<PyThrottle>()?;
    Ok(())
}

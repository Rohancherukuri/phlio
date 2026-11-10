//! `phlio-guard` — brute-force throttling for sign-in, 2FA and other
//! credential-checking endpoints.
//!
//! # Model
//!
//! Each *key* (e.g. `"login:user:arjun"` or `"login:ip:203.0.113.7"`) has a
//! sliding failure window. When a key collects `max_failures` failures
//! within `window_secs`, it is locked for `lockout_secs`; each further lockout
//! of the same key doubles the lockout (capped at `max_lockout_secs`), so a
//! patient attacker gets exponentially fewer guesses per hour while a user
//! who mistypes a password a few times is barely slowed down.
//! A successful sign-in calls [`Throttle::reset`].
//!
//! # Why Rust
//!
//! The check runs on every login request *before* the password hash is
//! computed, so it has to be cheap and safe under concurrency. The table sits
//! behind one `Mutex` (each operation is a hash-map lookup, well under a
//! microsecond) and is bounded: when it grows past `max_keys`, expired entries
//! are pruned and, if that is not enough, the oldest are evicted — so a flood
//! of random usernames cannot exhaust memory.
//!
//! # Scope
//!
//! State is per process. With several workers or instances, each keeps its own
//! table, which still caps guesses at `instances × max_failures` per window;
//! a shared store (Redis) can replace this later behind the same interface.
//!
//! Time is passed in by the caller (`now` in seconds), which keeps the crate
//! free of hidden clocks and makes it fully deterministic in tests.

use std::collections::HashMap;
use std::sync::Mutex;

/// Tuning for a [`Throttle`]. The defaults suit password sign-in.
#[derive(Debug, Clone, Copy)]
pub struct ThrottleConfig {
    /// Failures allowed inside the window before the key is locked.
    pub max_failures: u32,
    /// Length of the sliding failure window, in seconds.
    pub window_secs: f64,
    /// First lockout length, in seconds. Doubles on every repeat lockout.
    pub lockout_secs: f64,
    /// Upper bound for the doubling lockout, in seconds.
    pub max_lockout_secs: f64,
    /// Maximum number of keys tracked before pruning/eviction kicks in.
    pub max_keys: usize,
}

impl Default for ThrottleConfig {
    fn default() -> Self {
        Self {
            max_failures: 5,
            window_secs: 15.0 * 60.0,
            lockout_secs: 60.0,
            max_lockout_secs: 60.0 * 60.0,
            max_keys: 100_000,
        }
    }
}

#[derive(Debug, Clone)]
struct Entry {
    /// Timestamps of failures inside the current window (oldest first).
    failures: Vec<f64>,
    /// Locked until this time (0 = not locked).
    locked_until: f64,
    /// How many times this key has been locked (drives the doubling).
    strikes: u32,
    /// Last time the entry changed, used for pruning and eviction.
    touched: f64,
}

/// Thread-safe failure counter with exponential lockouts.
#[derive(Debug)]
pub struct Throttle {
    config: ThrottleConfig,
    entries: Mutex<HashMap<String, Entry>>,
}

impl Throttle {
    pub fn new(config: ThrottleConfig) -> Self {
        Self { config, entries: Mutex::new(HashMap::new()) }
    }

    pub fn config(&self) -> ThrottleConfig {
        self.config
    }

    /// Seconds the key is still locked for (0.0 = allowed to try).
    pub fn retry_after(&self, key: &str, now: f64) -> f64 {
        let entries = self.lock();
        entries.get(key).map_or(0.0, |e| (e.locked_until - now).max(0.0))
    }

    /// Records one failed attempt. Returns the lockout in seconds if this
    /// failure tripped (or the key already is in) a lockout, else 0.0.
    pub fn record_failure(&self, key: &str, now: f64) -> f64 {
        let cfg = self.config;
        let mut entries = self.lock();
        if entries.len() >= cfg.max_keys && !entries.contains_key(key) {
            Self::make_room(&mut entries, &cfg, now);
        }
        let entry = entries.entry(key.to_owned()).or_insert_with(|| Entry {
            failures: Vec::new(),
            locked_until: 0.0,
            strikes: 0,
            touched: now,
        });
        entry.touched = now;
        if entry.locked_until > now {
            return entry.locked_until - now;
        }
        entry.failures.retain(|t| now - t < cfg.window_secs);
        entry.failures.push(now);
        if entry.failures.len() as u32 >= cfg.max_failures {
            let factor = 2f64.powi(entry.strikes.min(16) as i32);
            let lockout = (cfg.lockout_secs * factor).min(cfg.max_lockout_secs);
            entry.locked_until = now + lockout;
            entry.strikes = entry.strikes.saturating_add(1);
            entry.failures.clear();
            log::warn!("guard.locked strikes={} lockout_secs={lockout}", entry.strikes);
            return lockout;
        }
        0.0
    }

    /// Forgets a key (call after a successful sign-in).
    pub fn reset(&self, key: &str) {
        self.lock().remove(key);
    }

    /// Number of keys currently tracked (for metrics and tests).
    pub fn len(&self) -> usize {
        self.lock().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Entry>> {
        // A panic while holding the lock cannot leave the map logically
        // inconsistent (every mutation is a single field write), so recover
        // from poisoning instead of failing every later sign-in.
        self.entries.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn make_room(entries: &mut HashMap<String, Entry>, cfg: &ThrottleConfig, now: f64) {
        // Drop entries that are neither locked nor holding recent failures.
        // Strikes on a forgotten key are lost, which is acceptable: it only
        // happens under a flood, when the IP key still throttles the sender.
        entries.retain(|_, e| {
            e.locked_until > now || e.failures.iter().any(|t| now - t < cfg.window_secs)
        });
        if entries.len() >= cfg.max_keys {
            // Still full: evict the least recently touched tenth.
            let mut by_age: Vec<(f64, String)> =
                entries.iter().map(|(k, e)| (e.touched, k.clone())).collect();
            by_age.sort_by(|a, b| a.0.total_cmp(&b.0));
            for (_, k) in by_age.into_iter().take((cfg.max_keys / 10).max(1)) {
                entries.remove(&k);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg() -> ThrottleConfig {
        ThrottleConfig { max_failures: 3, window_secs: 60.0, lockout_secs: 10.0, max_lockout_secs: 35.0, max_keys: 4 }
    }

    #[test]
    fn locks_after_max_failures_then_unlocks() {
        let t = Throttle::new(cfg());
        assert_eq!(t.record_failure("k", 0.0), 0.0);
        assert_eq!(t.record_failure("k", 1.0), 0.0);
        assert_eq!(t.record_failure("k", 2.0), 10.0);
        assert_eq!(t.retry_after("k", 5.0), 7.0);
        // Failures during a lockout do not extend it.
        assert_eq!(t.record_failure("k", 5.0), 7.0);
        assert_eq!(t.retry_after("k", 12.0), 0.0);
    }

    #[test]
    fn repeat_lockouts_double_and_cap() {
        let t = Throttle::new(cfg());
        let mut now = 0.0;
        let mut lockouts = vec![];
        for _ in 0..3 {
            for _ in 0..3 {
                let l = t.record_failure("k", now);
                if l > 0.0 { lockouts.push(l); now += l; }
            }
        }
        assert_eq!(lockouts, vec![10.0, 20.0, 35.0]);
    }

    #[test]
    fn old_failures_slide_out_of_the_window() {
        let t = Throttle::new(cfg());
        t.record_failure("k", 0.0);
        t.record_failure("k", 1.0);
        assert_eq!(t.record_failure("k", 100.0), 0.0);
    }

    #[test]
    fn reset_clears_state() {
        let t = Throttle::new(cfg());
        for i in 0..3 { t.record_failure("k", i as f64); }
        t.reset("k");
        assert_eq!(t.retry_after("k", 3.0), 0.0);
    }

    #[test]
    fn table_is_bounded() {
        let t = Throttle::new(cfg());
        for i in 0..50 { t.record_failure(&format!("k{i}"), i as f64); }
        assert!(t.len() <= 4);
    }
}

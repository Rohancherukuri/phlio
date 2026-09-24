//! `phlio-risk-features` — deterministic, rule-based risk scoring.
//!
//! Implements the "Rules" half of the risk architecture described in
//! Phlio_Production_Architecture.md section 19 (Phlio Guard):
//!
//! ```text
//! Event → Feature extraction → Rules + ML risk model → Risk aggregation
//!       → Graph analysis → Policy engine → Allow / Review / Block
//! ```
//!
//! This crate intentionally covers only the deterministic "Rules" stage.
//! It is a pure function of its inputs — no I/O, no randomness — so it is
//! trivially testable and auditable, and safe to run on the hot path of a
//! payment or account-security decision. The ML model and the final
//! allow/review/block policy decision belong to the backend's `security`
//! domain, which combines this score with other signals.

use phlio_common::{PhlioError, PhlioResult};
use serde::{Deserialize, Serialize};

/// Inputs used to compute a risk score for a single event (login, payment,
/// booking, etc). All fields are plain, already-extracted features — this
/// crate does not know how to read a database or a request; that is the
/// backend's job.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskEvent {
    /// Number of similar actions by this account in the trailing window
    /// (e.g. payments in the last 10 minutes). Higher = more suspicious.
    pub velocity_count: u32,
    /// Age of the account in days. Newer accounts are riskier.
    pub account_age_days: u32,
    /// Whether this device/browser has been seen before for this account.
    pub is_known_device: bool,
    /// Transaction amount in minor currency units (0 for non-financial
    /// events such as logins).
    pub amount_minor_units: i64,
    /// Whether the action is happening from a country/region that differs
    /// from the account's usual location.
    pub is_unusual_location: bool,
    /// Number of failed authentication attempts immediately preceding this
    /// event.
    pub recent_failed_auth_attempts: u32,
}

/// The outcome of a rules-based risk assessment.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RiskDecision {
    Allow,
    Review,
    Block,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskScore {
    /// 0-100, higher is riskier.
    pub score: u8,
    pub decision: RiskDecision,
    /// Which rules fired, for auditability — every score must be explainable.
    pub reasons: Vec<String>,
}

const REVIEW_THRESHOLD: u8 = 40;
const BLOCK_THRESHOLD: u8 = 75;

/// Scores a single risk event against a fixed set of weighted rules.
///
/// The weights below are deliberately simple starting points, not a tuned
/// production model — the architecture document is explicit that "Models
/// should assist decision systems, not become the sole authority for
/// high-impact actions," so this function is designed to be transparent
/// and easy to replace/extend as real fraud data becomes available.
pub fn score_event(event: &RiskEvent) -> PhlioResult<RiskScore> {
    if event.velocity_count > 100_000 {
        // Sanity bound — guards against a malformed upstream feature pipeline
        // silently producing nonsense scores.
        log::warn!("risk.rejected reason=implausible_velocity velocity_count={}", event.velocity_count);
        return Err(PhlioError::new(
            "invalid_feature",
            "velocity_count is implausibly large",
        ));
    }

    let mut score: i32 = 0;
    let mut reasons = Vec::new();

    if event.velocity_count >= 10 {
        score += 30;
        reasons.push("high_velocity".to_string());
    } else if event.velocity_count >= 5 {
        score += 15;
        reasons.push("elevated_velocity".to_string());
    }

    if event.account_age_days < 1 {
        score += 25;
        reasons.push("brand_new_account".to_string());
    } else if event.account_age_days < 7 {
        score += 10;
        reasons.push("young_account".to_string());
    }

    if !event.is_known_device {
        score += 15;
        reasons.push("unrecognized_device".to_string());
    }

    if event.is_unusual_location {
        score += 15;
        reasons.push("unusual_location".to_string());
    }

    if event.recent_failed_auth_attempts >= 3 {
        score += 20;
        reasons.push("repeated_auth_failures".to_string());
    }

    // Large payments carry inherently higher impact if fraudulent, so scale
    // the score up gently for high-value transactions (amount is in minor
    // units; ₹50,000 == 5_000_000 paise).
    if event.amount_minor_units >= 5_000_000 {
        score += 15;
        reasons.push("high_value_transaction".to_string());
    }

    let clamped = score.clamp(0, 100) as u8;
    let decision = if clamped >= BLOCK_THRESHOLD {
        RiskDecision::Block
    } else if clamped >= REVIEW_THRESHOLD {
        RiskDecision::Review
    } else {
        RiskDecision::Allow
    };

    match decision {
        RiskDecision::Allow => log::debug!("risk.scored score={clamped} decision=Allow"),
        RiskDecision::Review => log::info!(
            "risk.scored score={clamped} decision=Review reasons={reasons:?}"
        ),
        RiskDecision::Block => log::warn!(
            "risk.scored score={clamped} decision=Block reasons={reasons:?}"
        ),
    }

    Ok(RiskScore {
        score: clamped,
        decision,
        reasons,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn baseline_event() -> RiskEvent {
        RiskEvent {
            velocity_count: 1,
            account_age_days: 365,
            is_known_device: true,
            amount_minor_units: 10_000,
            is_unusual_location: false,
            recent_failed_auth_attempts: 0,
        }
    }

    #[test]
    fn trusted_established_account_is_allowed() {
        let result = score_event(&baseline_event()).unwrap();
        assert_eq!(result.decision, RiskDecision::Allow);
        assert!(result.reasons.is_empty());
    }

    #[test]
    fn brand_new_device_high_velocity_gets_blocked() {
        let event = RiskEvent {
            velocity_count: 12,
            account_age_days: 0,
            is_known_device: false,
            amount_minor_units: 6_000_000,
            is_unusual_location: true,
            recent_failed_auth_attempts: 4,
        };
        let result = score_event(&event).unwrap();
        assert_eq!(result.decision, RiskDecision::Block);
        assert_eq!(result.score, 100);
    }

    #[test]
    fn moderately_risky_event_is_sent_to_review() {
        let event = RiskEvent {
            velocity_count: 6,
            account_age_days: 3,
            is_known_device: false,
            ..baseline_event()
        };
        let result = score_event(&event).unwrap();
        assert_eq!(result.decision, RiskDecision::Review);
    }

    #[test]
    fn rejects_implausible_velocity() {
        let event = RiskEvent {
            velocity_count: 1_000_000,
            ..baseline_event()
        };
        assert!(score_event(&event).is_err());
    }
}

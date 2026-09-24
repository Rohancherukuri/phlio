//! `phlio-core` CLI — the boundary between the Rust engine and the rest of
//! the platform.
//!
//! Rather than requiring the Python backend to link against Rust through
//! PyO3/maturin (extra build complexity for a v1), the engine is exposed as
//! a small, fast, stateless command-line tool that reads one JSON object on
//! stdin and writes one JSON object on stdout. The backend's
//! `infrastructure/core_engine` module shells out to this binary per call.
//!
//! This keeps the integration point simple and language-agnostic: any
//! future service (a Go worker, another Rust service, a shell script) can
//! reuse the exact same binary with no bindings to maintain. When
//! throughput requirements outgrow "one process per call" (Stage 8 — Scale,
//! in the architecture document), this CLI can be wrapped in a small
//! long-running server without changing its JSON contract.
//!
//! Usage:
//!   phlio-core generate-id --prefix usr
//!   echo '{"secret":"...","payload":"..."}'          | phlio-core sign
//!   echo '{"secret":"...","payload":"...","signature":"..."}' | phlio-core verify
//!   echo '{"velocity_count":1, ...}'                  | phlio-core score-risk

use std::io::{self, Read};
use std::process::ExitCode;

use phlio_crypto::{generate_id, sign, verify};
use phlio_risk_features::{score_event, RiskEvent};
use serde::Deserialize;
use serde_json::{json, Value};

fn read_stdin_json() -> Result<Value, String> {
    let mut buf = String::new();
    io::stdin()
        .read_to_string(&mut buf)
        .map_err(|e| format!("failed to read stdin: {e}"))?;
    serde_json::from_str(&buf).map_err(|e| format!("invalid JSON on stdin: {e}"))
}

fn print_ok(value: Value) {
    println!("{}", json!({ "ok": true, "data": value }));
}

fn print_err(code: &str, message: &str) -> ExitCode {
    eprintln!("{}", json!({ "ok": false, "error": { "code": code, "message": message } }));
    ExitCode::FAILURE
}

#[derive(Deserialize)]
struct SignRequest {
    secret: String,
    payload: String,
}

#[derive(Deserialize)]
struct VerifyRequest {
    secret: String,
    payload: String,
    signature: String,
}

fn main() -> ExitCode {
    // Logs to stderr (env_logger's default target) so stdout stays
    // reserved for the single JSON response object the Python backend
    // parses — mixing log lines into stdout would corrupt that contract.
    // Controlled by `RUST_LOG` (e.g. `RUST_LOG=debug phlio-core score-risk`);
    // silent by default so a normal subprocess call from the backend
    // produces no noise unless the caller opts in.
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn"))
        .format_timestamp_millis()
        .init();

    let mut args = std::env::args().skip(1);
    let command = match args.next() {
        Some(c) => c,
        None => return print_err("missing_command", "expected a subcommand (generate-id | sign | verify | score-risk)"),
    };
    log::debug!("cli.invoked command={command}");

    match command.as_str() {
        "generate-id" => {
            let mut prefix = "id".to_string();
            let rest: Vec<String> = args.collect();
            let mut i = 0;
            while i < rest.len() {
                if rest[i] == "--prefix" {
                    if let Some(v) = rest.get(i + 1) {
                        prefix = v.clone();
                    }
                    i += 1;
                }
                i += 1;
            }
            print_ok(json!({ "id": generate_id(&prefix) }));
            ExitCode::SUCCESS
        }
        "sign" => {
            let body = match read_stdin_json() {
                Ok(v) => v,
                Err(e) => return print_err("invalid_input", &e),
            };
            let req: SignRequest = match serde_json::from_value(body) {
                Ok(r) => r,
                Err(e) => return print_err("invalid_input", &e.to_string()),
            };
            match sign(req.secret.as_bytes(), req.payload.as_bytes()) {
                Ok(signature) => {
                    print_ok(json!({ "signature": signature }));
                    ExitCode::SUCCESS
                }
                Err(e) => print_err(&e.code, &e.message),
            }
        }
        "verify" => {
            let body = match read_stdin_json() {
                Ok(v) => v,
                Err(e) => return print_err("invalid_input", &e),
            };
            let req: VerifyRequest = match serde_json::from_value(body) {
                Ok(r) => r,
                Err(e) => return print_err("invalid_input", &e.to_string()),
            };
            match verify(req.secret.as_bytes(), req.payload.as_bytes(), &req.signature) {
                Ok(valid) => {
                    print_ok(json!({ "valid": valid }));
                    ExitCode::SUCCESS
                }
                Err(e) => print_err(&e.code, &e.message),
            }
        }
        "score-risk" => {
            let body = match read_stdin_json() {
                Ok(v) => v,
                Err(e) => return print_err("invalid_input", &e),
            };
            let event: RiskEvent = match serde_json::from_value(body) {
                Ok(r) => r,
                Err(e) => return print_err("invalid_input", &e.to_string()),
            };
            match score_event(&event) {
                Ok(result) => {
                    print_ok(serde_json::to_value(result).unwrap());
                    ExitCode::SUCCESS
                }
                Err(e) => print_err(&e.code, &e.message),
            }
        }
        other => print_err("unknown_command", &format!("unknown subcommand: {other}")),
    }
}

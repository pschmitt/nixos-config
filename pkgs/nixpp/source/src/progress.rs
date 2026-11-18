//! Progress of runtime setup (`nixpp init`, `nixpp login`).
//!
//! Human mode prints short status lines and lets Nix write to the terminal.
//! JSON mode (`--json`) prints one JSON object per line on stdout, for the
//! TermuxPP first-start dialog:
//!
//! - `{"event":"extract"}`: the bootstrap seed is being verified and unpacked
//! - `{"event":"prepared"}`: the runtime exists; packages are imported next
//! - `{"event":"package","index":1,"total":13,"name":"bash-interactive-5.3p20"}`
//! - `{"event":"copy","name":"readline-8.3p3"}`: Nix copies a store path
//! - `{"event":"log","line":"..."}`: any other output of the import
//! - `{"event":"check"}`: final runtime checks
//! - `{"event":"ready","runtime":"/path"}`

use serde_json::{Value, json};
use std::io::Write;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

static JSON: AtomicBool = AtomicBool::new(false);

/// Select JSON progress for this process.
pub fn set_json(enabled: bool) {
    JSON.store(enabled, Ordering::Relaxed);
}

/// Whether progress is reported as JSON lines.
pub fn json() -> bool {
    JSON.load(Ordering::Relaxed)
}

fn emit(value: Value) {
    let mut stdout = std::io::stdout().lock();
    // Progress is best effort: a closed reader must not fail the setup.
    let _ = writeln!(stdout, "{value}");
    let _ = stdout.flush();
}

/// The display name of a store path: its basename without the hash.
pub fn store_name(path: &str) -> &str {
    let base = path.rsplit('/').next().unwrap_or(path);
    match base.split_once('-') {
        Some((hash, name)) if hash.len() == 32 && !name.is_empty() => name,
        _ => base,
    }
}

pub fn extract() {
    if json() {
        emit(json!({"event": "extract"}));
    }
}

pub fn prepared() {
    if json() {
        emit(json!({"event": "prepared"}));
    } else {
        println!("Prepared isolated runtime; package import is still required.");
    }
}

pub fn package(index: usize, total: usize, path: &str) {
    if json() {
        emit(json!({
            "event": "package",
            "index": index + 1,
            "total": total,
            "name": store_name(path),
        }));
    }
}

/// Report one line of import output (JSON mode only).
pub fn output_line(line: &str) {
    if !json() {
        return;
    }
    let line = line.trim_end();
    if line.is_empty() {
        return;
    }
    if let Some(rest) = line.strip_prefix("copying path '")
        && let Some((path, _)) = rest.split_once('\'')
    {
        emit(json!({"event": "copy", "name": store_name(path)}));
        return;
    }
    emit(json!({"event": "log", "line": line}));
}

pub fn check() {
    if json() {
        emit(json!({"event": "check"}));
    }
}

pub fn ready(directory: &Path) {
    if json() {
        emit(json!({"event": "ready", "runtime": directory.display().to_string()}));
    } else {
        println!("Runtime ready: {}/session.sh", directory.display());
        println!("The normal TermuxPP shell and prefix have not been changed.");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn store_names_drop_the_hash() {
        assert_eq!(
            store_name("/nix/store/x5b3k5pnynrjijw5bzvqrcbdhi5p81d3-bash-interactive-5.3p20"),
            "bash-interactive-5.3p20"
        );
        assert_eq!(store_name("plain"), "plain");
        assert_eq!(store_name("/nix/store/short-name"), "short-name");
    }
}

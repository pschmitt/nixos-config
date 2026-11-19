//! The native, journaled system controller.
//!
//! Every mutating operation takes the exclusive controller lock, records its
//! intent in `system-pending.json` before touching Home Manager, and removes
//! the journal only after the new selection is published, so an interrupted
//! activation can always be recovered.

use crate::error::{Error, Result};
use crate::fsutil::{
    FileLock, STATE_LIMIT, atomic_write, canonical_json, is_symlink, path_str, read_bounded,
    read_state_value, regular_file_size, to_canonical,
};
use crate::runner::Runner;
use crate::store::{is_candidate_name, is_store_root};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Sets the Home Manager profile; the store path is a positional argument.
pub const PROFILE_SET: &str = "exec nix-env --profile \"${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager\" --set \"$1\"";

const CHECK_TIMEOUT: Duration = Duration::from_secs(1200);
const ACTIVATE_TIMEOUT: Duration = Duration::from_secs(1800);
const PROFILE_TIMEOUT: Duration = Duration::from_secs(300);

const STATE_FILE: &str = "system-state.json";
const PENDING_FILE: &str = "system-pending.json";
const CURRENT_FILE: &str = "current-system";
pub(crate) const CONTROL_LOCK: &str = "system-control.lock";
const SECRETS_SUFFIX: &str = "/bin/activate-secrets";

/// The selected system and the retained previous one.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct State {
    pub current: Option<String>,
    #[serde(rename = "homeManager")]
    pub home_manager: Option<String>,
    pub previous: Option<String>,
    #[serde(rename = "previousHomeManager")]
    pub previous_home_manager: Option<String>,
}

fn string_or_null(object: &serde_json::Map<String, Value>, key: &str) -> Result<Option<String>> {
    match object.get(key) {
        Some(Value::String(text)) => Ok(Some(text.clone())),
        Some(Value::Null) => Ok(None),
        _ => Err(Error::invalid("invalid system state")),
    }
}

impl State {
    /// Strictly parse a state object: all four keys, each a string or null.
    pub fn from_value(value: &Value) -> Result<Self> {
        let object = value
            .as_object()
            .ok_or_else(|| Error::invalid("invalid system state"))?;
        Ok(Self {
            current: string_or_null(object, "current")?,
            home_manager: string_or_null(object, "homeManager")?,
            previous: string_or_null(object, "previous")?,
            previous_home_manager: string_or_null(object, "previousHomeManager")?,
        })
    }
}

/// The write-ahead record of an activation in progress.
#[derive(Serialize)]
struct Journal<'a> {
    before: &'a State,
    after: &'a State,
    phase: &'a str,
}

/// One entry of `list-generations`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Generation {
    pub number: Option<usize>,
    pub date: Option<String>,
    pub generation: String,
    #[serde(rename = "homeManager")]
    pub home_manager: String,
    pub current: bool,
    pub previous: bool,
}

/// The validated parts of a candidate manifest that the controller uses.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub home_manager: String,
    pub system_secrets: Option<String>,
    pub activation_supported: bool,
}

fn resolve(runtime: &Path) -> Result<PathBuf> {
    Ok(fs::canonicalize(runtime)?)
}

fn read_state(runtime: &Path) -> Result<Option<State>> {
    read_state_value(runtime, STATE_FILE)?
        .map(|value| State::from_value(&value))
        .transpose()
}

pub(crate) fn pending_exists(runtime: &Path) -> Result<bool> {
    Ok(read_state_value(runtime, PENDING_FILE)?.is_some())
}

fn write_json<T: Serialize>(runtime: &Path, filename: &str, value: &T) -> Result<()> {
    atomic_write(&runtime.join(filename), &(to_canonical(value)? + "\n"))
}

fn remove_journal(runtime: &Path) -> Result<()> {
    fs::remove_file(runtime.join(PENDING_FILE))?;
    Ok(())
}

/// Validate and load the manifest of a prepared candidate.
pub fn candidate_manifest(runtime: &Path, name: &str) -> Result<Candidate> {
    if !is_candidate_name(name) {
        return Err(Error::invalid("invalid candidate name"));
    }
    let candidates = runtime.join("system-candidates");
    let candidate = candidates.join(name);
    if is_symlink(&candidates) || is_symlink(&candidate) {
        return Err(Error::invalid("candidate directory must not be a symlink"));
    }
    let manifest = candidate.join("manifest.json");
    if regular_file_size(&manifest).is_none_or(|size| size > STATE_LIMIT) {
        return Err(Error::invalid("invalid candidate manifest file"));
    }
    let data: Value = serde_json::from_slice(&read_bounded(&manifest, STATE_LIMIT)?)?;
    let supported = data.as_object().is_some_and(|object| {
        object.get("formatVersion").and_then(Value::as_i64) == Some(1)
            && object.get("stateVersion").and_then(Value::as_str) == Some("1")
            && object.get("runtime").and_then(Value::as_str) == Some("droid-nix")
    });
    if !supported {
        return Err(Error::invalid("unsupported candidate manifest"));
    }
    let record = candidate.join("generation");
    if regular_file_size(&record).is_none_or(|size| size > 4096) {
        return Err(Error::invalid("invalid candidate generation record"));
    }
    let text = String::from_utf8(read_bounded(&record, 4096)?)
        .map_err(|_| Error::invalid("invalid candidate generation record"))?;
    let generation = text.trim();
    if !is_store_root(generation) || generation.strip_prefix("/nix/store/") != Some(name) {
        return Err(Error::invalid(
            "candidate generation does not match its name",
        ));
    }
    let home_manager = match data.get("homeManager").and_then(Value::as_str) {
        Some(home) if is_store_root(home) => home.to_owned(),
        _ => {
            return Err(Error::invalid(
                "candidate needs a store-backed Home Manager generation",
            ));
        }
    };
    let system_secrets = match data.get("systemSecrets") {
        None | Some(Value::Null) => None,
        Some(Value::String(secrets))
            if secrets
                .strip_suffix(SECRETS_SUFFIX)
                .is_some_and(is_store_root) =>
        {
            Some(secrets.clone())
        }
        Some(_) => {
            return Err(Error::invalid(
                "candidate needs a store-backed system secrets activator",
            ));
        }
    };
    Ok(Candidate {
        home_manager,
        system_secrets,
        activation_supported: data.get("activationSupported") == Some(&Value::Bool(true)),
    })
}

/// `sh session.sh (--legacy | --system NAME) -- ARGUMENTS...`
pub fn session_command(
    runtime: &Path,
    name: Option<&str>,
    arguments: &[String],
) -> Result<Vec<String>> {
    let mut command = vec![
        "/system/bin/sh".to_owned(),
        path_str(&runtime.join("session.sh"))?,
    ];
    match name {
        None => command.push("--legacy".to_owned()),
        Some(name) => {
            command.push("--system".to_owned());
            command.push(name.to_owned());
        }
    }
    command.push("--".to_owned());
    command.extend_from_slice(arguments);
    Ok(command)
}

/// Run the fixed runtime check in a fresh session of the candidate.
pub fn check(runtime: &Path, name: &str, thorough: bool, runner: &mut dyn Runner) -> Result<i32> {
    let runtime = resolve(runtime)?;
    let candidate = candidate_manifest(&runtime, name)?;
    let home = candidate.home_manager;
    let mut arguments = vec![
        format!("{home}/home-path/bin/full-nix-check-runtime"),
        "--isolated".to_owned(),
        "--generation".to_owned(),
        home,
    ];
    if thorough {
        arguments.push("--thorough".to_owned());
    }
    runner.run(
        &session_command(&runtime, Some(name), &arguments)?,
        CHECK_TIMEOUT,
    )
}

fn require_success(status: i32, what: &str) -> Result<()> {
    if status == 0 {
        Ok(())
    } else {
        Err(Error::invalid(format!(
            "{what} failed with status {status}; recovery is required"
        )))
    }
}

/// Activate a Home Manager generation (and the candidate's system secrets)
/// inside the session of `name`, or of the legacy runtime when `None`.
fn activate_home(
    runtime: &Path,
    name: Option<&str>,
    home: Option<&str>,
    runner: &mut dyn Runner,
) -> Result<()> {
    let home = home
        .filter(|home| is_store_root(home))
        .ok_or_else(|| Error::invalid("invalid Home Manager generation"))?;
    if let Some(name) = name
        && let Some(secrets) = candidate_manifest(runtime, name)?.system_secrets
    {
        let command = session_command(runtime, Some(name), &[secrets])?;
        let status = runner.run(&command, ACTIVATE_TIMEOUT)?;
        require_success(status, "System secrets activation")?;
    }
    let command = session_command(runtime, name, &[format!("{home}/activate")])?;
    require_success(
        runner.run(&command, ACTIVATE_TIMEOUT)?,
        "Home Manager activation",
    )?;
    // Upstream activate prints "No change so reusing latest profile generation"
    // while the current-home GC root already points at this generation, so the
    // XDG profile can stay behind after a recovery. Let upstream nix-env
    // reconcile it; the store path is a positional argument, never shell text.
    let arguments = ["/bin/sh", "-c", PROFILE_SET, "profile-set", home].map(str::to_owned);
    let command = session_command(runtime, name, &arguments)?;
    require_success(
        runner.run(&command, PROFILE_TIMEOUT)?,
        "Home Manager profile synchronization",
    )
}

/// Publish the selection: `current-system` first, then the state file.
fn publish_selection(runtime: &Path, state: &State) -> Result<()> {
    if state
        .current
        .as_deref()
        .is_some_and(|name| !is_candidate_name(name))
    {
        return Err(Error::invalid("invalid current system"));
    }
    let name = state.current.as_deref().unwrap_or("");
    atomic_write(&runtime.join(CURRENT_FILE), &format!("{name}\n"))?;
    write_json(runtime, STATE_FILE, state)
}

/// Check, activate and select `name`.
///
/// `previous_home` is the verified active Home Manager generation and is
/// required exactly for the first migration. `expected_state` makes the
/// operation fail if the state changed since the caller read it (rollback).
pub fn switch(
    runtime: &Path,
    name: &str,
    previous_home: Option<&str>,
    runner: &mut dyn Runner,
    expected_state: Option<&State>,
) -> Result<i32> {
    let runtime = resolve(runtime)?;
    let _lock = FileLock::acquire(&runtime.join(CONTROL_LOCK))?;
    if pending_exists(&runtime)? {
        return Err(Error::invalid(
            "an unfinished activation exists; run recover first",
        ));
    }
    let data = candidate_manifest(&runtime, name)?;
    if !data.activation_supported {
        return Err(Error::invalid(
            "candidate does not support coordinated activation",
        ));
    }
    let old = read_state(&runtime)?;
    if let Some(expected) = expected_state
        && old.as_ref() != Some(expected)
    {
        return Err(Error::invalid("system state changed; retry rollback"));
    }
    let old = match old {
        Some(old) => {
            if previous_home.is_some() {
                return Err(Error::invalid(
                    "previous Home Manager may only be supplied for the first migration",
                ));
            }
            old
        }
        None => {
            let previous = previous_home
                .filter(|home| is_store_root(home))
                .ok_or_else(|| {
                    Error::invalid(
                        "first migration requires the verified previous Home Manager generation",
                    )
                })?;
            let activate = runtime
                .join("root")
                .join(previous.trim_start_matches('/'))
                .join("activate");
            if !activate.is_file() {
                return Err(Error::invalid(
                    "previous Home Manager generation is unavailable",
                ));
            }
            let root = runtime.join("root/nix/var/nix/gcroots/termuxpp-system-baseline");
            if is_symlink(&root) {
                if fs::read_link(&root)? != Path::new(previous) {
                    return Err(Error::invalid(
                        "baseline GC root does not match the previous generation",
                    ));
                }
            } else {
                symlink(previous, &root)?;
            }
            State {
                current: None,
                home_manager: Some(previous.to_owned()),
                previous: None,
                previous_home_manager: None,
            }
        }
    };
    if old.current.as_deref() == Some(name) {
        return Ok(0);
    }
    let status = check(&runtime, name, true, runner)?;
    if status != 0 {
        return Ok(status);
    }
    let new = State {
        current: Some(name.to_owned()),
        home_manager: Some(data.home_manager.clone()),
        previous: old.current.clone(),
        previous_home_manager: old.home_manager.clone(),
    };
    let journal = |phase| Journal {
        before: &old,
        after: &new,
        phase,
    };
    write_json(&runtime, PENDING_FILE, &journal("activating"))?;
    activate_home(&runtime, Some(name), Some(&data.home_manager), runner)?;
    let status = check(&runtime, name, true, runner)?;
    if status != 0 {
        return Err(Error::invalid(format!(
            "post-activation check failed with status {status}; recovery is required"
        )));
    }
    write_json(&runtime, PENDING_FILE, &journal("publishing"))?;
    publish_selection(&runtime, &new)?;
    remove_journal(&runtime)?;
    Ok(0)
}

/// Restore the generation recorded before an interrupted activation.
pub fn recover(runtime: &Path, runner: &mut dyn Runner) -> Result<i32> {
    let runtime = resolve(runtime)?;
    let _lock = FileLock::acquire(&runtime.join(CONTROL_LOCK))?;
    let journal = read_state_value(&runtime, PENDING_FILE)?
        .ok_or_else(|| Error::invalid("no unfinished activation to recover"))?;
    let before = State::from_value(
        journal
            .get("before")
            .ok_or_else(|| Error::invalid("invalid system state"))?,
    )?;
    if let Some(current) = before.current.as_deref() {
        candidate_manifest(&runtime, current)?;
    }
    activate_home(
        &runtime,
        before.current.as_deref(),
        before.home_manager.as_deref(),
        runner,
    )?;
    publish_selection(&runtime, &before)?;
    remove_journal(&runtime)?;
    Ok(0)
}

/// Activate and select the retained previous generation.
pub fn rollback(runtime: &Path, runner: &mut dyn Runner) -> Result<i32> {
    let runtime = resolve(runtime)?;
    let state = match read_state(&runtime)? {
        Some(state) if state.previous_home_manager.is_some() => state,
        _ => return Err(Error::invalid("no previous generation is retained")),
    };
    if let Some(previous) = state.previous.as_deref() {
        return switch(&runtime, previous, None, runner, Some(&state));
    }
    let _lock = FileLock::acquire(&runtime.join(CONTROL_LOCK))?;
    if pending_exists(&runtime)? {
        return Err(Error::invalid(
            "an unfinished activation exists; run recover first",
        ));
    }
    if read_state(&runtime)?.as_ref() != Some(&state) {
        return Err(Error::invalid("system state changed; retry rollback"));
    }
    let old = State {
        current: None,
        home_manager: state.previous_home_manager.clone(),
        previous: state.current.clone(),
        previous_home_manager: state.home_manager.clone(),
    };
    write_json(
        &runtime,
        PENDING_FILE,
        &Journal {
            before: &state,
            after: &old,
            phase: "activating",
        },
    )?;
    activate_home(&runtime, None, old.home_manager.as_deref(), runner)?;
    publish_selection(&runtime, &old)?;
    remove_journal(&runtime)?;
    Ok(0)
}

/// List the prepared candidates and mark the selected and previous ones.
pub fn generations(runtime: &Path) -> Result<Vec<Generation>> {
    let state = read_state(runtime)?;
    let current = state.as_ref().and_then(|state| state.current.as_deref());
    let previous = state.as_ref().and_then(|state| state.previous.as_deref());
    let candidates = runtime.join("system-candidates");
    if is_symlink(&candidates) {
        return Err(Error::invalid("candidate directory must not be a symlink"));
    }
    let mut names = Vec::new();
    if candidates.exists() {
        for entry in fs::read_dir(&candidates)? {
            let name = entry?
                .file_name()
                .into_string()
                .map_err(|_| Error::invalid("candidate name is not valid UTF-8"))?;
            names.push(name);
        }
    }
    let mut result = Vec::new();
    for name in names {
        if name.starts_with('.') {
            continue;
        }
        let data = candidate_manifest(runtime, &name)?;
        result.push(Generation {
            number: None,
            date: None,
            home_manager: data.home_manager,
            current: Some(name.as_str()) == current,
            previous: Some(name.as_str()) == previous,
            generation: name,
        });
    }
    annotate_generations(runtime, result)
}

/// Number retained candidates by preparation time. The generation record is
/// created during preparation and remains untouched by switches and rollbacks.
pub(crate) fn annotate_generations(
    runtime: &Path,
    generations: Vec<Generation>,
) -> Result<Vec<Generation>> {
    let candidates = runtime.join("system-candidates");
    let mut dated: Vec<_> = generations
        .into_iter()
        .map(|generation| {
            let candidate = candidates.join(&generation.generation);
            let record = candidate.join("generation");
            if !is_candidate_name(&generation.generation)
                || is_symlink(&candidates)
                || is_symlink(&candidate)
                || regular_file_size(&record).is_none()
            {
                return Err(Error::invalid("invalid candidate generation record"));
            }
            Ok((fs::metadata(record)?.modified()?, generation))
        })
        .collect::<Result<_>>()?;
    dated.sort_by(|(left_time, left), (right_time, right)| {
        left_time
            .cmp(right_time)
            .then_with(|| left.generation.cmp(&right.generation))
    });
    Ok(dated
        .into_iter()
        .enumerate()
        .map(|(index, (time, mut generation))| {
            generation.number = Some(index + 1);
            generation.date = utc_date(time);
            generation
        })
        .collect())
}

fn utc_date(time: SystemTime) -> Option<String> {
    let seconds: libc::time_t = time
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_secs()
        .try_into()
        .ok()?;
    let mut result = std::mem::MaybeUninit::<libc::tm>::uninit();
    // SAFETY: seconds is an initialized time_t, and result points to writable
    // storage for one tm. gmtime_r initializes the result on success.
    let date = unsafe {
        if libc::gmtime_r(&seconds, result.as_mut_ptr()).is_null() {
            return None;
        }
        result.assume_init()
    };
    Some(format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}Z",
        i64::from(date.tm_year) + 1900,
        date.tm_mon + 1,
        date.tm_mday,
        date.tm_hour,
        date.tm_min,
        date.tm_sec
    ))
}

/// Serve one management request: an allowlist of exactly five commands.
pub fn dispatch(runtime: &Path, request: &Value, runner: &mut dyn Runner) -> Result<Value> {
    let object = request
        .as_object()
        .filter(|object| {
            object
                .keys()
                .all(|key| key == "command" || key == "candidate")
        })
        .ok_or_else(|| Error::invalid("invalid management request"))?;
    let command = object.get("command").and_then(Value::as_str);
    if let Some(command @ ("switch" | "check")) = command {
        let name = object
            .get("candidate")
            .and_then(Value::as_str)
            .filter(|name| is_candidate_name(name))
            .ok_or_else(|| Error::invalid("invalid candidate name"))?;
        let status = if command == "switch" {
            switch(runtime, name, None, runner, None)?
        } else {
            check(runtime, name, true, runner)?
        };
        return Ok(json!({ "status": status }));
    }
    if object.contains_key("candidate") {
        return Err(Error::invalid("unexpected candidate argument"));
    }
    match command {
        Some("list-generations") => Ok(json!({
            "status": 0,
            "generations": serde_json::to_value(generations(&resolve(runtime)?)?)?,
        })),
        Some("rollback") => Ok(json!({ "status": rollback(runtime, runner)? })),
        Some("recover") => Ok(json!({ "status": recover(runtime, runner)? })),
        _ => Err(Error::invalid("unsupported management command")),
    }
}

/// Process exit code for a command status: signals map to `128 + signal`.
pub fn exit_code(status: i32) -> u8 {
    let code = if status >= 0 { status } else { 128 - status };
    (code & 0xff) as u8
}

/// Serialise a response for the wire (sorted keys, ASCII only).
pub fn encode_response(response: &Value) -> String {
    canonical_json(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{Fixture, MockRunner, Outcome};
    use serde_json::json;
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    use std::sync::{Arc, Mutex};

    fn message(result: Result<impl std::fmt::Debug>) -> String {
        result.unwrap_err().to_string()
    }

    fn mkfifo(path: &Path) {
        let path = CString::new(path.as_os_str().as_bytes()).unwrap();
        // SAFETY: valid NUL-terminated path.
        assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
    }

    fn do_switch(fixture: &Fixture, runner: &mut MockRunner) -> Result<i32> {
        switch(
            &fixture.runtime,
            &fixture.name,
            Some(&fixture.baseline),
            runner,
            None,
        )
    }

    #[test]
    fn fixed_check_in_fresh_candidate_session() {
        let fixture = Fixture::new();
        let mut runner = MockRunner::returning(0);
        let status = check(&fixture.runtime, &fixture.name, false, &mut runner).unwrap();
        assert_eq!(status, 0);
        assert_eq!(runner.calls.len(), 1);
        let (command, timeout) = &runner.calls[0];
        assert_eq!(
            command,
            &vec![
                "/system/bin/sh".to_owned(),
                fixture.session_script(),
                "--system".to_owned(),
                fixture.name.clone(),
                "--".to_owned(),
                format!("{}/home-path/bin/full-nix-check-runtime", fixture.home),
                "--isolated".to_owned(),
                "--generation".to_owned(),
                fixture.home.clone(),
            ]
        );
        assert_eq!(*timeout, Duration::from_secs(1200));
        assert!(!fixture.exists("current-system"));
        assert_eq!(fs::read_dir(&fixture.candidate).unwrap().count(), 2);
    }

    #[test]
    fn thorough_and_failed_gate_status() {
        let fixture = Fixture::new();
        let mut runner = MockRunner::returning(7);
        let status = check(&fixture.runtime, &fixture.name, true, &mut runner).unwrap();
        assert_eq!(status, 7);
        assert_eq!(runner.last_arguments(), ["--thorough"]);
    }

    #[test]
    fn bad_names_never_launch() {
        let fixture = Fixture::new();
        let mut runner = MockRunner::returning(0);
        for name in [
            "../escape".to_owned(),
            "/absolute".to_owned(),
            String::new(),
            format!("{}/nested", fixture.name),
        ] {
            assert!(
                check(&fixture.runtime, &name, false, &mut runner).is_err(),
                "{name}"
            );
        }
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn no_home_manager_never_launches() {
        let mut fixture = Fixture::new();
        fixture.manifest["homeManager"] = Value::Null;
        fixture.save();
        let mut runner = MockRunner::returning(0);
        let error = message(check(&fixture.runtime, &fixture.name, false, &mut runner));
        assert!(error.contains("Home Manager"), "{error}");
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn manifest_paths_are_not_commands() {
        let mut fixture = Fixture::new();
        fixture.manifest["homeManager"] = json!("$(false)");
        fixture.save();
        let mut runner = MockRunner::returning(0);
        assert!(check(&fixture.runtime, &fixture.name, false, &mut runner).is_err());
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn mismatched_generation_never_launches() {
        let fixture = Fixture::new();
        fs::write(
            fixture.candidate.join("generation"),
            format!("/nix/store/{}-other\n", "c".repeat(32)),
        )
        .unwrap();
        let mut runner = MockRunner::returning(0);
        let error = message(check(&fixture.runtime, &fixture.name, false, &mut runner));
        assert!(error.contains("does not match"), "{error}");
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn system_secrets_precede_home_activation() {
        let mut fixture = Fixture::new();
        let secrets = format!(
            "/nix/store/{}-system-secrets/bin/activate-secrets",
            "d".repeat(32)
        );
        fixture.manifest["systemSecrets"] = json!(secrets);
        fixture.save();
        let mut runner = MockRunner::returning(0);
        assert_eq!(do_switch(&fixture, &mut runner).unwrap(), 0);
        assert_eq!(
            runner.last_arguments(),
            [
                "--thorough".to_owned(),
                secrets.clone(),
                format!("{}/activate", fixture.home),
                fixture.home.clone(),
                "--thorough".to_owned(),
            ]
        );
        let state = fixture.read_json("system-state.json");
        fs::write(
            fixture.path("system-pending.json"),
            json!({ "before": state }).to_string(),
        )
        .unwrap();
        let mut recovery = MockRunner::returning(0);
        assert_eq!(recover(&fixture.runtime, &mut recovery).unwrap(), 0);
        assert_eq!(
            recovery.last_arguments(),
            [
                secrets,
                format!("{}/activate", fixture.home),
                fixture.home.clone()
            ]
        );
    }

    #[test]
    fn system_secrets_failure_preserves_journal_without_home_mutation() {
        let mut fixture = Fixture::new();
        fixture.manifest["systemSecrets"] = json!(format!(
            "/nix/store/{}-system-secrets/bin/activate-secrets",
            "d".repeat(32)
        ));
        fixture.save();
        let mut runner = MockRunner::statuses(&[0, 7]);
        let error = message(do_switch(&fixture, &mut runner));
        assert!(
            error.contains("System secrets activation failed"),
            "{error}"
        );
        assert_eq!(runner.calls.len(), 2);
        assert!(fixture.exists("system-pending.json"));
        assert!(!fixture.exists("current-system"));
        let mut recovery = MockRunner::returning(0);
        assert_eq!(recover(&fixture.runtime, &mut recovery).unwrap(), 0);
        assert_eq!(
            recovery.last_arguments(),
            [
                format!("{}/activate", fixture.baseline),
                fixture.baseline.clone()
            ]
        );
    }

    #[test]
    fn invalid_system_secrets_never_launch() {
        let mut fixture = Fixture::new();
        let values = [
            json!("$(false)"),
            json!("/bin/activate-secrets"),
            json!(format!("{}/activate", fixture.home)),
            json!({}),
            json!(7),
        ];
        for value in values {
            fixture.manifest["systemSecrets"] = value.clone();
            fixture.save();
            let mut runner = MockRunner::returning(0);
            let error = message(check(&fixture.runtime, &fixture.name, false, &mut runner));
            assert!(error.contains("system secrets"), "{value}: {error}");
            assert!(runner.calls.is_empty());
        }
    }

    #[test]
    fn unsupported_manifest() {
        let mut fixture = Fixture::new();
        fixture.manifest["runtime"] = json!("other");
        fixture.save();
        let error = message(check(
            &fixture.runtime,
            &fixture.name,
            false,
            &mut MockRunner::returning(0),
        ));
        assert!(error.contains("unsupported"), "{error}");
        for (key, value) in [("formatVersion", json!(2)), ("stateVersion", json!(1))] {
            let mut fixture = Fixture::new();
            fixture.manifest[key] = value;
            fixture.save();
            assert!(
                check(
                    &fixture.runtime,
                    &fixture.name,
                    false,
                    &mut MockRunner::returning(0)
                )
                .is_err()
            );
        }
    }

    #[test]
    fn symlinked_candidate() {
        let fixture = Fixture::new();
        let target = fixture.path("retained");
        fs::rename(&fixture.candidate, &target).unwrap();
        symlink(&target, &fixture.candidate).unwrap();
        let error = message(check(
            &fixture.runtime,
            &fixture.name,
            false,
            &mut MockRunner::returning(0),
        ));
        assert!(error.contains("symlink"), "{error}");
    }

    #[test]
    fn symlinked_manifest_is_rejected() {
        let fixture = Fixture::new();
        let target = fixture.path("elsewhere.json");
        fs::rename(fixture.candidate.join("manifest.json"), &target).unwrap();
        symlink(&target, fixture.candidate.join("manifest.json")).unwrap();
        assert!(candidate_manifest(&fixture.runtime, &fixture.name).is_err());
    }

    #[test]
    fn switch_checks_activates_checks_then_publishes() {
        let fixture = Fixture::new();
        let runtime = fixture.runtime.clone();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let record = Arc::clone(&seen);
        let mut runner = MockRunner::returning(0).with_hook(move |index, command| {
            assert!(!runtime.join("current-system").exists());
            if index == 1 {
                let pending: Value =
                    serde_json::from_slice(&fs::read(runtime.join("system-pending.json")).unwrap())
                        .unwrap();
                assert_eq!(pending["phase"], "activating");
            }
            record.lock().unwrap().push(command.to_vec());
        });
        assert_eq!(do_switch(&fixture, &mut runner).unwrap(), 0);
        let calls = seen.lock().unwrap();
        assert_eq!(calls.len(), 4);
        assert_eq!(
            calls[1].last().unwrap(),
            &format!("{}/activate", fixture.home)
        );
        assert_eq!(calls[2].last().unwrap(), &fixture.home);
        assert_eq!(
            fixture.read("current-system"),
            format!("{}\n", fixture.name)
        );
        assert_eq!(
            fixture.read_json("system-state.json")["previousHomeManager"],
            fixture.baseline
        );
        assert!(!fixture.exists("system-pending.json"));
        assert_eq!(
            fs::read_link(fixture.path("root/nix/var/nix/gcroots/termuxpp-system-baseline"))
                .unwrap(),
            Path::new(&fixture.baseline)
        );
    }

    #[test]
    fn state_file_is_canonical_json() {
        let fixture = Fixture::new();
        do_switch(&fixture, &mut MockRunner::returning(0)).unwrap();
        assert_eq!(
            fixture.read("system-state.json"),
            format!(
                "{{\"current\": \"{}\", \"homeManager\": \"{}\", \"previous\": null, \"previousHomeManager\": \"{}\"}}\n",
                fixture.name, fixture.home, fixture.baseline
            )
        );
    }

    #[test]
    fn switch_requires_available_baseline() {
        let fixture = Fixture::new();
        let missing = format!("/nix/store/{}-missing", "d".repeat(32));
        for baseline in [None, Some("/tmp/not-store"), Some(missing.as_str())] {
            let mut runner = MockRunner::returning(0);
            let result = switch(&fixture.runtime, &fixture.name, baseline, &mut runner, None);
            assert!(result.is_err(), "{baseline:?}");
            assert!(runner.calls.is_empty());
        }
        assert!(!fixture.exists("root/nix/var/nix/gcroots/termuxpp-system-baseline"));
    }

    #[test]
    fn baseline_gc_root_must_match() {
        let fixture = Fixture::new();
        let root = fixture.path("root/nix/var/nix/gcroots/termuxpp-system-baseline");
        symlink(format!("/nix/store/{}-other", "d".repeat(32)), &root).unwrap();
        let mut runner = MockRunner::returning(0);
        let error = message(do_switch(&fixture, &mut runner));
        assert!(error.contains("baseline GC root"), "{error}");
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn previous_home_manager_only_for_first_migration() {
        let fixture = Fixture::new();
        do_switch(&fixture, &mut MockRunner::returning(0)).unwrap();
        let state = read_state(&fixture.runtime).unwrap().unwrap();
        let mut runner = MockRunner::returning(0);
        let error = message(switch(
            &fixture.runtime,
            &fixture.name,
            Some(&fixture.baseline),
            &mut runner,
            Some(&state),
        ));
        assert!(error.contains("first migration"), "{error}");
    }

    #[test]
    fn selecting_the_current_system_is_a_noop() {
        let fixture = Fixture::new();
        do_switch(&fixture, &mut MockRunner::returning(0)).unwrap();
        let mut runner = MockRunner::returning(0);
        let status = switch(&fixture.runtime, &fixture.name, None, &mut runner, None).unwrap();
        assert_eq!(status, 0);
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn failed_preflight_never_activates_or_selects() {
        let fixture = Fixture::new();
        let mut runner = MockRunner::returning(7);
        assert_eq!(do_switch(&fixture, &mut runner).unwrap(), 7);
        assert_eq!(runner.calls.len(), 1);
        assert!(!fixture.exists("current-system"));
        assert!(!fixture.exists("system-pending.json"));
    }

    #[test]
    fn failed_activation_retains_recovery_journal() {
        let fixture = Fixture::new();
        let error = message(do_switch(&fixture, &mut MockRunner::statuses(&[0, 7])));
        assert!(error.contains("recovery is required"), "{error}");
        assert!(fixture.exists("system-pending.json"));
        assert!(!fixture.exists("current-system"));
        let error = message(do_switch(&fixture, &mut MockRunner::returning(0)));
        assert!(error.contains("recover first"), "{error}");
    }

    #[test]
    fn recover_reactivates_baseline_without_candidate_selection() {
        let fixture = Fixture::new();
        assert!(do_switch(&fixture, &mut MockRunner::statuses(&[0, 7])).is_err());
        let mut runner = MockRunner::returning(0);
        assert_eq!(recover(&fixture.runtime, &mut runner).unwrap(), 0);
        let activate = vec![format!("{}/activate", fixture.baseline)];
        let profile = [
            "/bin/sh",
            "-c",
            PROFILE_SET,
            "profile-set",
            fixture.baseline.as_str(),
        ]
        .map(str::to_owned);
        assert_eq!(
            runner
                .calls
                .iter()
                .map(|(command, _)| command.clone())
                .collect::<Vec<_>>(),
            vec![
                session_command(&fixture.runtime, None, &activate).unwrap(),
                session_command(&fixture.runtime, None, &profile).unwrap(),
            ]
        );
        assert_eq!(fixture.read("current-system"), "\n");
        assert!(!fixture.exists("system-pending.json"));
    }

    #[test]
    fn recover_without_a_journal_is_an_error() {
        let fixture = Fixture::new();
        let error = message(recover(&fixture.runtime, &mut MockRunner::returning(0)));
        assert!(error.contains("no unfinished activation"), "{error}");
    }

    #[test]
    fn failed_recovery_retains_journal() {
        let fixture = Fixture::new();
        assert!(do_switch(&fixture, &mut MockRunner::statuses(&[0, 7])).is_err());
        assert!(recover(&fixture.runtime, &mut MockRunner::returning(7)).is_err());
        assert!(fixture.exists("system-pending.json"));
    }

    #[test]
    fn postcheck_failure_requires_recovery() {
        let fixture = Fixture::new();
        let error = message(do_switch(
            &fixture,
            &mut MockRunner::statuses(&[0, 0, 0, 7]),
        ));
        assert!(error.contains("post-activation"), "{error}");
        assert!(fixture.exists("system-pending.json"));
        assert!(!fixture.exists("current-system"));
    }

    #[test]
    fn profile_is_set_by_upstream_nix_env_with_positional_store_path() {
        let fixture = Fixture::new();
        let mut runner = MockRunner::returning(0);
        assert_eq!(do_switch(&fixture, &mut runner).unwrap(), 0);
        let profile = [
            "/bin/sh",
            "-c",
            PROFILE_SET,
            "profile-set",
            fixture.home.as_str(),
        ]
        .map(str::to_owned);
        assert_eq!(
            runner.command(2),
            &session_command(&fixture.runtime, Some(&fixture.name), &profile).unwrap()
        );
        assert!(!PROFILE_SET.contains(&fixture.home));
        assert_eq!(
            PROFILE_SET,
            "exec nix-env --profile \"${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager\" --set \"$1\""
        );
        assert_eq!(runner.calls[2].1, Duration::from_secs(300));
        assert_eq!(runner.calls[1].1, Duration::from_secs(1800));
    }

    #[test]
    fn failed_profile_sync_retains_journal_and_recovery_restores_old_profile() {
        let fixture = Fixture::new();
        let mut runner = MockRunner::statuses(&[0, 0, 7]);
        let error = message(do_switch(&fixture, &mut runner));
        assert!(
            error.contains("profile synchronization failed")
                && error.contains("recovery is required"),
            "{error}"
        );
        assert_eq!(runner.calls.len(), 3);
        assert_eq!(
            fixture.read_json("system-pending.json")["phase"],
            "activating"
        );
        assert!(!fixture.exists("current-system"));
        let mut recovery = MockRunner::returning(0);
        assert_eq!(recover(&fixture.runtime, &mut recovery).unwrap(), 0);
        assert_eq!(
            recovery.last_arguments(),
            [
                format!("{}/activate", fixture.baseline),
                fixture.baseline.clone()
            ]
        );
        let last = recovery.command(1);
        assert_eq!(
            &last[last.len() - 4..last.len() - 1],
            ["-c", PROFILE_SET, "profile-set"]
        );
        assert!(!fixture.exists("system-pending.json"));
    }

    #[test]
    fn failed_profile_sync_during_recovery_retains_journal() {
        let fixture = Fixture::new();
        assert!(do_switch(&fixture, &mut MockRunner::statuses(&[0, 7])).is_err());
        let error = message(recover(
            &fixture.runtime,
            &mut MockRunner::statuses(&[0, 7]),
        ));
        assert!(error.contains("profile synchronization"), "{error}");
        assert!(fixture.exists("system-pending.json"));
        assert!(!fixture.exists("current-system"));
    }

    #[test]
    fn interrupt_leaves_recovery_journal() {
        for outcome in [Outcome::Interrupted, Outcome::Terminated, Outcome::TimedOut] {
            let fixture = Fixture::new();
            let mut runner = MockRunner::script(vec![Outcome::Status(0), outcome]);
            let error = do_switch(&fixture, &mut runner).unwrap_err();
            assert!(!matches!(error, Error::Invalid(_)), "{error}");
            assert!(fixture.exists("system-pending.json"));
        }
    }

    #[test]
    fn rollback_to_baseline_then_forward_to_retained_system() {
        let fixture = Fixture::new();
        do_switch(&fixture, &mut MockRunner::returning(0)).unwrap();
        let mut runner = MockRunner::returning(0);
        assert_eq!(rollback(&fixture.runtime, &mut runner).unwrap(), 0);
        assert!(runner.command(0).contains(&"--legacy".to_owned()));
        assert_eq!(fixture.read("current-system"), "\n");
        assert_eq!(
            rollback(&fixture.runtime, &mut MockRunner::returning(0)).unwrap(),
            0
        );
        assert_eq!(
            fixture.read("current-system"),
            format!("{}\n", fixture.name)
        );
    }

    #[test]
    fn rollback_without_retained_generation_is_an_error() {
        let fixture = Fixture::new();
        let error = message(rollback(&fixture.runtime, &mut MockRunner::returning(0)));
        assert!(error.contains("no previous generation"), "{error}");
    }

    #[test]
    fn rollback_refuses_an_unfinished_activation() {
        let fixture = Fixture::new();
        do_switch(&fixture, &mut MockRunner::returning(0)).unwrap();
        fs::write(fixture.path("system-pending.json"), "{}").unwrap();
        let error = message(rollback(&fixture.runtime, &mut MockRunner::returning(0)));
        assert!(error.contains("recover first"), "{error}");
    }

    #[test]
    fn generation_listing_marks_selected_system() {
        let fixture = Fixture::new();
        do_switch(&fixture, &mut MockRunner::returning(0)).unwrap();
        fs::create_dir(fixture.path("system-candidates/.prepare-stage")).unwrap();
        fs::File::options()
            .write(true)
            .open(fixture.path(&format!("system-candidates/{}/generation", fixture.name)))
            .unwrap()
            .set_modified(UNIX_EPOCH + Duration::from_secs(1))
            .unwrap();
        assert_eq!(
            generations(&fixture.runtime).unwrap(),
            vec![Generation {
                number: Some(1),
                date: Some("1970-01-01 00:00:01Z".into()),
                generation: fixture.name.clone(),
                home_manager: fixture.home.clone(),
                current: true,
                previous: false,
            }]
        );
    }

    #[test]
    fn concurrent_controller_is_rejected() {
        let fixture = Fixture::new();
        let _held = FileLock::acquire(&fixture.path("system-control.lock")).unwrap();
        let error = do_switch(&fixture, &mut MockRunner::returning(0)).unwrap_err();
        assert!(error.is_would_block(), "{error}");
        assert!(
            recover(&fixture.runtime, &mut MockRunner::returning(0))
                .unwrap_err()
                .is_would_block()
        );
    }

    #[test]
    fn selection_publication_failure_can_recover() {
        let fixture = Fixture::new();
        // Publishing writes current-system first; a symlinked state temporary
        // makes the second write fail after the selection already changed.
        let blocker = fixture.path("system-state.json.new");
        symlink(fixture.path("elsewhere"), &blocker).unwrap();
        assert!(do_switch(&fixture, &mut MockRunner::returning(0)).is_err());
        assert_eq!(
            fixture.read("current-system"),
            format!("{}\n", fixture.name)
        );
        assert_eq!(
            fixture.read_json("system-pending.json")["phase"],
            "publishing"
        );
        fs::remove_file(&blocker).unwrap();
        assert_eq!(
            recover(&fixture.runtime, &mut MockRunner::returning(0)).unwrap(),
            0
        );
        assert_eq!(fixture.read("current-system"), "\n");
        assert!(!fixture.exists("system-pending.json"));
    }

    #[test]
    fn assembly_only_candidate_cannot_activate() {
        let mut fixture = Fixture::new();
        fixture.manifest["activationSupported"] = json!(false);
        fixture.save();
        let mut runner = MockRunner::returning(0);
        let error = message(do_switch(&fixture, &mut runner));
        assert!(error.contains("does not support"), "{error}");
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn special_generation_record_is_rejected_without_reading() {
        let fixture = Fixture::new();
        let record = fixture.candidate.join("generation");
        fs::remove_file(&record).unwrap();
        mkfifo(&record);
        let error = message(candidate_manifest(&fixture.runtime, &fixture.name));
        assert!(error.contains("generation record"), "{error}");
    }

    #[test]
    fn special_state_record_is_rejected_without_reading() {
        let fixture = Fixture::new();
        mkfifo(&fixture.path("system-state.json"));
        let error = message(read_state_value(&fixture.runtime, "system-state.json"));
        assert!(error.contains("not regular"), "{error}");
        assert!(generations(&fixture.runtime).is_err());
    }

    #[test]
    fn malformed_state_is_rejected() {
        let fixture = Fixture::new();
        for text in ["[]", "{}", "{\"current\": 3}", "{\"current\": null}"] {
            fs::write(fixture.path("system-state.json"), text).unwrap();
            assert!(read_state(&fixture.runtime).is_err(), "{text}");
        }
    }

    #[test]
    fn stale_rollback_state_is_rejected() {
        let fixture = Fixture::new();
        let stale = State {
            current: Some("stale".to_owned()),
            home_manager: None,
            previous: None,
            previous_home_manager: None,
        };
        let mut runner = MockRunner::returning(0);
        let error = message(switch(
            &fixture.runtime,
            &fixture.name,
            None,
            &mut runner,
            Some(&stale),
        ));
        assert!(error.contains("state changed"), "{error}");
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn management_allowlist_rejects_arbitrary_commands() {
        let fixture = Fixture::new();
        let requests = [
            json!({"command": "exec", "candidate": fixture.name}),
            json!({"command": "list-generations", "argv": ["sh"]}),
            json!({"command": "switch", "candidate": "../escape"}),
            json!({"command": "switch"}),
            json!({"command": "check", "candidate": 7}),
            json!({"command": "rollback", "candidate": fixture.name}),
            json!({"command": 7}),
            json!({}),
            json!(null),
            json!([]),
        ];
        for request in requests {
            let mut runner = MockRunner::returning(0);
            assert!(
                dispatch(&fixture.runtime, &request, &mut runner).is_err(),
                "{request}"
            );
            assert!(runner.calls.is_empty());
        }
    }

    #[test]
    fn management_switch_dispatches_only_selected_candidate() {
        let fixture = Fixture::new();
        let state = State {
            current: None,
            home_manager: Some(fixture.baseline.clone()),
            previous: None,
            previous_home_manager: None,
        };
        write_json(&fixture.runtime, STATE_FILE, &state).unwrap();
        let mut runner = MockRunner::returning(7);
        let response = dispatch(
            &fixture.runtime,
            &json!({"command": "switch", "candidate": fixture.name}),
            &mut runner,
        )
        .unwrap();
        assert_eq!(response, json!({"status": 7}));
        assert_eq!(runner.calls.len(), 1);
    }

    #[test]
    fn management_check_is_always_thorough() {
        let fixture = Fixture::new();
        let mut runner = MockRunner::returning(3);
        let response = dispatch(
            &fixture.runtime,
            &json!({"command": "check", "candidate": fixture.name}),
            &mut runner,
        )
        .unwrap();
        assert_eq!(response, json!({"status": 3}));
        assert_eq!(runner.last_arguments(), ["--thorough"]);
    }

    #[test]
    fn management_lists_generations() {
        let fixture = Fixture::new();
        let response = dispatch(
            &fixture.runtime,
            &json!({"command": "list-generations"}),
            &mut MockRunner::returning(0),
        )
        .unwrap();
        assert_eq!(response["status"], 0);
        assert_eq!(response["generations"][0]["generation"], fixture.name);
    }

    #[test]
    fn exit_codes_follow_the_shell_convention() {
        assert_eq!(exit_code(0), 0);
        assert_eq!(exit_code(7), 7);
        assert_eq!(exit_code(-9), 137);
        assert_eq!(exit_code(-15), 143);
        assert_eq!(exit_code(256), 0);
    }
}

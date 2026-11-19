//! The guest side: candidate preparation, remote builds and the controller
//! client.
//!
//! Nothing here activates Home Manager or selects a system; that is the
//! native controller's job and is only requested over the management socket.

use crate::controller::Generation;
use crate::error::{Error, Result};
use crate::fsutil::{canonical_json, is_symlink, path_str, read_bounded};
use crate::store::{guest_store_path, is_candidate_name, is_host_name, is_user_name};
use serde::Deserialize;
use serde_json::{Map, Value};
use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt, symlink};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// A switch can run a full check, an activation and a second check.
const MANAGE_TIMEOUT: Duration = Duration::from_secs(4500);
/// Largest accepted controller response, including the newline.
const RESPONSE_LIMIT: usize = 65536;
const MANIFEST_LIMIT: u64 = 1 << 20;
pub(crate) const GCROOTS: &str = "root/nix/var/nix/gcroots/termuxpp-system-candidates";

/// Candidate names are store basenames; nothing else may reach the socket.
pub fn validate_candidate(name: &str) -> Result<()> {
    if is_candidate_name(name) {
        Ok(())
    } else {
        Err(Error::invalid("invalid system candidate name"))
    }
}

/// Send one request to the native controller and return its response.
///
/// A non-zero controller status is turned into an error carrying the
/// controller's message.
pub fn manage(socket: &Path, command: &str, candidate: Option<&str>) -> Result<Value> {
    let mut request = Map::new();
    request.insert("command".to_owned(), Value::String(command.to_owned()));
    if let Some(candidate) = candidate {
        validate_candidate(candidate)?;
        request.insert("candidate".to_owned(), Value::String(candidate.to_owned()));
    }
    let mut stream = UnixStream::connect(socket).map_err(|error| {
        Error::invalid(format!(
            "cannot reach the native controller at {}: {error}",
            socket.display()
        ))
    })?;
    stream.set_read_timeout(Some(MANAGE_TIMEOUT))?;
    stream.set_write_timeout(Some(MANAGE_TIMEOUT))?;
    stream.write_all((canonical_json(&Value::Object(request)) + "\n").as_bytes())?;
    let invalid = || Error::invalid("invalid native controller response");
    let mut payload = Vec::new();
    let mut chunk = vec![0u8; RESPONSE_LIMIT + 1];
    while !payload.ends_with(b"\n") {
        let wanted = RESPONSE_LIMIT + 1 - payload.len();
        let count = match stream.read(&mut chunk[..wanted]) {
            Ok(count) => count,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(error.into()),
        };
        if count == 0 || payload.len() + count > RESPONSE_LIMIT {
            return Err(invalid());
        }
        payload.extend_from_slice(&chunk[..count]);
    }
    let response: Value = serde_json::from_slice(&payload).map_err(|_| invalid())?;
    let status = response
        .as_object()
        .and_then(|object| object.get("status"))
        .and_then(Value::as_i64)
        .ok_or_else(|| Error::invalid("invalid native controller status"))?;
    if status != 0 {
        return Err(Error::invalid(
            response.get("error").and_then(Value::as_str).map_or_else(
                || format!("native controller failed with status {status}"),
                str::to_owned,
            ),
        ));
    }
    Ok(response)
}

/// The `generations` array of a `list-generations` response.
pub fn generations(response: &Value) -> Result<Vec<Generation>> {
    let list = response
        .get("generations")
        .ok_or_else(|| Error::invalid("invalid native controller response"))?;
    serde_json::from_value(list.clone())
        .map_err(|_| Error::invalid("invalid native controller response"))
}

fn store_value(value: Option<&Value>, check: &dyn Fn(&str) -> Result<()>) -> Result<String> {
    let text = value
        .and_then(Value::as_str)
        .ok_or_else(|| Error::invalid("invalid guest store path"))?;
    check(text)?;
    Ok(text.to_owned())
}

fn create_private_dir(path: &Path) -> Result<()> {
    match DirBuilder::new().mode(0o700).create(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists && path.is_dir() => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn write_private(path: &Path, text: &str) -> Result<()> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(text.as_bytes())?;
    Ok(())
}

fn copy_file(source: &Path, destination: &Path) -> Result<()> {
    fs::copy(source, destination)?;
    fs::set_permissions(destination, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

// The native launcher reads this file before the guest store is mounted.
const NATIVE_ETC_FILES: &[&str] = &["termuxpp-release"];

/// Overlay regular files while refusing directory symlinks, special files and
/// dangling links.
fn install_etc_tree(
    source: &Path,
    target: &Path,
    install_file: &impl Fn(&Path, &Path) -> Result<()>,
) -> Result<()> {
    let mut entries = fs::read_dir(source)?.collect::<io::Result<Vec<_>>>()?;
    entries.sort_by_key(|entry| entry.file_name());
    for entry in entries {
        let path = entry.path();
        let destination = target.join(entry.file_name());
        let kind = fs::metadata(&path).ok();
        if kind.as_ref().is_some_and(fs::Metadata::is_dir) {
            if is_symlink(&path) {
                return Err(Error::invalid(
                    "configuration directory symlinks are not supported",
                ));
            }
            if destination.exists() && !destination.is_dir() {
                return Err(Error::invalid(
                    "configuration directory conflicts with an existing file",
                ));
            }
            create_private_dir(&destination)?;
            install_etc_tree(&path, &destination, install_file)?;
        } else if kind.as_ref().is_some_and(fs::Metadata::is_file) {
            if destination.is_dir() {
                return Err(Error::invalid(
                    "configuration file conflicts with an existing directory",
                ));
            }
            install_file(&path, &destination)?;
        } else {
            return Err(Error::invalid(
                "configuration contains a special or dangling file",
            ));
        }
    }
    Ok(())
}

static STAGE_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Create a fresh private `.prepare-*` directory inside `parent`.
fn make_stage(parent: &Path) -> Result<PathBuf> {
    for _ in 0..100 {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.subsec_nanos());
        let path = parent.join(format!(
            ".prepare-{:x}-{:x}-{}",
            std::process::id(),
            nanos,
            STAGE_COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        match DirBuilder::new().mode(0o700).create(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
            Err(error) => return Err(error.into()),
        }
    }
    Err(Error::invalid("cannot create a staging directory"))
}

/// Prepare a candidate in the runtime without selecting or activating it.
pub fn prepare(runtime: &Path, generation: &Path) -> Result<PathBuf> {
    prepare_with(runtime, generation, &guest_store_path)
}

/// [`prepare`] with an injectable store-path check (tests use temporary
/// directories instead of real store paths).
pub fn prepare_with(
    runtime: &Path,
    generation: &Path,
    store_check: &dyn Fn(&str) -> Result<()>,
) -> Result<PathBuf> {
    let runtime = fs::canonicalize(runtime)?;
    let _lock = crate::fsutil::FileLock::acquire(&runtime.join(crate::controller::CONTROL_LOCK))?;
    let generation = fs::canonicalize(generation)?;
    store_check(&path_str(&generation)?)?;
    let data: Value = serde_json::from_slice(&read_bounded(
        &generation.join("manifest.json"),
        MANIFEST_LIMIT,
    )?)?;
    let field = |key: &str| data.get(key);
    if field("formatVersion").and_then(Value::as_i64) != Some(1)
        || field("stateVersion").and_then(Value::as_str) != Some("1")
        || field("runtime").and_then(Value::as_str) != Some("droid-nix")
    {
        return Err(Error::invalid("unsupported guest system manifest"));
    }
    let user = field("name")
        .and_then(Value::as_str)
        .filter(|user| is_user_name(user))
        .ok_or_else(|| Error::invalid("invalid guest identity"))?;
    let home = field("home")
        .and_then(Value::as_str)
        .filter(|home| *home == format!("/home/{user}"))
        .ok_or_else(|| Error::invalid("invalid guest identity"))?;
    for entry in ["passwd", "group"] {
        if fs::symlink_metadata(generation.join("etc").join(entry)).is_ok() {
            return Err(Error::invalid(
                "Android-owned passwd/group cannot be overridden by a candidate",
            ));
        }
    }
    let base: Value = serde_json::from_slice(&read_bounded(
        &runtime.join("session.json"),
        MANIFEST_LIMIT,
    )?)?;
    if base.get("schema").and_then(Value::as_i64) != Some(1)
        || base.get("system").and_then(Value::as_str) != Some("aarch64-linux")
        || base.get("pageSize").and_then(Value::as_i64) != Some(4096)
    {
        return Err(Error::invalid("unsupported base runtime"));
    }
    let passwd = fs::read_to_string(runtime.join("root/etc/passwd"))?;
    let records: Vec<Vec<&str>> = passwd
        .lines()
        .map(|line| line.split(':').collect::<Vec<_>>())
        .filter(|fields| fields[0] == user)
        .collect();
    if records.len() != 1 || records[0].len() != 7 || records[0][5] != home {
        return Err(Error::invalid(
            "candidate identity does not match the prepared runtime",
        ));
    }
    let session = field("session");
    let session_value = |key: &str| session.and_then(|session| session.get(key));
    let system_path = store_value(field("systemPath"), store_check)?;
    let values = [
        user.to_owned(),
        home.to_owned(),
        system_path + "/bin",
        store_value(session_value("shell"), store_check)?,
        store_value(session_value("certificate"), store_check)?,
        store_value(session_value("terminfo"), store_check)?,
    ];
    if values[2..].iter().any(|path| !Path::new(path).exists()) {
        return Err(Error::invalid("candidate closure is not fully available"));
    }
    if let Some(manager) = field("homeManager").filter(|value| !value.is_null()) {
        let manager = store_value(Some(manager), store_check)?;
        if !Path::new(&manager).join("activate").is_file() {
            return Err(Error::invalid(
                "associated Home Manager generation is unavailable",
            ));
        }
    }
    let candidates = runtime.join("system-candidates");
    if is_symlink(&candidates) {
        return Err(Error::invalid("candidate directory must not be a symlink"));
    }
    create_private_dir(&candidates)?;
    let name = generation
        .file_name()
        .ok_or_else(|| Error::invalid("invalid guest store path"))?;
    let destination = candidates.join(name);
    if fs::symlink_metadata(&destination).is_ok() {
        return Err(Error::invalid(
            "candidate already exists; retained candidates are never overwritten",
        ));
    }
    let stage = make_stage(&candidates)?;
    let staged = stage_candidate(&runtime, &generation, &stage, &data, &values, &destination);
    if staged.is_err() {
        let _ = fs::remove_dir_all(&stage);
    }
    staged?;
    Ok(destination)
}

fn stage_candidate(
    runtime: &Path,
    generation: &Path,
    stage: &Path,
    data: &Value,
    values: &[String; 6],
    destination: &Path,
) -> Result<()> {
    let etc = stage.join("etc");
    create_private_dir(&etc)?;
    install_etc_tree(&runtime.join("root/etc"), &etc, &copy_file)?;
    install_etc_tree(&generation.join("etc"), &etc, &|source, destination| {
        if NATIVE_ETC_FILES
            .iter()
            .any(|name| destination == etc.join(name))
        {
            return copy_file(source, destination);
        }
        if destination.exists() {
            fs::remove_file(destination)?;
        }
        symlink(source, destination)?;
        Ok(())
    })?;
    // Android owns numeric credentials; a generation may not replace them.
    for entry in ["passwd", "group"] {
        copy_file(&runtime.join("root/etc").join(entry), &etc.join(entry))?;
    }
    write_private(&stage.join("session"), &(values.join("\n") + "\n"))?;
    write_private(&stage.join("generation"), &(path_str(generation)? + "\n"))?;
    write_private(&stage.join("manifest.json"), &(canonical_json(data) + "\n"))?;
    let roots = runtime.join(GCROOTS);
    if is_symlink(&roots) {
        return Err(Error::invalid(
            "candidate GC root directory must not be a symlink",
        ));
    }
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&roots)?;
    let root = roots.join(destination.file_name().unwrap_or_default());
    symlink(generation, &root)?;
    if let Err(error) = fs::rename(stage, destination) {
        let _ = fs::remove_file(&root);
        return Err(error.into());
    }
    Ok(())
}

/// Runs a build command and returns what it printed on stdout.
pub trait Builder {
    fn output(&mut self, command: &[String]) -> Result<String>;
}

fn diff_endpoints(
    generations: &[Generation],
    from: Option<&str>,
    to: Option<&str>,
) -> Result<(String, String)> {
    let find = |selector: &str| {
        let number = selector.parse::<usize>().ok();
        generations
            .iter()
            .find(|generation| {
                generation.generation == selector
                    || number.is_some_and(|number| generation.number == Some(number))
            })
            .map(|generation| generation.generation.clone())
            .ok_or_else(|| Error::invalid(format!("unknown system generation: {selector}")))
    };
    match (from, to) {
        (Some(from), Some(to)) => Ok((find(from)?, find(to)?)),
        (None, None) => {
            let previous = generations
                .iter()
                .find(|generation| generation.previous)
                .ok_or_else(|| Error::invalid("no previous system generation is retained"))?;
            let current = generations
                .iter()
                .find(|generation| generation.current)
                .ok_or_else(|| Error::invalid("no active system generation"))?;
            Ok((previous.generation.clone(), current.generation.clone()))
        }
        _ => Err(Error::invalid("diff takes two generation selectors")),
    }
}

#[cfg(test)]
#[test]
fn closure_diff_defaults_to_previous_then_active() {
    let generations = [false, true].map(|current| Generation {
        number: Some(if current { 3 } else { 2 }),
        date: None,
        generation: if current { "active" } else { "previous" }.into(),
        home_manager: String::new(),
        current,
        previous: !current,
    });
    assert_eq!(
        diff_endpoints(&generations, None, None).unwrap(),
        ("previous".into(), "active".into())
    );
    assert_eq!(
        diff_endpoints(&generations, Some("3"), Some("previous")).unwrap(),
        ("active".into(), "previous".into())
    );
}

pub enum DiffFormat {
    Nix,
    Dix { color: bool },
}

/// Compare retained closures under the controller lock so neither candidate
/// can be pruned while the diff reads the graphs.
pub fn diff_generations(
    runtime: &Path,
    from: Option<&str>,
    to: Option<&str>,
    format: DiffFormat,
    builder: &mut dyn Builder,
) -> Result<(String, String, String)> {
    let _lock = crate::fsutil::FileLock::acquire(&runtime.join(crate::controller::CONTROL_LOCK))?;
    let (from, to) = diff_endpoints(&crate::controller::generations(runtime)?, from, to)?;
    let mut command = match format {
        DiffFormat::Nix => vec!["nix".into(), "store".into(), "diff-closures".into()],
        DiffFormat::Dix { color } => {
            let mut args = vec![
                option_env!("NIXPP_DIX").unwrap_or("dix").into(),
                if color {
                    "--color=always"
                } else {
                    "--color=never"
                }
                .into(),
            ];
            let verb = if option_env!("NIXPP_DIX_LEGACY") == Some("1") {
                "--force-correctness"
            } else {
                "diff"
            };
            args.push(verb.into());
            args
        }
    };
    command.extend([format!("/nix/store/{from}"), format!("/nix/store/{to}")]);
    let diff = builder.output(&command)?;
    Ok((from, to, diff))
}

/// The real builder: stdout is captured, stdin and stderr stay attached so
/// that remote build progress remains visible.
#[derive(Debug, Default)]
pub struct ProcessBuilder;

impl Builder for ProcessBuilder {
    fn output(&mut self, command: &[String]) -> Result<String> {
        let (program, arguments) = command
            .split_first()
            .ok_or_else(|| Error::invalid("empty command"))?;
        let output = Command::new(program)
            .args(arguments)
            .stdin(Stdio::inherit())
            .stderr(Stdio::inherit())
            .output()
            .map_err(|error| Error::invalid(format!("cannot run {program}: {error}")))?;
        if !output.status.success() {
            return Err(Error::invalid(format!(
                "{program} failed ({})",
                output.status
            )));
        }
        String::from_utf8(output.stdout)
            .map_err(|_| Error::invalid("build output is not valid UTF-8"))
    }
}

/// The command line that builds the system of `host` without compiling on
/// the phone (`--max-jobs 0`, or through the disposable-worker integration).
pub fn build_command(flake: &str, host: &str, rworker: bool) -> Result<Vec<String>> {
    if !is_host_name(host) {
        return Err(Error::invalid("invalid system host name"));
    }
    if flake.is_empty() || flake.starts_with('-') || flake.contains('#') {
        return Err(Error::invalid(
            "supply a flake URI without an output fragment",
        ));
    }
    let target = format!("{flake}#termuxppConfigurations.{host}.system");
    let mut command: Vec<String> = if rworker {
        vec!["rworker-nix".to_owned(), "build".to_owned()]
    } else {
        ["nix", "build", "--max-jobs", "0"]
            .map(str::to_owned)
            .to_vec()
    };
    command.extend(["--no-link", "--print-out-paths"].map(str::to_owned));
    command.push(target);
    Ok(command)
}

#[derive(Debug, Deserialize)]
pub struct UpgradeTarget {
    pub flake: String,
    pub host: String,
    pub cache: Option<UpgradeCache>,
}

#[derive(Debug, Deserialize)]
pub struct UpgradeCache {
    pub store: String,
    pub pin_reader: PathBuf,
    pub public_keys: Vec<String>,
    pub credentials_file: Option<PathBuf>,
}

pub fn upgrade_target(
    config: &Path,
    flake: Option<String>,
    host: Option<String>,
) -> Result<UpgradeTarget> {
    if let (Some(flake), Some(host)) = (&flake, &host) {
        return Ok(UpgradeTarget {
            flake: flake.clone(),
            host: host.clone(),
            cache: None,
        });
    }
    let data = read_bounded(config, 4096)
        .map_err(|error| Error::invalid(format!("cannot read {}: {error}", config.display())))?;
    let defaults: UpgradeTarget = serde_json::from_slice(&data)
        .map_err(|error| Error::invalid(format!("invalid {}: {error}", config.display())))?;
    Ok(UpgradeTarget {
        flake: flake.unwrap_or(defaults.flake),
        host: host.unwrap_or(defaults.host),
        cache: defaults.cache,
    })
}

pub fn plan_upgrade(target: &UpgradeTarget, builder: &mut dyn Builder) -> Result<()> {
    let mut command = build_command(&target.flake, &target.host, false)?;
    command.splice(2..2, ["--refresh", "--dry-run"].map(str::to_owned));
    builder.output(&command)?;
    Ok(())
}

/// Resolve a host-specific pin and require Nix to verify it at the configured
/// cache, even when a path bearing the same name is already installed.
pub fn cached_upgrade(
    target: &UpgradeTarget,
    dry_run: bool,
    builder: &mut dyn Builder,
) -> Result<PathBuf> {
    let cache = target
        .cache
        .as_ref()
        .ok_or_else(|| Error::invalid("no binary cache configured for upgrades"))?;
    if !is_host_name(&target.host)
        || cache.public_keys.is_empty()
        || !cache.pin_reader.is_absolute()
    {
        return Err(Error::invalid("invalid binary cache configuration"));
    }

    let pin = builder.output(&[path_str(&cache.pin_reader)?.to_owned()])?;
    let path = pin.trim();
    let name = path.strip_prefix("/nix/store/").unwrap_or_default();
    if !is_candidate_name(name) || !name.ends_with(&format!("-termuxpp-system-{}", target.host)) {
        return Err(Error::invalid(
            "cache pin does not select this host's system",
        ));
    }
    let keys = cache.public_keys.join(" ");
    let credentials = cache
        .credentials_file
        .as_deref()
        .map(path_str)
        .transpose()?
        .map(|path| format!("AWS_SHARED_CREDENTIALS_FILE={path}"));
    let command = |arguments: &[&str]| {
        credentials
            .iter()
            .flat_map(|value| ["env", value.as_str()])
            .chain(["nix", "--refresh", "--option", "trusted-public-keys", &keys])
            .into_iter()
            .chain(arguments.iter().copied())
            .chain([path])
            .map(str::to_owned)
            .collect::<Vec<_>>()
    };
    let metadata = builder.output(&command(&[
        "path-info",
        "--json",
        "--json-format",
        "1",
        "--store",
        &cache.store,
    ]))?;
    let metadata: Value = serde_json::from_str(&metadata)?;
    let entry = &metadata[path];
    // Nix trusts content-addressed paths and ultimately trusted paths without
    // signatures. Neither is a signed release from this cache.
    if entry.get("ca") != Some(&Value::Null) || entry.get("ultimate") != Some(&Value::Bool(false)) {
        return Err(Error::invalid(
            "cache pin does not select a signed system release",
        ));
    }
    builder.output(&command(&[
        "store",
        "verify",
        "--store",
        &cache.store,
        "--no-contents",
        "--sigs-needed",
        "1",
    ]))?;
    if !dry_run {
        builder.output(&command(&[
            "copy",
            "--from",
            &cache.store,
            "--option",
            "require-sigs",
            "true",
        ]))?;
    }
    Ok(PathBuf::from(path))
}

pub fn probe_store(builder: &mut dyn Builder, store: Option<&str>) -> Result<()> {
    let mut command = ["timeout", "8", "nix", "store", "ping"]
        .map(str::to_owned)
        .to_vec();
    if let Some(store) = store {
        command.extend(["--store".to_owned(), store.to_owned()]);
    }
    builder.output(&command)?;
    Ok(())
}

pub fn probe_builders(builder: &mut dyn Builder) -> Result<()> {
    let config = builder.output(&["nix", "config", "show", "builders"].map(str::to_owned))?;
    let config = if let Some(path) = config.trim().strip_prefix('@') {
        String::from_utf8(read_bounded(Path::new(path), 65536)?)
            .map_err(|_| Error::invalid("builder list is not valid UTF-8"))?
    } else {
        config
    };
    let stores: std::collections::BTreeSet<_> = config
        .split([';', '\n'])
        .filter_map(|line| line.split_whitespace().next())
        .filter(|store| store.starts_with("ssh-ng://") || store.starts_with("ssh://"))
        .collect();
    if stores.is_empty() {
        return Err(Error::invalid("no remote SSH builders configured"));
    }
    let unavailable = std::thread::scope(|scope| {
        let tasks: Vec<_> = stores
            .into_iter()
            .map(|store| {
                (
                    store,
                    scope.spawn(move || probe_store(&mut ProcessBuilder, Some(store))),
                )
            })
            .collect();
        tasks
            .into_iter()
            .filter_map(|(store, task)| (!matches!(task.join(), Ok(Ok(())))).then_some(store))
            .collect::<Vec<_>>()
    });
    if !unavailable.is_empty() {
        return Err(Error::invalid(format!(
            "unreachable: {}",
            unavailable.join(", ")
        )));
    }
    Ok(())
}

pub fn build_upgrade(
    target: &UpgradeTarget,
    rworker: bool,
    builder: &mut dyn Builder,
) -> Result<PathBuf> {
    let mut command = build_command(&target.flake, &target.host, rworker)?;
    command.insert(2, "--refresh".to_owned());
    built_system(&command, builder)
}

/// Build the system of `host` and return its store path.
pub fn build_system(
    flake: &str,
    host: &str,
    rworker: bool,
    builder: &mut dyn Builder,
) -> Result<PathBuf> {
    built_system(&build_command(flake, host, rworker)?, builder)
}

fn built_system(command: &[String], builder: &mut dyn Builder) -> Result<PathBuf> {
    let output = builder.output(command)?;
    let mut paths = output.lines();
    let (Some(path), None) = (paths.next(), paths.next()) else {
        return Err(Error::invalid(
            "build did not return exactly one system generation",
        ));
    };
    guest_store_path(path)?;
    Ok(PathBuf::from(path))
}

/// The phases of [`rebuild`], reported as they begin.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    Build,
    Prepare,
    Switch,
}

/// Build, prepare (unless already retained) and switch to a system.
pub fn rebuild(
    runtime: &Path,
    socket: &Path,
    flake: &str,
    host: &str,
    rworker: bool,
    builder: &mut dyn Builder,
    on_stage: &mut dyn FnMut(Stage),
) -> Result<PathBuf> {
    on_stage(Stage::Build);
    let generation = build_system(flake, host, rworker, builder)?;
    activate_system(runtime, socket, &generation, on_stage)?;
    Ok(generation)
}

pub fn activate_system(
    runtime: &Path,
    socket: &Path,
    generation: &Path,
    on_stage: &mut dyn FnMut(Stage),
) -> Result<()> {
    let name = generation
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| Error::invalid("invalid guest store path"))?
        .to_owned();
    if !runtime.join("system-candidates").join(&name).exists() {
        on_stage(Stage::Prepare);
        prepare(runtime, generation)?;
    }
    on_stage(Stage::Switch);
    manage(socket, "switch", Some(&name))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::ffi::CString;
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::net::UnixListener;
    use std::thread::{self, JoinHandle};

    fn message<T: std::fmt::Debug>(result: Result<T>) -> String {
        result.unwrap_err().to_string()
    }

    struct Prepared {
        _dir: tempfile::TempDir,
        runtime: PathBuf,
        generation: PathBuf,
        data: Value,
    }

    impl Prepared {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let root = fs::canonicalize(dir.path()).unwrap();
            let runtime = root.join("runtime");
            let generation = root.join(format!("{}-termuxpp-system-test", "a".repeat(32)));
            for path in [
                runtime.join("root/etc"),
                generation.join("etc/nested"),
                generation.join("sw/bin"),
                generation.join("terminfo"),
            ] {
                fs::create_dir_all(path).unwrap();
            }
            let write = |path: PathBuf, text: &str| fs::write(path, text).unwrap();
            write(
                runtime.join("session.json"),
                r#"{"schema": 1, "system": "aarch64-linux", "pageSize": 4096}"#,
            );
            write(
                runtime.join("root/etc/passwd"),
                "guest:x:123:456:Guest:/home/guest:/bin/sh\n",
            );
            write(runtime.join("root/etc/group"), "guest:x:456:\n");
            write(
                runtime.join("root/etc/resolv.conf"),
                "nameserver 127.0.0.1\n",
            );
            write(runtime.join("root/etc/example"), "old\n");
            write(generation.join("etc/example"), "new\n");
            write(generation.join("etc/nested/value"), "nested\n");
            write(generation.join("shell"), "");
            write(generation.join("cert"), "");
            let text = |name: &str| generation.join(name).to_str().unwrap().to_owned();
            let data = json!({
                "formatVersion": 1, "stateVersion": "1", "runtime": "droid-nix",
                "name": "guest", "home": "/home/guest", "homeManager": null,
                "systemPath": text("sw"),
                "session": {
                    "shell": text("shell"),
                    "certificate": text("cert"),
                    "terminfo": text("terminfo"),
                },
            });
            let prepared = Self {
                _dir: dir,
                runtime,
                generation,
                data,
            };
            prepared.save();
            prepared
        }

        fn save(&self) {
            fs::write(self.generation.join("manifest.json"), self.data.to_string()).unwrap();
        }

        /// Temporary fixtures stand in for store paths; the real grammar is
        /// covered separately.
        fn prepare(&self) -> Result<PathBuf> {
            prepare_with(&self.runtime, &self.generation, &|_| Ok(()))
        }

        fn name(&self) -> String {
            self.generation
                .file_name()
                .unwrap()
                .to_str()
                .unwrap()
                .to_owned()
        }
    }

    fn mode(path: &Path) -> u32 {
        fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    #[test]
    fn prepare_retains_base_and_overlays_system() {
        let fixture = Prepared::new();
        let result = fixture.prepare().unwrap();
        let read = |name: &str| fs::read_to_string(result.join(name)).unwrap();
        assert_eq!(read("etc/example"), "new\n");
        assert_eq!(read("etc/nested/value"), "nested\n");
        assert_eq!(read("etc/resolv.conf"), "nameserver 127.0.0.1\n");
        assert_eq!(
            fs::read_to_string(fixture.runtime.join("root/etc/example")).unwrap(),
            "old\n"
        );
        assert_eq!(
            fs::read(result.join("etc/passwd")).unwrap(),
            fs::read(fixture.runtime.join("root/etc/passwd")).unwrap()
        );
        assert_eq!(read("session").lines().count(), 6);
        assert_eq!(mode(&result), 0o700);
        assert_eq!(mode(&result.join("etc/passwd")), 0o600);
        assert_eq!(mode(&result.join("session")), 0o600);
        let root = fixture.runtime.join(GCROOTS).join(fixture.name());
        assert_eq!(fs::read_link(root).unwrap(), fixture.generation);
        assert!(!fixture.runtime.join("current-system").exists());
        assert_eq!(
            read("generation"),
            format!("{}\n", fixture.generation.display())
        );
    }

    #[test]
    fn session_file_lists_identity_and_store_paths() {
        let fixture = Prepared::new();
        let result = fixture.prepare().unwrap();
        let session = fs::read_to_string(result.join("session")).unwrap();
        let lines: Vec<&str> = session.lines().collect();
        assert_eq!(lines[0], "guest");
        assert_eq!(lines[1], "/home/guest");
        assert_eq!(
            lines[2],
            format!("{}/bin", fixture.generation.join("sw").display())
        );
    }

    #[test]
    fn manifest_is_stored_in_canonical_form() {
        let fixture = Prepared::new();
        let result = fixture.prepare().unwrap();
        let stored = fs::read_to_string(result.join("manifest.json")).unwrap();
        assert!(stored.starts_with("{\"formatVersion\": 1, \"home\": \"/home/guest\""));
        assert!(stored.ends_with("}\n"));
    }

    #[test]
    fn retained_candidate_is_not_overwritten() {
        let fixture = Prepared::new();
        let candidate = fixture.prepare().unwrap();
        let error = message(fixture.prepare());
        assert!(error.contains("already exists"), "{error}");
        assert!(candidate.join("session").is_file());
    }

    #[test]
    fn symlink_at_the_destination_counts_as_existing() {
        let fixture = Prepared::new();
        let candidates = fixture.runtime.join("system-candidates");
        fs::create_dir(&candidates).unwrap();
        symlink("/nonexistent", candidates.join(fixture.name())).unwrap();
        assert!(message(fixture.prepare()).contains("already exists"));
    }

    #[test]
    fn identity_mismatch() {
        let mut fixture = Prepared::new();
        fixture.data["name"] = json!("other");
        fixture.data["home"] = json!("/home/other");
        fixture.save();
        let error = message(fixture.prepare());
        assert!(error.contains("identity does not match"), "{error}");
    }

    #[test]
    fn invalid_identity_is_rejected() {
        for (name, home) in [
            ("Guest", "/home/Guest"),
            ("guest", "/home/other"),
            ("a/b", "/home/a/b"),
        ] {
            let mut fixture = Prepared::new();
            fixture.data["name"] = json!(name);
            fixture.data["home"] = json!(home);
            fixture.save();
            let error = message(fixture.prepare());
            assert!(error.contains("invalid guest identity"), "{name}: {error}");
        }
    }

    #[test]
    fn unsupported_schema() {
        for (key, value) in [
            ("formatVersion", json!(2)),
            ("stateVersion", json!(1)),
            ("runtime", json!("other")),
        ] {
            let mut fixture = Prepared::new();
            fixture.data[key] = value;
            fixture.save();
            let error = message(fixture.prepare());
            assert!(error.contains("unsupported"), "{key}: {error}");
        }
    }

    #[test]
    fn unsupported_base_runtime() {
        let fixture = Prepared::new();
        fs::write(
            fixture.runtime.join("session.json"),
            r#"{"schema": 1, "system": "x86_64-linux", "pageSize": 4096}"#,
        )
        .unwrap();
        assert!(message(fixture.prepare()).contains("unsupported base runtime"));
    }

    #[test]
    fn reserved_identity_files() {
        let fixture = Prepared::new();
        fs::write(fixture.generation.join("etc/passwd"), "not Android\n").unwrap();
        assert!(message(fixture.prepare()).contains("passwd/group"));
        fs::remove_file(fixture.generation.join("etc/passwd")).unwrap();
        symlink("/nonexistent", fixture.generation.join("etc/group")).unwrap();
        assert!(message(fixture.prepare()).contains("passwd/group"));
    }

    #[test]
    fn ambiguous_or_malformed_passwd_is_rejected() {
        for passwd in [
            "",
            "guest:x:1:2:G:/home/guest:/bin/sh\nguest:x:3:4:G:/home/guest:/bin/sh\n",
            "guest:x:1:2:/home/guest:/bin/sh\n",
        ] {
            let fixture = Prepared::new();
            fs::write(fixture.runtime.join("root/etc/passwd"), passwd).unwrap();
            let error = message(fixture.prepare());
            assert!(
                error.contains("identity does not match"),
                "{passwd}: {error}"
            );
        }
    }

    #[test]
    fn missing_closure() {
        let fixture = Prepared::new();
        fs::remove_file(fixture.generation.join("shell")).unwrap();
        assert!(message(fixture.prepare()).contains("closure"));
    }

    #[test]
    fn missing_or_non_string_store_paths_are_rejected() {
        for key in ["systemPath", "session"] {
            let mut fixture = Prepared::new();
            fixture.data[key] = json!(7);
            fixture.save();
            let error = message(fixture.prepare());
            assert!(error.contains("invalid guest store path"), "{key}: {error}");
        }
        let mut fixture = Prepared::new();
        fixture.data["session"]
            .as_object_mut()
            .unwrap()
            .remove("shell");
        fixture.save();
        assert!(message(fixture.prepare()).contains("invalid guest store path"));
    }

    #[test]
    fn real_store_check_rejects_paths_outside_the_store() {
        let fixture = Prepared::new();
        let error = message(prepare(&fixture.runtime, &fixture.generation));
        assert!(error.contains("invalid guest store path"), "{error}");
        assert!(!fixture.runtime.join("system-candidates").exists());
    }

    #[test]
    fn home_manager_generation_must_be_available() {
        let mut fixture = Prepared::new();
        let home = fixture.generation.join("home");
        fs::create_dir(&home).unwrap();
        fixture.data["homeManager"] = json!(home.to_str().unwrap());
        fixture.save();
        assert!(message(fixture.prepare()).contains("Home Manager"));
        fs::write(home.join("activate"), "").unwrap();
        fixture.prepare().unwrap();
    }

    #[test]
    fn failed_copy_leaves_no_candidate() {
        let fixture = Prepared::new();
        symlink(
            fixture.generation.join("etc"),
            fixture.generation.join("etc/cycle"),
        )
        .unwrap();
        let error = message(fixture.prepare());
        assert!(error.contains("directory symlinks"), "{error}");
        let leftovers = fs::read_dir(fixture.runtime.join("system-candidates"))
            .unwrap()
            .count();
        assert_eq!(leftovers, 0);
        assert!(!fixture.runtime.join(GCROOTS).join(fixture.name()).exists());
    }

    #[test]
    fn special_and_dangling_files_are_rejected() {
        let fixture = Prepared::new();
        symlink("/nonexistent", fixture.generation.join("etc/dangling")).unwrap();
        assert!(message(fixture.prepare()).contains("special or dangling"));
        fs::remove_file(fixture.generation.join("etc/dangling")).unwrap();
        let fifo =
            CString::new(fixture.generation.join("etc/fifo").as_os_str().as_bytes()).unwrap();
        // SAFETY: valid NUL-terminated path.
        assert_eq!(unsafe { libc::mkfifo(fifo.as_ptr(), 0o600) }, 0);
        assert!(message(fixture.prepare()).contains("special or dangling"));
    }

    #[test]
    fn overlay_conflicts_are_rejected() {
        let fixture = Prepared::new();
        fs::create_dir(fixture.runtime.join("root/etc/clash")).unwrap();
        fs::write(fixture.generation.join("etc/clash"), "file").unwrap();
        assert!(message(fixture.prepare()).contains("conflicts with an existing directory"));
        let other = Prepared::new();
        fs::write(other.runtime.join("root/etc/clash"), "file").unwrap();
        fs::create_dir(other.generation.join("etc/clash")).unwrap();
        assert!(message(other.prepare()).contains("conflicts with an existing file"));
    }

    #[test]
    fn symlinked_candidate_directories_are_rejected() {
        let fixture = Prepared::new();
        symlink(
            &fixture.generation,
            fixture.runtime.join("system-candidates"),
        )
        .unwrap();
        assert!(message(fixture.prepare()).contains("candidate directory must not be a symlink"));
        let other = Prepared::new();
        let roots = other.runtime.join(GCROOTS);
        fs::create_dir_all(roots.parent().unwrap()).unwrap();
        symlink(&other.generation, &roots).unwrap();
        assert!(message(other.prepare()).contains("GC root directory"));
        let leftovers = fs::read_dir(other.runtime.join("system-candidates"))
            .unwrap()
            .count();
        assert_eq!(leftovers, 0);
    }

    #[test]
    fn configuration_files_link_to_generation_except_native_release() {
        let fixture = Prepared::new();
        symlink(
            fixture.generation.join("etc/example"),
            fixture.generation.join("etc/linked"),
        )
        .unwrap();
        let release = fixture.generation.join("etc/termuxpp-release");
        fs::write(&release, "ID=termuxpp\n").unwrap();
        let result = fixture.prepare().unwrap();
        for name in ["example", "linked"] {
            assert_eq!(
                fs::read_link(result.join("etc").join(name)).unwrap(),
                fixture.generation.join("etc").join(name)
            );
        }
        assert!(!is_symlink(&result.join("etc/termuxpp-release")));
        assert_eq!(
            fs::read_to_string(result.join("etc/termuxpp-release")).unwrap(),
            "ID=termuxpp\n"
        );
        assert_eq!(
            fs::read_to_string(result.join("etc/linked")).unwrap(),
            "new\n"
        );
    }

    #[test]
    fn store_path_validation() {
        let good = format!("/nix/store/{}-bash/bin/bash", "a".repeat(32));
        assert!(guest_store_path(&good).is_ok());
        for bad in [
            "/bin/bash".to_owned(),
            format!("{good}/../escape"),
            format!("{good}:bad"),
            format!("{good}\nextra"),
        ] {
            assert!(guest_store_path(&bad).is_err(), "{bad:?}");
        }
    }

    struct Scripted {
        output: String,
        commands: Vec<Vec<String>>,
    }

    impl Scripted {
        fn new(output: &str) -> Self {
            Self {
                output: output.to_owned(),
                commands: Vec::new(),
            }
        }
    }

    impl Builder for Scripted {
        fn output(&mut self, command: &[String]) -> Result<String> {
            self.commands.push(command.to_vec());
            Ok(self.output.clone())
        }
    }

    fn system_path() -> String {
        format!("/nix/store/{}-termuxpp-system-test", "a".repeat(32))
    }

    #[test]
    fn upgrade_uses_configured_defaults_and_plans_without_building() {
        let dir = tempfile::tempdir().unwrap();
        let config = dir.path().join("upgrade.json");
        fs::write(
            &config,
            r#"{"flake":"github:example/config/main","host":"phone"}"#,
        )
        .unwrap();
        let target = upgrade_target(&config, Some("/source".to_owned()), None).unwrap();
        let mut builder = Scripted::new("");
        plan_upgrade(&target, &mut builder).unwrap();
        assert_eq!(
            builder.commands[0],
            [
                "nix",
                "build",
                "--refresh",
                "--dry-run",
                "--max-jobs",
                "0",
                "--no-link",
                "--print-out-paths",
                "/source#termuxppConfigurations.phone.system",
            ]
        );
    }

    #[test]
    fn cache_only_upgrade_checks_the_host_and_signatures_before_downloading() {
        let target = UpgradeTarget {
            host: "test".to_owned(),
            flake: "unused".to_owned(),
            cache: Some(UpgradeCache {
                store: "file:///cache".to_owned(),
                pin_reader: "/pinned/read-pin".into(),
                public_keys: vec!["test:key".to_owned()],
                credentials_file: None,
            }),
        };
        struct CacheFixture {
            results: std::vec::IntoIter<String>,
            commands: Vec<Vec<String>>,
        }

        impl Builder for CacheFixture {
            fn output(&mut self, command: &[String]) -> Result<String> {
                self.commands.push(command.to_vec());
                Ok(self.results.next().unwrap())
            }
        }

        let path = system_path();
        let mut builder = CacheFixture {
            results: vec![
                path.clone(),
                json!({path.clone(): {"ca": null, "ultimate": false}}).to_string(),
                String::new(),
            ]
            .into_iter(),
            commands: Vec::new(),
        };
        assert_eq!(
            cached_upgrade(&target, true, &mut builder).unwrap(),
            Path::new(&path)
        );
        assert_eq!(builder.commands[0], ["/pinned/read-pin"]);
        assert_eq!(
            builder.commands[2],
            [
                "nix",
                "--refresh",
                "--option",
                "trusted-public-keys",
                "test:key",
                "store",
                "verify",
                "--store",
                "file:///cache",
                "--no-contents",
                "--sigs-needed",
                "1",
                &path,
            ]
        );
        assert_eq!(builder.commands.len(), 3);
        let mut builder = Scripted::new(&path.replace("-test", "-other"));
        assert!(cached_upgrade(&target, false, &mut builder).is_err());
        assert_eq!(builder.commands.len(), 1);
        let mut builder = CacheFixture {
            results: vec![
                path.clone(),
                json!({path: {"ca": "fixed:sha256:123", "ultimate": false}}).to_string(),
            ]
            .into_iter(),
            commands: Vec::new(),
        };
        assert!(cached_upgrade(&target, false, &mut builder).is_err());
        assert_eq!(builder.commands.len(), 2);
    }

    #[test]
    fn build_never_compiles_on_phone() {
        let path = system_path();
        let mut builder = Scripted::new(&format!("{path}\n"));
        let built = build_system("/source", "test", false, &mut builder).unwrap();
        assert_eq!(built, PathBuf::from(&path));
        assert_eq!(
            builder.commands[0],
            [
                "nix",
                "build",
                "--max-jobs",
                "0",
                "--no-link",
                "--print-out-paths",
                "/source#termuxppConfigurations.test.system"
            ]
        );
    }

    #[test]
    fn build_uses_existing_rworker_integration() {
        let mut builder = Scripted::new(&format!("{}\n", system_path()));
        build_system("github:example/config", "test", true, &mut builder).unwrap();
        assert_eq!(
            builder.commands[0],
            [
                "rworker-nix",
                "build",
                "--no-link",
                "--print-out-paths",
                "github:example/config#termuxppConfigurations.test.system"
            ]
        );
    }

    #[test]
    fn invalid_build_arguments_never_launch() {
        let mut builder = Scripted::new("");
        for (flake, host) in [
            ("--bad", "host"),
            ("source#other", "host"),
            ("source", "host.bad"),
            ("source", ""),
            ("", "host"),
        ] {
            assert!(
                build_system(flake, host, false, &mut builder).is_err(),
                "{flake} {host}"
            );
        }
        assert!(builder.commands.is_empty());
    }

    #[test]
    fn build_output_is_validated() {
        let two = format!("{}\n/nix/store/{}-two\n", system_path(), "b".repeat(32));
        for output in [String::new(), "/tmp/not-store\n".to_owned(), two] {
            let mut builder = Scripted::new(&output);
            assert!(
                build_system("source", "host", false, &mut builder).is_err(),
                "{output:?}"
            );
        }
    }

    #[test]
    fn process_builder_reports_failures() {
        let run = |arguments: &[&str]| {
            let command: Vec<String> = arguments.iter().map(|text| (*text).to_owned()).collect();
            ProcessBuilder.output(&command)
        };
        assert_eq!(run(&["sh", "-c", "echo hi"]).unwrap(), "hi\n");
        assert!(message(run(&["sh", "-c", "exit 3"])).contains("failed"));
        // Under qemu-user (aarch64 checks on an x86_64 builder) the posix_spawn
        // fast path of `Command` cannot report a failed exec: the child exits
        // with status 127 instead. Either way the failure names the program.
        let missing = message(run(&["/nonexistent/program"]));
        assert!(missing.contains("/nonexistent/program"), "{missing}");
        assert!(
            missing.contains("cannot run") || missing.contains("failed"),
            "{missing}"
        );
        assert!(run(&[]).is_err());
    }

    /// A one-shot controller: replies with `response` and reports the request.
    fn controller(path: &Path, response: Vec<u8>) -> JoinHandle<Vec<u8>> {
        let listener = UnixListener::bind(path).unwrap();
        thread::spawn(move || {
            let (mut connection, _) = listener.accept().unwrap();
            let mut request = Vec::new();
            let mut byte = [0u8; 1];
            while !request.ends_with(b"\n") && connection.read(&mut byte).unwrap() == 1 {
                request.push(byte[0]);
            }
            let _ = connection.write_all(&response);
            request
        })
    }

    fn socket_path() -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("control.sock");
        (dir, path)
    }

    #[test]
    fn native_management_protocol_is_data_only() {
        let (_dir, path) = socket_path();
        let server = controller(&path, b"{\"status\":0,\"generations\":[]}\n".to_vec());
        let response = manage(&path, "list-generations", None).unwrap();
        assert_eq!(response["generations"], json!([]));
        let request: Value = serde_json::from_slice(&server.join().unwrap()).unwrap();
        assert_eq!(request, json!({"command": "list-generations"}));
    }

    #[test]
    fn candidate_is_sent_as_data() {
        let (_dir, path) = socket_path();
        let server = controller(&path, b"{\"status\":0}\n".to_vec());
        let name = format!("{}-termuxpp-system-test", "a".repeat(32));
        manage(&path, "switch", Some(&name)).unwrap();
        let request: Value = serde_json::from_slice(&server.join().unwrap()).unwrap();
        assert_eq!(request, json!({"command": "switch", "candidate": name}));
    }

    #[test]
    fn invalid_candidate_never_connects() {
        let (_dir, path) = socket_path();
        for candidate in [
            "../escape",
            "/absolute",
            "short",
            &format!("{}-bad/name", "x".repeat(32)),
        ] {
            let error = message(manage(&path, "switch", Some(candidate)));
            assert_eq!(error, "invalid system candidate name");
        }
    }

    #[test]
    fn unreachable_controller_names_the_socket() {
        let (_dir, path) = socket_path();
        let error = message(manage(&path, "list-generations", None));
        assert!(
            error.contains("native controller") && error.contains("control.sock"),
            "{error}"
        );
    }

    #[test]
    fn invalid_controller_responses_are_rejected() {
        let oversized = {
            let mut text = vec![b' '; RESPONSE_LIMIT + 1];
            text.push(b'\n');
            text
        };
        let cases: Vec<(&str, Vec<u8>)> = vec![
            (
                "invalid native controller status",
                b"{\"status\":true}\n".to_vec(),
            ),
            (
                "invalid native controller status",
                b"{\"status\":1.0}\n".to_vec(),
            ),
            (
                "invalid native controller status",
                b"{\"status\":\"0\"}\n".to_vec(),
            ),
            ("invalid native controller status", b"{}\n".to_vec()),
            ("invalid native controller status", b"[]\n".to_vec()),
            ("invalid native controller response", b"not json\n".to_vec()),
            (
                "invalid native controller response",
                b"{\"status\":0}".to_vec(),
            ),
            ("invalid native controller response", Vec::new()),
            ("invalid native controller response", oversized),
        ];
        for (expected, response) in cases {
            let (_dir, path) = socket_path();
            let server = controller(&path, response.clone());
            let error = message(manage(&path, "list-generations", None));
            assert_eq!(
                error,
                expected,
                "{:?}",
                String::from_utf8_lossy(&response[..response.len().min(40)])
            );
            server.join().unwrap();
        }
    }

    #[test]
    fn controller_errors_are_surfaced() {
        let (_dir, path) = socket_path();
        let server = controller(&path, b"{\"status\":1,\"error\":\"nope\"}\n".to_vec());
        assert_eq!(message(manage(&path, "recover", None)), "nope");
        server.join().unwrap();
        let (_dir, path) = socket_path();
        let server = controller(&path, b"{\"status\":3}\n".to_vec());
        assert_eq!(
            message(manage(&path, "recover", None)),
            "native controller failed with status 3"
        );
        server.join().unwrap();
    }

    #[test]
    fn generations_are_decoded() {
        let response = json!({"status": 0, "generations": [{
            "generation": "g", "homeManager": "h", "current": true, "previous": false}]});
        let list = generations(&response).unwrap();
        assert_eq!(list.len(), 1);
        assert!(list[0].current && !list[0].previous);
        assert!(generations(&json!({"status": 0})).is_err());
        assert!(generations(&json!({"generations": [1]})).is_err());
    }

    #[test]
    fn rebuild_skips_prepare_for_a_retained_candidate_and_switches() {
        let fixture = crate::testutil::Fixture::new();
        let (_dir, path) = socket_path();
        let server = controller(&path, b"{\"status\":0}\n".to_vec());
        let name = fixture.name.clone();
        let mut builder = Scripted::new(&format!("/nix/store/{name}\n"));
        let mut stages = Vec::new();
        let built = rebuild(
            &fixture.runtime,
            &path,
            "source",
            "host",
            false,
            &mut builder,
            &mut |stage| stages.push(stage),
        )
        .unwrap();
        assert_eq!(built, PathBuf::from(format!("/nix/store/{name}")));
        assert_eq!(stages, [Stage::Build, Stage::Switch]);
        let request: Value = serde_json::from_slice(&server.join().unwrap()).unwrap();
        assert_eq!(request, json!({"command": "switch", "candidate": name}));
    }

    #[test]
    fn rebuild_stops_when_the_build_fails() {
        let fixture = crate::testutil::Fixture::new();
        let (_dir, path) = socket_path();
        let mut builder = Scripted::new("");
        let mut stages = Vec::new();
        let result = rebuild(
            &fixture.runtime,
            &path,
            "source",
            "host",
            false,
            &mut builder,
            &mut |stage| stages.push(stage),
        );
        assert!(result.is_err());
        assert_eq!(stages, [Stage::Build]);
    }
}

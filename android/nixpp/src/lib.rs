use anyhow::{Context, Result, bail, ensure};
use base64::{Engine, engine::general_purpose::STANDARD as BASE64};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::env;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, IsTerminal, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::time::{Duration, Instant};
use url::Url;

const NIX_BASE32: &[u8; 32] = b"0123456789abcdfghijklmnpqrsvwxyz";
const MAX_NAR_SIZE: u64 = 20 << 30;
const MAX_NAR_STRING: u64 = 1 << 30;
const MAX_NARINFO_SIZE: u64 = 1 << 20;
const ZSTD_MAGIC: &[u8; 4] = b"\x28\xb5\x2f\xfd";

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
struct NixppConfig {
    defaults: ConfigDefaults,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
struct ConfigDefaults {
    substituter: Option<String>,
    flake: Option<String>,
    builders: Vec<String>,
    /// Backwards compatibility for configs written before builder lists.
    builder: Option<String>,
    public_keys: Vec<String>,
    aws_credentials_file: Option<PathBuf>,
    aws_credentials_command: Option<Vec<String>>,
    cache_pins: BTreeMap<String, String>,
}

#[derive(Debug, Serialize)]
struct CachePin {
    name: String,
    pin: String,
    store_path: Option<String>,
    status: &'static str,
}

impl ConfigDefaults {
    fn configured_builders(&self) -> Vec<String> {
        if self.builders.is_empty() {
            self.builder.iter().cloned().collect()
        } else {
            self.builders.clone()
        }
    }
}

#[derive(Debug)]
struct CacheTarget {
    base: Url,
    s3: Option<S3Cache>,
}

#[derive(Debug)]
struct S3Cache {
    region: String,
    profile: String,
    credentials: AwsCredentialSource,
}

#[derive(Debug)]
enum AwsCredentialSource {
    File(PathBuf),
    Command(Vec<String>),
}

struct CacheAuth {
    netrc: Option<PathBuf>,
    curl_config: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct NarInfo {
    store_path: String,
    url: String,
    compression: String,
    nar_hash: String,
    nar_size: u64,
    file_hash: Option<String>,
    file_size: Option<u64>,
    references: Vec<String>,
    signatures: Vec<String>,
}

struct Progress {
    color: bool,
}

impl Progress {
    fn new() -> Self {
        let color = io::stderr().is_terminal()
            && env::var_os("NO_COLOR").is_none()
            && env::var("TERM").as_deref() != Ok("dumb");
        Self { color }
    }

    fn for_stdout() -> Self {
        let color = io::stdout().is_terminal()
            && env::var_os("NO_COLOR").is_none()
            && env::var("TERM").as_deref() != Ok("dumb");
        Self { color }
    }

    fn paint(&self, code: &str, value: &str) -> String {
        if self.color {
            format!("\x1b[{code}m{value}\x1b[0m")
        } else {
            value.to_owned()
        }
    }

    fn title(&self) {
        eprintln!("nixpp: {}", self.paint("2", "Termux environment"));
    }

    fn stage(&self, label: &str, action: impl FnOnce() -> Result<()>) -> Result<()> {
        eprintln!("{label}");
        let started = Instant::now();
        let result = action();
        self.report_stage_completion(started.elapsed(), result)
    }

    fn report_stage_result(
        &self,
        label: &str,
        duration: Duration,
        result: Result<()>,
    ) -> Result<()> {
        eprintln!("{label}");
        self.report_stage_completion(duration, result)
    }

    fn report_stage_completion(&self, duration: Duration, result: Result<()>) -> Result<()> {
        match result {
            Ok(()) => {
                eprintln!("  {} ({})", self.paint("1;32", "OK"), elapsed(duration));
                Ok(())
            }
            Err(error) => {
                eprintln!("  {} ({})", self.paint("1;31", "Failed"), elapsed(duration));
                Err(error)
            }
        }
    }

    fn warning(&self, message: &str) {
        eprintln!("{}: {message}", self.paint("1;33", "Warning"));
    }
}

fn elapsed(duration: Duration) -> String {
    let seconds = duration.as_secs();
    if seconds < 60 {
        format!("{seconds}s")
    } else {
        format!("{}m {:02}s", seconds / 60, seconds % 60)
    }
}

#[derive(Debug, serde::Serialize)]
struct GenerationInfo {
    id: String,
    number: Option<u64>,
    path: String,
    architecture: String,
    minimum_api: u64,
    pinned: bool,
    apt_packages: Vec<String>,
    nix_packages: Vec<String>,
    #[serde(skip_serializing)]
    home_files: Option<Vec<String>>,
    #[serde(skip_serializing)]
    plugins: Option<Vec<String>>,
    #[serde(skip_serializing)]
    gitstatus_version: Option<String>,
}

#[derive(Debug, serde::Serialize)]
struct GenerationEntry {
    id: String,
    number: Option<u64>,
    current: bool,
    pinned: bool,
}

#[derive(Debug, serde::Serialize)]
struct InvalidGeneration {
    id: String,
    error: String,
}

#[derive(Debug, serde::Serialize)]
struct GenerationStatus {
    root: String,
    current: Option<GenerationInfo>,
    generations: Vec<GenerationEntry>,
    invalid_generations: Vec<InvalidGeneration>,
}

fn valid_generation_id(id: &str) -> bool {
    id.len() == 64
        && id
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

fn generation_id_from_target(target: &Path) -> Result<String> {
    let mut components = target.components();
    ensure!(
        matches!(components.next(), Some(Component::Normal(name)) if name == OsStr::new("generations")),
        "current generation symlink must point under generations/"
    );
    let id = components
        .next()
        .and_then(|component| match component {
            Component::Normal(name) => name.to_str(),
            _ => None,
        })
        .context("current generation symlink has no generation ID")?;
    ensure!(
        components.next().is_none() && valid_generation_id(id),
        "current generation symlink has an invalid target"
    );
    Ok(id.to_owned())
}

fn manifest_string_array(manifest: &serde_json::Value, name: &str) -> Result<Vec<String>> {
    manifest
        .get(name)
        .and_then(serde_json::Value::as_array)
        .with_context(|| format!("generation manifest is missing {name}"))?
        .iter()
        .map(|item| {
            item.as_str()
                .map(str::to_owned)
                .with_context(|| format!("generation manifest {name} contains a non-string value"))
        })
        .collect()
}

fn optional_manifest_string_array(
    manifest: &serde_json::Value,
    name: &str,
) -> Result<Option<Vec<String>>> {
    manifest
        .get(name)
        .map(|_| manifest_string_array(manifest, name))
        .transpose()
}

fn record_generation_number(
    numbers: &mut HashMap<String, u64>,
    used_numbers: &mut HashSet<u64>,
    id: &str,
    number: u64,
) -> Result<()> {
    ensure!(
        valid_generation_id(id),
        "invalid generation ID in index: {id}"
    );
    ensure!(number > 0, "generation number must be positive");
    if let Some(existing) = numbers.get(id) {
        ensure!(
            *existing == number,
            "conflicting generation numbers for {id}: {existing} and {number}"
        );
        return Ok(());
    }
    ensure!(
        used_numbers.insert(number),
        "duplicate generation number in index: {number}"
    );
    numbers.insert(id.to_owned(), number);
    Ok(())
}

fn generation_numbers(root: &Path) -> Result<HashMap<String, u64>> {
    let mut numbers = HashMap::new();
    let mut used_numbers = HashSet::new();

    let json_path = root.join("generation-index.json");
    match fs::read_to_string(&json_path) {
        Ok(contents) => {
            let entries: serde_json::Value = serde_json::from_str(&contents)
                .with_context(|| format!("parse {}", json_path.display()))?;
            let entries = entries
                .as_object()
                .with_context(|| format!("{} must contain a JSON object", json_path.display()))?;
            for (id, value) in entries {
                let number = value.as_u64().with_context(|| {
                    format!(
                        "invalid generation number for {id} in {}",
                        json_path.display()
                    )
                })?;
                record_generation_number(&mut numbers, &mut used_numbers, id, number)?;
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error).with_context(|| format!("read {}", json_path.display())),
    }

    let path = root.join("generation-index.tsv");
    let contents = match fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(numbers),
        Err(error) => return Err(error).with_context(|| format!("read {}", path.display())),
    };
    for (line_number, line) in contents.lines().enumerate() {
        let fields: Vec<_> = line.split('\t').collect();
        ensure!(
            fields.len() == 2
                && fields[0].parse::<u64>().is_ok_and(|number| number > 0)
                && valid_generation_id(fields[1]),
            "invalid generation index entry on line {}",
            line_number + 1
        );
        let number = fields[0].parse::<u64>()?;
        record_generation_number(&mut numbers, &mut used_numbers, fields[1], number)?;
    }
    Ok(numbers)
}

fn generation_pins(root: &Path) -> Result<HashSet<String>> {
    let path = root.join("pinned-generations.json");
    let contents = match fs::read(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(HashSet::new()),
        Err(error) => return Err(error).with_context(|| format!("read {}", path.display())),
    };
    let pins: Vec<String> =
        serde_json::from_slice(&contents).with_context(|| format!("parse {}", path.display()))?;
    let mut result = HashSet::new();
    for id in pins {
        ensure!(
            valid_generation_id(&id) && result.insert(id.clone()),
            "{} contains an invalid or duplicate generation ID",
            path.display()
        );
    }
    Ok(result)
}

fn resolve_generation(root: &Path, selection: &str) -> Result<String> {
    if let Ok(number) = selection.parse::<u64>() {
        ensure!(number > 0, "generation number must be positive");
        return generation_numbers(root)?
            .into_iter()
            .find_map(|(id, candidate)| (candidate == number).then_some(id))
            .with_context(|| format!("unknown generation number {number}"));
    }
    ensure!(
        valid_generation_id(selection),
        "expected a generation number or lowercase SHA-256 ID"
    );
    Ok(selection.to_owned())
}

fn inspect_generation(
    root: &Path,
    id: &str,
    number: Option<u64>,
    pinned: bool,
) -> Result<GenerationInfo> {
    let path = root.join("generations").join(id);
    let metadata =
        fs::symlink_metadata(&path).with_context(|| format!("inspect generation {id}"))?;
    ensure!(
        metadata.file_type().is_dir(),
        "generation {id} is not a real directory"
    );
    let manifest_path = path.join("manifest.json");
    ensure!(
        fs::symlink_metadata(&manifest_path).is_ok_and(|metadata| metadata.file_type().is_file()),
        "generation {id} has no regular manifest.json"
    );
    let manifest: serde_json::Value = serde_json::from_slice(
        &fs::read(&manifest_path).with_context(|| format!("read generation {id} manifest"))?,
    )
    .with_context(|| format!("parse generation {id} manifest"))?;
    ensure!(
        manifest.get("schema").and_then(serde_json::Value::as_u64) == Some(1),
        "generation {id} uses an unsupported manifest schema"
    );
    let architecture = manifest
        .get("architecture")
        .and_then(serde_json::Value::as_str)
        .context("generation manifest is missing architecture")?
        .to_owned();
    let minimum_api = manifest
        .get("minimumApi")
        .and_then(serde_json::Value::as_u64)
        .context("generation manifest is missing minimumApi")?;
    Ok(GenerationInfo {
        id: id.to_owned(),
        number,
        path: root.join("current").display().to_string(),
        architecture,
        minimum_api,
        pinned,
        apt_packages: manifest_string_array(&manifest, "basePackages")?,
        nix_packages: manifest_string_array(&manifest, "homePackages")?,
        home_files: optional_manifest_string_array(&manifest, "homeFiles")?,
        plugins: optional_manifest_string_array(&manifest, "plugins")?,
        gitstatus_version: manifest
            .get("gitstatusVersion")
            .and_then(serde_json::Value::as_str)
            .map(str::to_owned),
    })
}

fn inspect_generations(root: &Path) -> Result<GenerationStatus> {
    let numbers = generation_numbers(root)?;
    let pinned = generation_pins(root)?;
    let current = match fs::read_link(root.join("current")) {
        Ok(target) => Some(generation_id_from_target(&target)?),
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        Err(error) => return Err(error).context("read current generation symlink"),
    };
    let generations_dir = root.join("generations");
    let mut ids = Vec::new();
    match fs::read_dir(&generations_dir) {
        Ok(entries) => {
            for entry in entries {
                let entry = entry.context("read generation directory entry")?;
                if !entry
                    .file_type()
                    .context("inspect generation directory entry")?
                    .is_dir()
                {
                    continue;
                }
                let Some(id) = entry.file_name().to_str().map(str::to_owned) else {
                    continue;
                };
                if valid_generation_id(&id) {
                    ids.push(id);
                }
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error).context("read generations directory"),
    }
    if let Some(id) = &current {
        ensure!(
            ids.contains(id),
            "current points to a missing generation: {id}"
        );
    }
    ids.sort_unstable();
    ids.sort_by_key(|id| id != current.as_deref().unwrap_or_default());
    let mut current_info = None;
    let mut generations = Vec::new();
    let mut invalid_generations = Vec::new();
    for id in ids {
        match inspect_generation(root, &id, numbers.get(&id).copied(), pinned.contains(&id)) {
            Ok(info) if Some(&id) == current.as_ref() => current_info = Some(info),
            Ok(info) => generations.push(GenerationEntry {
                id,
                number: info.number,
                current: false,
                pinned: info.pinned,
            }),
            Err(error) if Some(&id) == current.as_ref() => {
                return Err(error).with_context(|| format!("inspect current generation {id}"));
            }
            Err(error) => invalid_generations.push(InvalidGeneration {
                id,
                error: format!("{error:#}"),
            }),
        }
    }
    if let Some(info) = &current_info {
        generations.insert(
            0,
            GenerationEntry {
                id: info.id.clone(),
                number: info.number,
                current: true,
                pinned: info.pinned,
            },
        );
    }
    Ok(GenerationStatus {
        root: root.display().to_string(),
        current: current_info,
        generations,
        invalid_generations,
    })
}

fn termux_generation_root() -> Result<PathBuf> {
    let home = env::var_os("HOME").context("HOME is not set")?;
    Ok(PathBuf::from(home).join(".local/share/termux-native"))
}

fn print_generation_status(status: &GenerationStatus, json: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(status)?);
        return Ok(());
    }

    let ui = Progress::new();
    println!("{}", ui.paint("1;36", "nixpp: Termux generations"));
    if let Some(current) = &status.current {
        let number = current.number.map_or_else(
            || "unnumbered".to_owned(),
            |number| format!("generation {number}"),
        );
        let label = format!("{number} · {}", &current.id[..12]);
        println!("Current: {}", ui.paint("1;32", &label));
        if current.pinned {
            println!("  Pinned: yes");
        }
        println!(
            "  {} · Android API {}+",
            current.architecture, current.minimum_api
        );
        println!(
            "  Termux APT: {}",
            sorted_package_list(&current.apt_packages)
        );
        println!(
            "  Nix outputs: {}",
            sorted_package_list(&current.nix_packages)
        );
        println!("  Path: {}", current.path);
    } else {
        println!("Current: {}", ui.paint("1;33", "none"));
        println!("Run `nixpp switch --flake FLAKE` to install a generation.");
    }
    println!("Readable generations: {}", status.generations.len());
    if !status.invalid_generations.is_empty() {
        println!(
            "Unusable historical generations: {} (details: `nixpp status --json`)",
            status.invalid_generations.len()
        );
    }
    Ok(())
}

fn sorted_package_list(packages: &[String]) -> String {
    let mut sorted: Vec<_> = packages.iter().map(String::as_str).collect();
    sorted.sort_unstable();
    sorted.join(", ")
}

fn print_generations(status: &GenerationStatus) {
    let ui = Progress::new();
    println!("{}", ui.paint("1;36", "nixpp: generations"));
    if status.generations.is_empty() {
        println!("No generations are installed.");
        return;
    }
    println!("Rollback with: nixpp rollback GENERATION_NUMBER");
    let mut generations: Vec<_> = status.generations.iter().collect();
    generations.sort_by_key(|generation| generation.number.unwrap_or(u64::MAX));
    for generation in generations {
        let number = generation.number.map_or_else(
            || "unnumbered".to_owned(),
            |number| format!("generation {number}"),
        );
        let label = format!("{number} · {}", &generation.id[..12]);
        let label = if generation.current {
            ui.paint("1;32", &label)
        } else {
            ui.paint("2", &label)
        };
        let mut tags = Vec::new();
        if generation.current {
            tags.push("current");
        }
        if generation.pinned {
            tags.push("pinned");
        }
        if tags.is_empty() {
            println!("  {label}");
        } else {
            println!("  {label} ({})", tags.join(", "));
        }
    }
    if !status.invalid_generations.is_empty() {
        println!(
            "Skipped {} unusable historical generation(s).",
            status.invalid_generations.len()
        );
    }
}

pub fn status(all: bool, json: bool) -> Result<()> {
    let status = inspect_generations(&termux_generation_root()?)?;
    print_generation_status(&status, json)?;
    if all && !json {
        print_generations(&status);
    }
    Ok(())
}

pub fn generations() -> Result<()> {
    let status = inspect_generations(&termux_generation_root()?)?;
    print_generations(&status);
    Ok(())
}

pub fn pin(generation: &str, pinned: bool) -> Result<()> {
    let root = termux_generation_root()?;
    let generation = resolve_generation(&root, generation)?;
    let action = if pinned { "pin" } else { "unpin" };
    let status = Command::new("bash")
        .arg(root.join("current/bootstrap.sh"))
        .arg(action)
        .arg(generation)
        .status()
        .context("start generation pin update")?;
    ensure!(status.success(), "generation {action} failed: {status}");
    Ok(())
}

pub fn doctor() -> Result<()> {
    let config = load_config()?;
    let flake = config
        .defaults
        .flake
        .as_deref()
        .context("defaults.flake is not configured")?;
    let builders = config.defaults.configured_builders();
    let cache = config
        .defaults
        .substituter
        .as_deref()
        .context("defaults.substituter is not configured")?;
    ensure!(!flake.is_empty(), "defaults.flake is empty");
    ensure!(!builders.is_empty(), "defaults.builders is not configured");
    for builder in &builders {
        ensure!(
            valid_ssh_target(builder),
            "defaults.builders contains an invalid SSH target: {builder}"
        );
    }
    ensure!(
        !config.defaults.public_keys.is_empty(),
        "defaults.public_keys is empty"
    );
    for key in &config.defaults.public_keys {
        let (_, encoded) = key
            .split_once(':')
            .context("public key must use NAME:BASE64 format")?;
        let bytes = BASE64
            .decode(encoded)
            .context("public key is not valid base64")?;
        let key_array: [u8; 32] = bytes
            .try_into()
            .map_err(|_| anyhow::anyhow!("public key must decode to 32 bytes"))?;
        VerifyingKey::from_bytes(&key_array).context("public key is not valid Ed25519")?;
    }

    let target = parse_cache_target(
        cache,
        config.defaults.aws_credentials_file.as_deref(),
        config.defaults.aws_credentials_command.as_deref(),
    )?;
    let s3 = target
        .s3
        .as_ref()
        .context("defaults.substituter must use s3://")?;
    let auth = CacheAuth {
        netrc: None,
        curl_config: Some(make_s3_curl_config(s3)?),
    };
    let ui = Progress::new();
    ui.title();
    ui.stage("Validate trusted cache keys and AWS credentials", || Ok(()))?;
    let (cache_check, builder_checks) = std::thread::scope(|scope| -> Result<_> {
        let target = &target;
        let auth = &auth;
        let cache_check = scope.spawn(move || {
            let started = Instant::now();
            let result = (|| {
                let url = safe_cache_url(&target.base, "nix-cache-info")?;
                let data = curl_read(&url, &auth, 1 << 20)?;
                let text = std::str::from_utf8(&data).context("nix-cache-info is not UTF-8")?;
                ensure!(
                    text.lines().any(|line| line.starts_with("StoreDir: ")),
                    "cache returned invalid nix-cache-info"
                );
                Ok(())
            })();
            (started.elapsed(), result)
        });
        let builder_checks: Vec<_> = builders
            .iter()
            .map(|builder| {
                scope.spawn(move || {
                    let started = Instant::now();
                    let result = (|| {
                        let output = Command::new("ssh")
                            .args([
                                "-o",
                                "BatchMode=yes",
                                "-o",
                                "ConnectTimeout=10",
                                builder,
                                "command -v nix >/dev/null",
                            ])
                            .output()
                            .context("start SSH check")?;
                        ensure!(
                            output.status.success(),
                            "builder SSH or Nix check failed: {}",
                            String::from_utf8_lossy(&output.stderr).trim()
                        );
                        Ok(())
                    })();
                    (started.elapsed(), result)
                })
            })
            .collect();

        let cache_check = cache_check
            .join()
            .map_err(|_| anyhow::anyhow!("S3 cache check panicked"))?;
        let builder_checks = builder_checks
            .into_iter()
            .map(|check| {
                check
                    .join()
                    .map_err(|_| anyhow::anyhow!("builder check panicked"))
            })
            .collect::<Result<Vec<_>>>()?;
        Ok((cache_check, builder_checks))
    })?;

    let cache_result = ui.report_stage_result(
        "Check access to the configured S3 cache",
        cache_check.0,
        cache_check.1,
    );
    let mut reachable_builders = 0;
    for (builder, (duration, result)) in builders.iter().zip(builder_checks) {
        if ui
            .report_stage_result(&format!("Check SSH and Nix on {builder}"), duration, result)
            .is_ok()
        {
            reachable_builders += 1;
        }
    }
    cache_result?;
    ensure!(
        reachable_builders > 0,
        "no configured Nix builders are reachable"
    );
    println!("Configuration and upgrade checks passed.");
    Ok(())
}

fn generation_label(generation: &GenerationInfo) -> String {
    let number = generation.number.map_or_else(
        || "unnumbered".to_owned(),
        |number| format!("generation {number}"),
    );
    format!("{number} · {}", &generation.id[..12])
}

fn print_set_diff(ui: &Progress, label: &str, old: &[String], new: &[String]) -> bool {
    let old: BTreeSet<_> = old.iter().collect();
    let new: BTreeSet<_> = new.iter().collect();
    let removed: Vec<_> = old.difference(&new).collect();
    let added: Vec<_> = new.difference(&old).collect();
    if removed.is_empty() && added.is_empty() {
        return false;
    }

    println!("{}:", ui.paint("1", label));
    for item in removed {
        println!("  {} {item}", ui.paint("31", "-"));
    }
    for item in added {
        println!("  {} {item}", ui.paint("32", "+"));
    }
    true
}

fn safe_home_file_path(path: &str) -> Result<PathBuf> {
    let path = Path::new(path);
    ensure!(
        !path.as_os_str().is_empty()
            && path
                .components()
                .all(|component| matches!(component, Component::Normal(_))),
        "generation manifest contains an unsafe home file path"
    );
    Ok(path.to_path_buf())
}

fn path_signature(path: &Path) -> Result<String> {
    let metadata = fs::symlink_metadata(&path)
        .with_context(|| format!("inspect generated home file {}", path.display()))?;
    let mode = metadata.permissions().mode() & 0o777;
    if metadata.file_type().is_symlink() {
        return Ok(format!(
            "symlink:{mode:o}:{}",
            fs::read_link(&path)?.display()
        ));
    }
    if metadata.file_type().is_dir() {
        return Ok(format!("directory:{mode:o}"));
    }
    ensure!(
        metadata.file_type().is_file(),
        "generated home path {} is not a regular file, directory, or symlink",
        path.display()
    );
    let mut file = File::open(&path).with_context(|| format!("open {}", path.display()))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 64 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .with_context(|| format!("read {}", path.display()))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("file:{mode:o}:{}", hex(&hasher.finalize())))
}

fn home_file_signature(generation_root: &Path, relative_path: &str) -> Result<String> {
    let relative_path = safe_home_file_path(relative_path)?;
    path_signature(&generation_root.join("home").join(relative_path))
}

fn generation_command_signatures(generation_root: &Path) -> Result<BTreeMap<String, String>> {
    let native = generation_root.join("native");
    let mut signatures = BTreeMap::new();
    let packages = match fs::read_dir(&native) {
        Ok(packages) => packages,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(signatures),
        Err(error) => return Err(error).with_context(|| format!("read {}", native.display())),
    };
    for package in packages {
        let package = package.with_context(|| format!("read an entry in {}", native.display()))?;
        if !package
            .file_type()
            .with_context(|| format!("inspect {}", package.path().display()))?
            .is_dir()
        {
            continue;
        }
        let package_name = package.file_name().into_string().map_err(|_| {
            anyhow::anyhow!("{} contains a non-UTF-8 package name", native.display())
        })?;
        let bin = package.path().join("bin");
        let commands = match fs::read_dir(&bin) {
            Ok(commands) => commands,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error).with_context(|| format!("read {}", bin.display())),
        };
        for command in commands {
            let command = command.with_context(|| format!("read an entry in {}", bin.display()))?;
            let file_type = command
                .file_type()
                .with_context(|| format!("inspect {}", command.path().display()))?;
            if !file_type.is_file() && !file_type.is_symlink() {
                continue;
            }
            let command_name = command.file_name().into_string().map_err(|_| {
                anyhow::anyhow!("{} contains a non-UTF-8 command name", bin.display())
            })?;
            signatures.insert(
                format!("{package_name}/bin/{command_name}"),
                path_signature(&command.path())?,
            );
        }
    }
    Ok(signatures)
}

fn print_command_diff(
    ui: &Progress,
    old_base: &Path,
    new_base: &Path,
    old: &GenerationInfo,
    new: &GenerationInfo,
) -> Result<bool> {
    let old_root = old_base.join("generations").join(&old.id);
    let new_root = new_base.join("generations").join(&new.id);
    let old_signatures = generation_command_signatures(&old_root)?;
    let new_signatures = generation_command_signatures(&new_root)?;
    let names: BTreeSet<_> = old_signatures
        .keys()
        .chain(new_signatures.keys())
        .cloned()
        .collect();
    let mut changes = Vec::new();
    for name in names {
        match (old_signatures.get(&name), new_signatures.get(&name)) {
            (Some(_), None) => changes.push(("31", "-", name)),
            (None, Some(_)) => changes.push(("32", "+", name)),
            (Some(old), Some(new)) if old != new => changes.push(("33", "~", name)),
            _ => {}
        }
    }
    if changes.is_empty() {
        return Ok(false);
    }
    println!("{}:", ui.paint("1", "Nix package commands"));
    for (color, marker, name) in changes {
        println!("  {} {name}", ui.paint(color, marker));
    }
    Ok(true)
}

fn print_home_file_diff(
    ui: &Progress,
    old_base: &Path,
    new_base: &Path,
    old: &GenerationInfo,
    new: &GenerationInfo,
) -> Result<bool> {
    let (Some(old_files), Some(new_files)) = (&old.home_files, &new.home_files) else {
        println!(
            "{}: not recorded in both generation manifests",
            ui.paint("1", "Generated home files")
        );
        return Ok(false);
    };

    let old_set: BTreeSet<_> = old_files.iter().collect();
    let new_set: BTreeSet<_> = new_files.iter().collect();
    let removed: Vec<_> = old_set.difference(&new_set).collect();
    let added: Vec<_> = new_set.difference(&old_set).collect();
    let mut changed = !removed.is_empty() || !added.is_empty();
    if changed {
        println!("{}:", ui.paint("1", "Generated home files"));
        for path in removed {
            println!("  {} {path}", ui.paint("31", "-"));
        }
        for path in added {
            println!("  {} {path}", ui.paint("32", "+"));
        }
    }

    let old_root = old_base.join("generations").join(&old.id);
    let new_root = new_base.join("generations").join(&new.id);
    let mut content_changes = Vec::new();
    for relative_path in old_set.intersection(&new_set) {
        if home_file_signature(&old_root, relative_path)?
            != home_file_signature(&new_root, relative_path)?
        {
            content_changes.push(*relative_path);
        }
    }
    if !content_changes.is_empty() {
        if !changed {
            println!("{}:", ui.paint("1", "Generated home files"));
        }
        for path in content_changes {
            println!("  {} {path}", ui.paint("33", "~"));
        }
        changed = true;
    }
    Ok(changed)
}

fn print_generation_diff(root: &Path, old_id: &str, new_id: &str) -> Result<()> {
    ensure!(old_id != new_id, "cannot diff a generation against itself");
    let numbers = generation_numbers(root)?;
    let pins = generation_pins(root)?;
    let old = inspect_generation(
        root,
        old_id,
        numbers.get(old_id).copied(),
        pins.contains(old_id),
    )?;
    let new = inspect_generation(
        root,
        new_id,
        numbers.get(new_id).copied(),
        pins.contains(new_id),
    )?;
    print_generation_diff_infos(root, root, &old, &new)
}

fn print_generation_diff_infos(
    old_base: &Path,
    new_base: &Path,
    old: &GenerationInfo,
    new: &GenerationInfo,
) -> Result<()> {
    ensure!(old.id != new.id, "cannot diff a generation against itself");
    let ui = Progress::for_stdout();
    println!(
        "{} {} → {}",
        ui.paint("1;36", "nixpp: generation diff"),
        generation_label(&old),
        generation_label(&new)
    );

    let mut changed = false;
    if old.architecture != new.architecture {
        println!(
            "Architecture: {} → {}",
            ui.paint("31", &old.architecture),
            ui.paint("32", &new.architecture)
        );
        changed = true;
    }
    if old.minimum_api != new.minimum_api {
        println!(
            "Minimum Android API: {} → {}",
            ui.paint("31", &old.minimum_api.to_string()),
            ui.paint("32", &new.minimum_api.to_string())
        );
        changed = true;
    }
    if old.gitstatus_version != new.gitstatus_version {
        match (&old.gitstatus_version, &new.gitstatus_version) {
            (Some(old), Some(new)) => println!(
                "Git status: {} → {}",
                ui.paint("31", old),
                ui.paint("32", new)
            ),
            (old, new) => println!("Git status: {old:?} → {new:?}"),
        }
        changed = true;
    }
    changed |= print_set_diff(
        &ui,
        "Termux APT package requirements",
        &old.apt_packages,
        &new.apt_packages,
    );
    changed |= print_set_diff(
        &ui,
        "Nix output packages",
        &old.nix_packages,
        &new.nix_packages,
    );
    if let Some(old_plugins) = &old.plugins {
        if let Some(new_plugins) = &new.plugins {
            changed |= print_set_diff(&ui, "Shell plugins", old_plugins, new_plugins);
        }
    }
    changed |= print_command_diff(&ui, old_base, new_base, old, new)?;
    changed |= print_home_file_diff(&ui, old_base, new_base, old, new)?;
    if !changed {
        println!("No recorded changes.");
    }
    Ok(())
}

pub fn diff(old: Option<&str>, new: Option<&str>) -> Result<()> {
    let root = termux_generation_root()?;
    let status = inspect_generations(&root)?;
    let current = status
        .current
        .as_ref()
        .context("no current generation is installed")?;
    let new_id = match new {
        Some(selection) => resolve_generation(&root, selection)?,
        None => current.id.clone(),
    };
    let old_id = match old {
        Some(selection) => resolve_generation(&root, selection)?,
        None => status
            .generations
            .iter()
            .filter(|generation| generation.id != new_id)
            .max_by_key(|generation| generation.number.unwrap_or(0))
            .map(|generation| generation.id.clone())
            .context("no previous generation is available to compare")?,
    };
    print_generation_diff(&root, &old_id, &new_id)
}

pub fn gc(keep: usize, dry_run: bool) -> Result<()> {
    ensure!(
        (1..=1000).contains(&keep),
        "--keep must be between 1 and 1000 generations"
    );
    let root = termux_generation_root()?;
    let bootstrap = root.join("current/bootstrap.sh");
    let ui = Progress::new();
    ui.title();
    ui.stage(
        "Prune old generations and unused Termux APT packages",
        || {
            let mut command = Command::new("bash");
            command
                .arg(&bootstrap)
                .arg("gc")
                .arg("--keep")
                .arg(keep.to_string());
            if dry_run {
                command.arg("--dry-run");
            }
            let status = command.status().with_context(|| {
                format!(
                    "start generation garbage collection via {}",
                    bootstrap.display()
                )
            })?;
            ensure!(
                status.success(),
                "Termux generation garbage collection failed: {status}"
            );
            Ok(())
        },
    )
}

pub fn rollback(generation: &str) -> Result<()> {
    let root = termux_generation_root()?;
    let generation = resolve_generation(&root, generation)?;
    let installer = root.join("current/activate.sh");
    let status = Command::new("bash")
        .arg(installer)
        .arg("rollback")
        .arg(generation)
        .status()
        .context("start Termux generation rollback")?;
    ensure!(
        status.success(),
        "Termux generation rollback failed: {status}"
    );
    Ok(())
}

pub fn fetch(
    cache: Option<&str>,
    store_path: &str,
    destination: &Path,
    public_key: Option<&str>,
    netrc_file: Option<&Path>,
) -> Result<()> {
    let config = load_config()?;
    let cache = cache
        .or(config.defaults.substituter.as_deref())
        .context("no cache specified; pass --cache or set defaults.substituter in the config")?;
    let public_keys = public_key
        .map(|key| vec![key.to_owned()])
        .unwrap_or_else(|| config.defaults.public_keys.clone());
    ensure!(
        !public_keys.is_empty(),
        "no trusted public keys specified; pass --public-key or set defaults.public_keys in the config"
    );
    let store_hash = store_hash(store_path)?;
    let target = parse_cache_target(
        cache,
        config.defaults.aws_credentials_file.as_deref(),
        config.defaults.aws_credentials_command.as_deref(),
    )?;
    let has_credentials = env::var_os("NIXPP_USERNAME").is_some()
        || env::var_os("NIXPP_PASSWORD").is_some()
        || netrc_file.is_some()
        || target.s3.is_some();
    ensure!(
        target.base.scheme() == "https" || !has_credentials,
        "refusing to send cache credentials over plain HTTP"
    );

    let (netrc, remove_netrc) = match (target.s3.as_ref(), netrc_file) {
        (Some(_), Some(_)) => bail!("--netrc-file cannot be used with an S3 substituter"),
        (Some(_), None) => (None, None),
        (None, Some(path)) => {
            validate_netrc(path)?;
            (Some(path.to_path_buf()), None)
        }
        (None, None) => make_netrc(target.base.host_str().context("cache URL has no host")?)?,
    };
    let auth = match target.s3.as_ref() {
        Some(s3) => CacheAuth {
            netrc: None,
            curl_config: Some(make_s3_curl_config(s3)?),
        },
        None => CacheAuth {
            netrc,
            curl_config: None,
        },
    };
    let result = (|| {
        let mut info_url = target.base.clone();
        info_url
            .path_segments_mut()
            .map_err(|_| anyhow::anyhow!("cache URL cannot accept a path"))?
            .pop_if_empty()
            .push(&format!("{store_hash}.narinfo"));
        let narinfo = curl_read(info_url.as_str(), &auth, MAX_NARINFO_SIZE)?;
        let info = parse_nar_info_response(&narinfo)?;
        ensure!(
            info.store_path == store_path,
            "narinfo StorePath does not match requested store path"
        );
        ensure!(
            info.references.is_empty(),
            "refusing cache output with Nix store references"
        );
        verify_any_signature(&info, &public_keys)?;
        ensure!(
            matches!(info.compression.as_str(), "none" | "gzip" | "xz" | "zstd"),
            "unsupported cache compression {:?}; supported formats are none, gzip, xz, and zstd",
            info.compression
        );
        let archive_url = safe_cache_url(&target.base, &info.url)?;
        download_and_extract(&archive_url, &auth, &info, destination)
    })();
    let cleanup_result = remove_netrc.map_or(Ok(()), |path| {
        fs::remove_file(&path).with_context(|| format!("remove temporary netrc {}", path.display()))
    });
    result.and(cleanup_result)
}

pub fn cache_list(json: bool) -> Result<()> {
    let config = load_config()?;
    ensure!(
        !config.defaults.cache_pins.is_empty(),
        "no cache pins configured; set defaults.cache_pins in the nixpp config"
    );
    ensure!(
        !config.defaults.public_keys.is_empty(),
        "no trusted public keys configured; set defaults.public_keys in the nixpp config"
    );
    let cache = config
        .defaults
        .substituter
        .as_deref()
        .context("no cache configured; set defaults.substituter in the nixpp config")?;
    let target = parse_cache_target(
        cache,
        config.defaults.aws_credentials_file.as_deref(),
        config.defaults.aws_credentials_command.as_deref(),
    )?;
    ensure!(
        target.s3.is_some(),
        "nixpp cache list requires an s3:// defaults.substituter"
    );
    let auth = CacheAuth {
        netrc: None,
        curl_config: Some(make_s3_curl_config(
            target.s3.as_ref().expect("S3 target was checked"),
        )?),
    };
    let pins = config
        .defaults
        .cache_pins
        .into_iter()
        .map(|(name, pin)| {
            ensure!(
                !name.is_empty()
                    && name
                        .chars()
                        .all(|character| character.is_ascii_alphanumeric()
                            || "-_".contains(character)),
                "invalid cache pin label {name:?}"
            );
            ensure!(
                !pin.is_empty()
                    && pin
                        .chars()
                        .all(|character| character.is_ascii_alphanumeric()
                            || "-_.".contains(character)),
                "invalid Niks3 pin name for {name:?}"
            );
            let url = safe_cache_url(&target.base, &format!("pins/{pin}"))?;
            let path = curl_read_optional(&url, &auth, 4096)?
                .map(|value| String::from_utf8(value).context("Niks3 pin is not UTF-8"))
                .transpose()?
                .map(|value| value.trim().to_owned());
            let status = if let Some(path) = path.as_deref() {
                let hash = store_hash(path)
                    .with_context(|| format!("Niks3 pin {pin} contains an invalid store path"))?;
                let narinfo_url = safe_cache_url(&target.base, &format!("{hash}.narinfo"))?;
                match curl_read_optional(&narinfo_url, &auth, MAX_NARINFO_SIZE)? {
                    Some(narinfo) => {
                        let info = parse_nar_info_response(&narinfo)?;
                        ensure!(
                            info.store_path == path,
                            "narinfo StorePath does not match Niks3 pin {pin}"
                        );
                        ensure!(
                            info.references.is_empty(),
                            "Niks3 pin {pin} points to an output with Nix store references"
                        );
                        verify_any_signature(&info, &config.defaults.public_keys)?;
                        "cached"
                    }
                    None => "stale",
                }
            } else {
                "missing"
            };
            Ok(CachePin {
                name,
                pin,
                status,
                store_path: path,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    if json {
        println!("{}", serde_json::to_string_pretty(&pins)?);
    } else {
        println!("Configured Niks3 pins:");
        for pin in pins {
            match pin.store_path {
                Some(path) => println!("{}\t{}\t{}", pin.name, pin.status, path),
                None => println!("{}\t{}", pin.name, pin.status),
            }
        }
    }
    Ok(())
}

fn curl_read_optional(url: &str, auth: &CacheAuth, max_size: u64) -> Result<Option<Vec<u8>>> {
    let mut command = Command::new("curl");
    let mut arguments = curl_args(auth, false);
    arguments.retain(|argument| argument != "--fail");
    command
        .args(arguments)
        .args([
            "--max-filesize",
            &max_size.to_string(),
            "--output",
            "-",
            "--write-out",
            "\\n%{http_code}",
            url,
        ])
        .env_remove("NIXPP_USERNAME")
        .env_remove("NIXPP_PASSWORD")
        .stderr(Stdio::inherit());
    let output = run_curl(command, auth).context("start curl")?;
    ensure!(
        output.status.success(),
        "curl failed fetching {url}: {}",
        output.status
    );
    let response = output.stdout;
    let split = response
        .iter()
        .rposition(|byte| *byte == b'\n')
        .context("curl response did not include an HTTP status")?;
    let status = std::str::from_utf8(&response[split + 1..])
        .context("curl returned a non-UTF-8 HTTP status")?;
    let body = &response[..split];
    ensure!(
        body.len() as u64 <= max_size,
        "Niks3 pin response exceeds its size limit"
    );
    match status {
        "200" => Ok(Some(body.to_vec())),
        "404" => Ok(None),
        _ => bail!("unexpected HTTP status {status} fetching {url}"),
    }
}

fn load_config() -> Result<NixppConfig> {
    let path = if let Some(path) = env::var_os("NIXPP_CONFIG") {
        PathBuf::from(path)
    } else {
        let config_home = env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
            .context("cannot locate config; set HOME, XDG_CONFIG_HOME, or NIXPP_CONFIG")?;
        config_home.join("nixpp/config.toml")
    };
    match fs::read_to_string(&path) {
        Ok(contents) => toml::from_str(&contents)
            .with_context(|| format!("parse nixpp config {}", path.display())),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(NixppConfig::default()),
        Err(error) => Err(error).with_context(|| format!("read nixpp config {}", path.display())),
    }
}

fn parse_cache_target(
    value: &str,
    configured_credentials: Option<&Path>,
    credentials_command: Option<&[String]>,
) -> Result<CacheTarget> {
    if value.starts_with("s3://") {
        let s3_url = Url::parse(value).context("invalid S3 cache URL")?;
        ensure!(
            s3_url.scheme() == "s3",
            "cache must use s3://, http://, or https://"
        );
        let bucket = s3_url.host_str().context("S3 cache URL has no bucket")?;
        ensure!(!bucket.is_empty(), "S3 bucket name cannot be empty");
        ensure!(
            s3_url.username().is_empty()
                && s3_url.password().is_none()
                && s3_url.fragment().is_none(),
            "S3 cache URL cannot contain credentials or a fragment"
        );
        let mut options = HashMap::new();
        for (name, value) in s3_url.query_pairs() {
            ensure!(
                matches!(
                    name.as_ref(),
                    "endpoint" | "region" | "scheme" | "profile" | "priority"
                ),
                "unsupported S3 cache option {name:?}"
            );
            ensure!(
                options
                    .insert(name.to_string(), value.to_string())
                    .is_none(),
                "duplicate S3 cache option {name:?}"
            );
        }
        let endpoint = options
            .get("endpoint")
            .context("S3 cache URL requires endpoint=<S3 endpoint>")?;
        let region = options
            .get("region")
            .map(String::as_str)
            .unwrap_or("us-east-1");
        let scheme = options.get("scheme").map(String::as_str).unwrap_or("https");
        let profile = options
            .get("profile")
            .map(String::as_str)
            .unwrap_or("default");
        ensure!(
            matches!(scheme, "https" | "http"),
            "S3 cache scheme must be http or https"
        );
        ensure!(
            scheme == "https",
            "S3 cache credentials require an HTTPS endpoint"
        );
        ensure!(
            !region.is_empty() && !profile.is_empty(),
            "S3 region and profile must be non-empty"
        );
        let endpoint_url =
            Url::parse(&format!("{scheme}://{endpoint}/")).context("invalid S3 endpoint")?;
        ensure!(
            endpoint_url.host_str().is_some()
                && endpoint_url.username().is_empty()
                && endpoint_url.password().is_none()
                && endpoint_url.path() == "/"
                && endpoint_url.query().is_none()
                && endpoint_url.fragment().is_none(),
            "S3 endpoint must be a host name with an optional port"
        );
        let mut base = endpoint_url;
        {
            let mut segments = base.path_segments_mut().expect("hierarchical endpoint URL");
            segments.pop_if_empty();
            segments.push(bucket);
            for segment in s3_url
                .path_segments()
                .into_iter()
                .flatten()
                .filter(|part| !part.is_empty())
            {
                segments.push(segment);
            }
        }
        let credentials = if let Some(command) = credentials_command {
            ensure!(
                !command.is_empty() && command.iter().all(|part| !part.is_empty()),
                "defaults.aws_credentials_command must contain a program and non-empty arguments"
            );
            AwsCredentialSource::Command(command.to_vec())
        } else {
            AwsCredentialSource::File(s3_credentials_path(configured_credentials)?)
        };
        Ok(CacheTarget {
            base,
            s3: Some(S3Cache {
                region: region.to_owned(),
                profile: profile.to_owned(),
                credentials,
            }),
        })
    } else {
        Ok(CacheTarget {
            base: parse_http_cache_url(value)?,
            s3: None,
        })
    }
}

fn s3_credentials_path(configured: Option<&Path>) -> Result<PathBuf> {
    let path = env::var_os("AWS_SHARED_CREDENTIALS_FILE")
        .map(PathBuf::from)
        .or_else(|| configured.map(Path::to_path_buf))
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".aws/credentials")))
        .context("cannot locate AWS credentials; set AWS_SHARED_CREDENTIALS_FILE or defaults.aws_credentials_file")?;
    Ok(expand_home(&path))
}

fn expand_home(path: &Path) -> PathBuf {
    if path == Path::new("~") {
        return env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| path.to_path_buf());
    }
    if let Ok(value) = path.strip_prefix("~") {
        if let Some(home) = env::var_os("HOME") {
            return PathBuf::from(home).join(value);
        }
    }
    path.to_path_buf()
}

fn make_s3_curl_config(s3: &S3Cache) -> Result<String> {
    let (access_key, secret_key, session_token) = match &s3.credentials {
        AwsCredentialSource::File(path) => load_aws_profile(path, &s3.profile)?,
        AwsCredentialSource::Command(command) => load_aws_credentials_command(command)?,
    };
    let mut config = format!(
        "aws-sigv4 = \"aws:amz:{}:s3\"\nuser = \"{}:{}\"\n",
        curl_config_escape(&s3.region),
        curl_config_escape(&access_key),
        curl_config_escape(&secret_key)
    );
    if let Some(token) = session_token {
        config.push_str(&format!(
            "header = \"x-amz-security-token: {}\"\n",
            curl_config_escape(&token)
        ));
    }
    Ok(config)
}

fn load_aws_credentials_command(command: &[String]) -> Result<(String, String, Option<String>)> {
    ensure!(!command.is_empty(), "AWS credentials command is empty");
    let output = Command::new(&command[0])
        .args(&command[1..])
        .env_remove("NIXPP_USERNAME")
        .env_remove("NIXPP_PASSWORD")
        .output()
        .with_context(|| format!("start AWS credentials command {}", command[0]))?;
    ensure!(
        output.status.success(),
        "AWS credentials command {} failed: {}",
        command[0],
        output.status
    );
    let value: serde_json::Value = serde_json::from_slice(&output.stdout)
        .context("AWS credentials command must output rbw JSON")?;
    let data = value
        .get("data")
        .context("rbw JSON is missing its data object")?;
    ensure!(
        data.get("type").and_then(serde_json::Value::as_str) == Some("Login"),
        "rbw AWS credentials entry must be a Login item"
    );
    let access_key = data
        .get("username")
        .and_then(serde_json::Value::as_str)
        .context("rbw AWS credentials entry is missing its username")?
        .to_owned();
    let secret_key = data
        .get("password")
        .and_then(serde_json::Value::as_str)
        .context("rbw AWS credentials entry is missing its password")?
        .to_owned();
    let session_token = value
        .get("fields")
        .and_then(serde_json::Value::as_array)
        .and_then(|fields| {
            fields.iter().find_map(|field| {
                let name = field.get("name")?.as_str()?;
                if name.eq_ignore_ascii_case("aws_session_token") {
                    field.get("value")?.as_str().map(str::to_owned)
                } else {
                    None
                }
            })
        });
    validate_aws_credentials(access_key, secret_key, session_token)
}

fn curl_config_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
}

fn load_aws_profile(path: &Path, profile: &str) -> Result<(String, String, Option<String>)> {
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("inspect AWS credentials file {}", path.display()))?;
    ensure!(
        metadata.file_type().is_file(),
        "AWS credentials path must be a regular file"
    );
    ensure!(
        metadata.permissions().mode() & 0o077 == 0,
        "AWS credentials file must have mode 0600 or stricter"
    );
    let contents = fs::read_to_string(path)
        .with_context(|| format!("read AWS credentials file {}", path.display()))?;
    let mut current_profile = "default";
    let mut fields = HashMap::<String, String>::new();
    for line in contents.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            current_profile = line[1..line.len() - 1].trim();
            continue;
        }
        if current_profile != profile {
            continue;
        }
        if let Some((name, value)) = line.split_once('=') {
            fields.insert(name.trim().to_owned(), value.trim().to_owned());
        }
    }
    let access_key = fields
        .remove("aws_access_key_id")
        .context("AWS profile is missing aws_access_key_id")?;
    let secret_key = fields
        .remove("aws_secret_access_key")
        .context("AWS profile is missing aws_secret_access_key")?;
    let session_token = fields.remove("aws_session_token");
    validate_aws_credentials(access_key, secret_key, session_token)
}

fn validate_aws_credentials(
    access_key: String,
    secret_key: String,
    session_token: Option<String>,
) -> Result<(String, String, Option<String>)> {
    ensure!(
        !access_key.is_empty()
            && !secret_key.is_empty()
            && !access_key.contains(['\n', '\r'])
            && !secret_key.contains(['\n', '\r'])
            && session_token
                .as_ref()
                .is_none_or(|token| !token.is_empty() && !token.contains(['\n', '\r'])),
        "AWS credentials are invalid"
    );
    Ok((access_key, secret_key, session_token))
}

fn parse_http_cache_url(value: &str) -> Result<Url> {
    let url = Url::parse(value).context("cache must be an HTTP(S) or S3 URL")?;
    ensure!(
        matches!(url.scheme(), "http" | "https"),
        "cache must be an HTTP(S) or S3 URL"
    );
    ensure!(url.host_str().is_some(), "cache URL has no host");
    ensure!(
        url.username().is_empty() && url.password().is_none(),
        "cache URL must not contain credentials"
    );
    ensure!(
        url.query().is_none() && url.fragment().is_none(),
        "HTTP cache URL must not contain a query or fragment"
    );
    Ok(url)
}

pub fn switch_profile(
    flake: Option<&str>,
    builder: Option<&str>,
    public_key: Option<&str>,
) -> Result<()> {
    switch_profile_with_source(flake, builder, public_key, false, false)
}

pub fn upgrade_profile(dry_run: bool) -> Result<()> {
    switch_profile_with_source(None, None, None, true, dry_run)
}

fn switch_profile_with_source(
    flake: Option<&str>,
    builder: Option<&str>,
    public_key: Option<&str>,
    use_s3: bool,
    dry_run: bool,
) -> Result<()> {
    let config = load_config()?;
    let flake = flake
        .or(config.defaults.flake.as_deref())
        .context("no flake specified; pass --flake or set defaults.flake in the config")?;
    let builders = builder
        .map(|builder| vec![builder.to_owned()])
        .unwrap_or_else(|| config.defaults.configured_builders());
    let public_keys = public_key
        .map(|key| vec![key.to_owned()])
        .unwrap_or_else(|| config.defaults.public_keys.clone());
    ensure!(
        !public_keys.is_empty(),
        "no trusted public keys specified; pass --public-key or set defaults.public_keys in the config"
    );
    let substituter = if use_s3 {
        let value = config
            .defaults
            .substituter
            .as_deref()
            .context("no S3 substituter configured; set defaults.substituter in the config")?;
        let target = parse_cache_target(
            value,
            config.defaults.aws_credentials_file.as_deref(),
            config.defaults.aws_credentials_command.as_deref(),
        )?;
        ensure!(
            target.s3.is_some(),
            "nixpp upgrade requires an s3:// defaults.substituter"
        );
        Some(value)
    } else {
        None
    };
    let generation_root = termux_generation_root()?;
    let previous_generation = if use_s3 {
        inspect_generations(&generation_root)?
            .current
            .map(|generation| generation.id)
    } else {
        None
    };
    ensure!(!flake.is_empty(), "--flake is required");
    ensure!(
        flake.len() <= 4096 && !flake.contains(['\0', '\r', '\n']),
        "flake installable is invalid or too long"
    );
    ensure!(
        !builders.is_empty(),
        "no builders specified; pass --builder or set defaults.builders in the config"
    );
    for builder in &builders {
        ensure!(
            valid_ssh_target(builder),
            "builder must be an SSH host or user@host alias without command-line options: {builder}"
        );
    }
    ensure!(
        env::var("PREFIX").as_deref() == Ok("/data/data/com.termux/files/usr"),
        "switch must run inside the standard Termux app shell"
    );
    ensure!(
        Command::new("bash")
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok(),
        "Termux bash is required to activate a generation"
    );

    let ui = Progress::new();
    ui.title();
    let mut selected_builder = String::new();
    let mut store_path = String::new();
    ui.stage("Build the configured flake", || {
        let mut failures = Vec::new();
        for candidate in &builders {
            match remote_build(candidate, flake) {
                Ok(path) => {
                    selected_builder.clone_from(candidate);
                    store_path = path;
                    return Ok(());
                }
                Err(error) => failures.push(format!("{candidate}: {error:#}")),
            }
        }
        anyhow::bail!("all configured builders failed: {}", failures.join("; "))
    })?;
    let builder = selected_builder.as_str();

    let mut remote_temp = None;
    let stage = make_staging_directory("nixpp-switch-")?;
    let result = (|| {
        let bundle_dir = stage.join("bundle");
        if let Some(cache) = substituter {
            ui.stage("Fetch and verify the bundle from the S3 cache", || {
                fetch(Some(cache), &store_path, &bundle_dir, None, None)
                    .context("fetch built Termux bundle from the configured S3 cache")?;
                Ok(())
            })?;
        } else {
            let mut info = None;
            ui.stage("Sign and inspect the Nix output", || {
                let path = remote_output_cache(builder, &store_path)?;
                remote_temp = Some(path.clone());
                let store_hash = store_hash(&store_path)?;
                let metadata_path = format!("{path}/cache/{store_hash}.narinfo");
                let data =
                    remote_output(builder, &format!("cat -- {}", shell_quote(&metadata_path)))?;
                let parsed = parse_nar_info(data.as_bytes())?;
                ensure!(
                    parsed.store_path == store_path,
                    "builder metadata StorePath does not match the requested flake output"
                );
                ensure!(
                    parsed.references.is_empty(),
                    "refusing Termux bundle with Nix store references"
                );
                verify_any_signature(&parsed, &public_keys).context("verify builder signature")?;
                info = Some(parsed);
                Ok(())
            })?;
            let info = info.context("builder returned no Nix metadata")?;
            ui.stage("Transfer and verify the bundle", || {
                let nar_path = stage.join("output.nar");
                remote_nar(builder, &store_path, &nar_path, info.nar_size)?;
                extract_verified_nar(&nar_path, &info, &bundle_dir)
            })?;
        }

        let archive_path = bundle_dir.join("environment.tar.gz");
        let digest = read_archive_digest(&bundle_dir.join("SHA256SUMS"))?;
        verify_file_sha256(&archive_path, &digest).context("verify Termux archive")?;
        let bootstrap_path = bundle_dir.join("bootstrap.sh");
        ensure!(
            fs::metadata(&bootstrap_path).is_ok_and(|metadata| metadata.file_type().is_file()),
            "Termux bundle is missing a regular bootstrap.sh"
        );
        if dry_run {
            let preview_home = stage.join("preview-home");
            fs::create_dir_all(&preview_home).context("create preview home")?;
            ui.stage("Preflight the bundle without activating", || {
                let status = Command::new("bash")
                    .arg(&bootstrap_path)
                    .arg("preflight")
                    .arg(&archive_path)
                    .arg(&digest)
                    .env("HOME", &preview_home)
                    .status()
                    .context("start upgrade preflight")?;
                ensure!(status.success(), "upgrade preflight failed: {status}");
                Ok(())
            })?;
            let preview_root = preview_home.join(".local/share/termux-native");
            if let Some(previous) = previous_generation.as_deref() {
                let installed = generation_root.join("generations").join(previous);
                ensure!(installed.is_dir(), "active generation directory is missing");
                let old_numbers = generation_numbers(&generation_root)?;
                let old_pins = generation_pins(&generation_root)?;
                let old = inspect_generation(
                    &generation_root,
                    previous,
                    old_numbers.get(previous).copied(),
                    old_pins.contains(previous),
                )?;
                let new = inspect_generation(&preview_root, &digest, None, false)?;
                print_generation_diff_infos(&generation_root, &preview_root, &old, &new)?;
            } else {
                println!(
                    "Previewed generation {} (no installed generation to compare).",
                    &digest[..12]
                );
            }
            println!("Dry run complete; no generation was activated.");
            return Ok(());
        }
        ui.stage("Install and health-check the new generation", || {
            let status = Command::new("bash")
                .arg(&bootstrap_path)
                .arg("install")
                .arg(&archive_path)
                .arg(&digest)
                .status()
                .context("start Termux generation activation")?;
            ensure!(status.success(), "activate Termux generation: {status}");
            Ok(())
        })
    })();
    let cleanup = fs::remove_dir_all(&stage)
        .with_context(|| format!("remove local staging directory {}", stage.display()));
    let result = result.and(cleanup);
    if let Some(path) = remote_temp
        && let Err(error) = remote_run(builder, &format!("rm -rf -- {}", shell_quote(&path)))
    {
        ui.warning(&format!(
            "could not remove temporary builder output {path}: {error:#}"
        ));
    }
    result?;
    if let Some(previous) = previous_generation {
        match inspect_generations(&generation_root) {
            Ok(status) => {
                if let Some(current) = status.current
                    && current.id != previous
                {
                    let diff = Command::new(generation_root.join("current/bin/nixpp"))
                        .env_remove("TERMUX_GENERATION")
                        .arg("diff")
                        .arg(&previous)
                        .arg(&current.id)
                        .status();
                    match diff {
                        Ok(status) if status.success() => {}
                        Ok(status) => ui.warning(&format!(
                            "upgrade succeeded, but generation diff exited with {status}"
                        )),
                        Err(error) => ui.warning(&format!(
                            "upgrade succeeded, but could not run the new generation diff: {error}"
                        )),
                    }
                }
            }
            Err(error) => ui.warning(&format!(
                "upgrade succeeded, but could not inspect the active generation for a diff: {error:#}"
            )),
        }
    }
    Ok(())
}

fn remote_build(builder: &str, flake: &str) -> Result<String> {
    let command = format!(
        "nix build --refresh --accept-flake-config --no-link --print-out-paths -- {}",
        shell_quote(flake)
    );
    let output =
        remote_output(builder, &command).with_context(|| format!("build flake on {builder}"))?;
    let paths: Vec<_> = output.split_whitespace().collect();
    ensure!(
        paths.len() == 1 && valid_store_path(paths[0]),
        "flake build must produce exactly one valid /nix/store output path"
    );
    Ok(paths[0].to_owned())
}

fn remote_output_cache(builder: &str, store_path: &str) -> Result<String> {
    let output = remote_output(builder, "mktemp -d /tmp/nixpp-switch.XXXXXXXX")
        .context("create temporary cache on builder")?;
    let path = output.trim();
    ensure!(
        valid_remote_temp(path),
        "builder returned an unsafe temporary directory"
    );
    let command = format!(
        "references=$(nix-store -q --references {store}) && \
         if [ -n \"$references\" ]; then echo 'Termux output has Nix references' >&2; exit 1; fi && \
         mkdir -- {cache} && nix copy --to {cache_url} {store}",
        store = shell_quote(store_path),
        cache = shell_quote(&format!("{path}/cache")),
        cache_url = shell_quote(&format!("file://{path}/cache")),
    );
    if let Err(error) = remote_run(builder, &command) {
        let _ = remote_run(builder, &format!("rm -rf -- {}", shell_quote(path)));
        return Err(error).context("sign and export output on builder");
    }
    Ok(path.to_owned())
}

fn remote_nar(builder: &str, store_path: &str, destination: &Path, maximum: u64) -> Result<()> {
    let mut file = create_temp_file(destination)?;
    let temp_path = file.path.clone();
    let mut child = Command::new("ssh")
        .args(["-T", "--", builder])
        .arg(format!("nix nar pack {}", shell_quote(store_path)))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .with_context(|| format!("start NAR transfer from {builder}"))?;
    let mut stdout = child
        .stdout
        .take()
        .context("SSH process has no NAR output pipe")?;
    let transfer = io::copy(&mut stdout.by_ref().take(maximum + 1), &mut file.file);
    let count = match transfer {
        Ok(count) => count,
        Err(error) => {
            let _ = child.kill();
            let _ = child.wait();
            return Err(error).context("receive NAR from builder");
        }
    };
    if count > maximum {
        let _ = child.kill();
        let _ = child.wait();
        bail!("builder NAR exceeds its signed size limit");
    }
    let status = child.wait().context("wait for NAR transfer")?;
    ensure!(status.success(), "receive NAR from {builder}: {status}");
    file.file.sync_all().context("sync NAR file")?;
    fs::rename(&temp_path, destination).with_context(|| {
        format!(
            "move verified NAR staging file to {}",
            destination.display()
        )
    })?;
    Ok(())
}

fn remote_output(builder: &str, remote_command: &str) -> Result<String> {
    let output = Command::new("ssh")
        .args(["-T", "--", builder, remote_command])
        .output()
        .with_context(|| format!("start ssh to {builder}"))?;
    io::stderr()
        .write_all(&output.stderr)
        .context("write SSH diagnostics")?;
    ensure!(
        output.status.success(),
        "ssh {builder} exited with {}",
        output.status
    );
    String::from_utf8(output.stdout).context("SSH output is not valid UTF-8")
}

fn remote_run(builder: &str, remote_command: &str) -> Result<()> {
    remote_output(builder, remote_command).map(|_| ())
}

fn valid_ssh_target(target: &str) -> bool {
    !target.is_empty()
        && !target.starts_with('-')
        && target
            .chars()
            .all(|char| char.is_ascii_alphanumeric() || "._@-".contains(char))
}

fn valid_store_path(path: &str) -> bool {
    let Some(base) = path.strip_prefix("/nix/store/") else {
        return false;
    };
    let Some((hash, name)) = base.split_once('-') else {
        return false;
    };
    hash.len() == 32
        && hash.bytes().all(|byte| NIX_BASE32.contains(&byte))
        && !name.is_empty()
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"+._?=-".contains(&byte))
}

fn store_hash(store_path: &str) -> Result<&str> {
    ensure!(valid_store_path(store_path), "invalid full Nix store path");
    Ok(store_path
        .strip_prefix("/nix/store/")
        .and_then(|path| path.split_once('-'))
        .map(|(hash, _)| hash)
        .expect("validated store path contains a hash separator"))
}

fn valid_remote_temp(path: &str) -> bool {
    let Some(suffix) = path.strip_prefix("/tmp/nixpp-switch.") else {
        return false;
    };
    suffix.len() == 8 && suffix.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}

struct TempFile {
    file: File,
    path: PathBuf,
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn create_temp_file(destination: &Path) -> Result<TempFile> {
    let parent = destination
        .parent()
        .context("destination has no parent directory")?;
    let (path, file) = create_private_file(parent, ".nixpp")?;
    Ok(TempFile { file, path })
}

fn create_private_file(parent: &Path, prefix: &str) -> Result<(PathBuf, File)> {
    for attempt in 0..32u32 {
        let path = parent.join(format!(
            "{prefix}-{}-{}-{attempt}.tmp",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        match OpenOptions::new()
            .write(true)
            .read(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
        {
            Ok(file) => return Ok((path, file)),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error).with_context(|| format!("create {}", path.display())),
        }
    }
    bail!(
        "could not create a unique temporary file in {}",
        parent.display()
    )
}

fn safe_cache_url(base: &Url, path: &str) -> Result<String> {
    ensure!(
        !path.is_empty()
            && path
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"-._~/".contains(&byte))
            && !path.starts_with('/')
            && !path.contains('\\'),
        "narinfo URL is not a safe relative path"
    );
    ensure!(
        path.split('/')
            .all(|segment| !segment.is_empty() && segment != "." && segment != ".."),
        "narinfo URL contains an unsafe path component"
    );
    let mut result = base.clone();
    {
        let mut segments = result
            .path_segments_mut()
            .map_err(|_| anyhow::anyhow!("cache URL cannot accept a path"))?;
        segments.pop_if_empty();
        segments.extend(path.split('/'));
    }
    Ok(result.into())
}

fn validate_netrc(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("cannot read netrc file {}", path.display()))?;
    ensure!(
        metadata.file_type().is_file(),
        "netrc file must be a regular file"
    );
    ensure!(
        metadata.permissions().mode() & 0o077 == 0,
        "netrc file must have permissions 0600 or stricter"
    );
    Ok(())
}

fn make_netrc(host: &str) -> Result<(Option<PathBuf>, Option<PathBuf>)> {
    let username = env::var("NIXPP_USERNAME").ok();
    let password = env::var("NIXPP_PASSWORD").ok();
    if username.is_none() && password.is_none() {
        return Ok((None, None));
    }
    let (Some(username), Some(password)) = (username, password) else {
        bail!("NIXPP_USERNAME and NIXPP_PASSWORD must be set together");
    };
    ensure!(
        !username.contains(['\0', '\n', '\r']) && !password.contains(['\0', '\n', '\r']),
        "cache credentials contain a forbidden line break"
    );
    let (path, mut file) = create_private_file(&env::temp_dir(), ".nixpp-netrc")?;
    let write_result = (|| {
        file.set_permissions(fs::Permissions::from_mode(0o600))?;
        writeln!(
            file,
            "machine {host} login {} password {}",
            netrc_quote(&username),
            netrc_quote(&password)
        )
        .context("write temporary netrc")?;
        file.sync_all().context("sync temporary netrc")
    })();
    drop(file);
    if let Err(error) = write_result {
        return match fs::remove_file(&path) {
            Ok(()) => Err(error),
            Err(cleanup_error) => Err(error.context(format!(
                "also failed to remove temporary netrc: {cleanup_error}"
            ))),
        };
    }
    Ok((Some(path.clone()), Some(path)))
}

fn netrc_quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn curl_args(auth: &CacheAuth, progress: bool) -> Vec<String> {
    let mut arguments = vec![
        "--fail".to_owned(),
        "--show-error".to_owned(),
        "--location".to_owned(),
        "--proto".to_owned(),
        "=https,http".to_owned(),
        "--max-time".to_owned(),
        "7200".to_owned(),
    ];
    if progress && io::stderr().is_terminal() {
        arguments.push("--progress-bar".to_owned());
    } else {
        arguments.push("--silent".to_owned());
    }
    if let Some(path) = auth.netrc.as_deref() {
        arguments.extend(["--netrc-file".to_owned(), path.display().to_string()]);
    }
    if auth.curl_config.is_some() {
        arguments.extend(["--config".to_owned(), "-".to_owned()]);
    }
    arguments
}

fn run_curl(mut command: Command, auth: &CacheAuth) -> io::Result<Output> {
    if let Some(config) = auth.curl_config.as_deref() {
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(config.as_bytes())?;
        }
        child.wait_with_output()
    } else {
        command.output()
    }
}

fn curl_read(url: &str, auth: &CacheAuth, max_size: u64) -> Result<Vec<u8>> {
    let mut command = Command::new("curl");
    command
        .args(curl_args(auth, false))
        .args([
            "--max-filesize",
            &max_size.to_string(),
            "--output",
            "-",
            url,
        ])
        .env_remove("NIXPP_USERNAME")
        .env_remove("NIXPP_PASSWORD")
        .stderr(Stdio::inherit());
    let output = run_curl(command, auth).context("start curl")?;
    ensure!(
        output.status.success(),
        "curl failed fetching {url}: {}",
        output.status
    );
    ensure!(
        output.stdout.len() as u64 <= max_size,
        "narinfo response exceeds its size limit"
    );
    Ok(output.stdout)
}

fn parse_nar_info(data: &[u8]) -> Result<NarInfo> {
    let text = std::str::from_utf8(data).context("narinfo is not UTF-8")?;
    let mut fields = std::collections::HashMap::<&str, Vec<&str>>::new();
    for line in text.lines() {
        if line.is_empty() {
            continue;
        }
        let (key, value) = line
            .split_once(": ")
            .with_context(|| format!("malformed narinfo line {line:?}"))?;
        fields.entry(key).or_default().push(value);
    }
    let one = |key: &str| -> Result<&str> {
        let values = fields
            .get(key)
            .with_context(|| format!("narinfo is missing {key}"))?;
        ensure!(
            values.len() == 1,
            "narinfo must contain exactly one {key} field"
        );
        Ok(values[0])
    };
    let store_path = one("StorePath")?.to_owned();
    ensure!(
        valid_store_path(&store_path),
        "narinfo contains an invalid StorePath"
    );
    let url = one("URL")?.to_owned();
    let compression_values = fields.get("Compression");
    ensure!(
        compression_values.is_none_or(|values| values.len() == 1),
        "narinfo has duplicate Compression fields"
    );
    let compression = compression_values
        .and_then(|values| values.first())
        .copied()
        .unwrap_or("bzip2")
        .to_owned();
    let nar_hash = one("NarHash")?.to_owned();
    let nar_size = one("NarSize")?.parse::<u64>().context("invalid NarSize")?;
    ensure!(
        (1..=MAX_NAR_SIZE).contains(&nar_size),
        "NarSize is outside the supported safety limit"
    );
    let references = one("References")?
        .split_ascii_whitespace()
        .map(str::to_owned)
        .collect();
    let signatures = fields
        .get("Sig")
        .into_iter()
        .flatten()
        .map(|value| (*value).to_owned())
        .collect();
    let file_hash = optional_single(&fields, "FileHash")?.map(str::to_owned);
    let file_size = optional_single(&fields, "FileSize")?
        .map(|value| value.parse::<u64>().context("invalid FileSize"))
        .transpose()?;
    if let Some(size) = file_size {
        ensure!(
            size > 0 && size <= nar_size.saturating_add(1 << 20),
            "FileSize is outside the supported safety limit"
        );
    }
    Ok(NarInfo {
        store_path,
        url,
        compression,
        nar_hash,
        nar_size,
        file_hash,
        file_size,
        references,
        signatures,
    })
}

fn parse_nar_info_response(data: &[u8]) -> Result<NarInfo> {
    if data.starts_with(ZSTD_MAGIC) {
        let decoder = ruzstd::decoding::StreamingDecoder::new(data)
            .context("start Zstandard narinfo decompressor")?;
        let mut decoded = Vec::new();
        decoder
            .take(MAX_NARINFO_SIZE + 1)
            .read_to_end(&mut decoded)
            .context("decompress Zstandard narinfo")?;
        ensure!(
            decoded.len() as u64 <= MAX_NARINFO_SIZE,
            "decompressed narinfo exceeds its size limit"
        );
        parse_nar_info(&decoded)
    } else {
        parse_nar_info(data)
    }
}

fn optional_single<'a>(
    fields: &'a std::collections::HashMap<&str, Vec<&'a str>>,
    key: &str,
) -> Result<Option<&'a str>> {
    let Some(values) = fields.get(key) else {
        return Ok(None);
    };
    ensure!(values.len() == 1, "narinfo has duplicate {key} fields");
    Ok(values.first().copied())
}

fn verify_signature(info: &NarInfo, public_key: &str) -> Result<()> {
    let (name, encoded_key) = public_key
        .split_once(':')
        .context("public key must use Nix cache format NAME:BASE64")?;
    ensure!(!name.is_empty(), "public key name cannot be empty");
    let key_bytes = BASE64
        .decode(encoded_key)
        .context("invalid Ed25519 cache public key")?;
    let key_array: [u8; 32] = key_bytes
        .try_into()
        .map_err(|_| anyhow::anyhow!("invalid Ed25519 cache public key length"))?;
    let key = VerifyingKey::from_bytes(&key_array).context("invalid Ed25519 cache public key")?;
    let nar_hash = info
        .nar_hash
        .strip_prefix("sha256:")
        .context("narinfo NarHash must use SHA-256")?;
    let _ = nix_base32_decode(nar_hash)?;
    let mut references = info.references.clone();
    references.sort_unstable();
    let fingerprint = format!(
        "1;{};sha256:{};{};{}",
        info.store_path,
        nar_hash,
        info.nar_size,
        references.join(",")
    );
    for value in &info.signatures {
        let Some((key_name, encoded_signature)) = value.split_once(':') else {
            continue;
        };
        if key_name != name {
            continue;
        }
        let Ok(signature_bytes) = BASE64.decode(encoded_signature) else {
            continue;
        };
        let Ok(signature) = Signature::from_slice(&signature_bytes) else {
            continue;
        };
        if key.verify(fingerprint.as_bytes(), &signature).is_ok() {
            return Ok(());
        }
    }
    bail!("narinfo has no valid signature from trusted cache key {name:?}")
}

fn verify_any_signature(info: &NarInfo, public_keys: &[String]) -> Result<()> {
    let mut last_error = None;
    for public_key in public_keys {
        match verify_signature(info, public_key) {
            Ok(()) => return Ok(()),
            Err(error) => last_error = Some(error),
        }
    }
    let names = public_keys
        .iter()
        .filter_map(|key| key.split_once(':').map(|(name, _)| name))
        .collect::<Vec<_>>()
        .join(", ");
    Err(last_error.unwrap_or_else(|| anyhow::anyhow!("no trusted cache keys configured"))).context(
        format!("narinfo has no valid signature from configured cache keys ({names})"),
    )
}

fn download_and_extract(
    url: &str,
    auth: &CacheAuth,
    info: &NarInfo,
    destination: &Path,
) -> Result<()> {
    match fs::symlink_metadata(destination) {
        Ok(_) => bail!("destination already exists: {}", destination.display()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(error).with_context(|| format!("inspect {}", destination.display()));
        }
    }
    let parent = destination
        .parent()
        .context("destination has no parent directory")?;
    fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    let stage = create_temp_dir(parent, ".nixpp-stage")?;
    let result = (|| {
        let compressed_path = stage.join("download");
        let compressed_limit = info
            .file_size
            .unwrap_or_else(|| info.nar_size.saturating_add(1 << 20));
        curl_download(url, auth, &compressed_path, compressed_limit)?;
        let (file_hash, file_size) = hash_file(&compressed_path)?;
        if let Some(expected_size) = info.file_size {
            ensure!(
                file_size == expected_size,
                "downloaded NAR file size mismatch"
            );
        } else {
            ensure!(
                file_size <= compressed_limit,
                "compressed NAR exceeds safety limit"
            );
        }
        if let Some(expected_hash) = &info.file_hash {
            ensure!(
                file_hash == decode_nix_hash(expected_hash)?,
                "downloaded NAR file hash mismatch"
            );
        }

        let nar_path = stage.join("archive.nar");
        decompress_to_file(
            &info.compression,
            &compressed_path,
            &nar_path,
            info.nar_size,
        )?;
        let (nar_hash, nar_size) = hash_file(&nar_path)?;
        ensure!(nar_size == info.nar_size, "uncompressed NAR size mismatch");
        ensure!(
            nar_hash == decode_nix_hash(&info.nar_hash)?,
            "NAR hash mismatch"
        );
        let mut nar_file = File::open(&nar_path).context("open verified NAR")?;
        let output = stage.join("output");
        extract_nar(&mut nar_file, &output)?;
        fs::remove_file(&compressed_path).context("remove compressed download")?;
        fs::remove_file(&nar_path).context("remove extracted NAR archive")?;
        fs::rename(&output, destination)
            .with_context(|| format!("activate output at {}", destination.display()))?;
        Ok(())
    })();
    let cleanup = fs::remove_dir_all(&stage)
        .with_context(|| format!("remove staging directory {}", stage.display()));
    result.and(cleanup)
}

fn curl_download(url: &str, auth: &CacheAuth, destination: &Path, maximum: u64) -> Result<()> {
    let mut command = Command::new("curl");
    command
        .args(curl_args(auth, true))
        .args(["--max-filesize", &maximum.to_string(), "--output"])
        .arg(destination)
        .arg(url)
        .env_remove("NIXPP_USERNAME")
        .env_remove("NIXPP_PASSWORD");
    if io::stderr().is_terminal() {
        command.stderr(Stdio::inherit());
    }
    let output = run_curl(command, auth).context("start curl")?;
    ensure!(
        output.status.success(),
        "curl failed fetching NAR: {}: {}",
        output.status,
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(())
}

fn hash_file(path: &Path) -> Result<(Vec<u8>, u64)> {
    let mut file = File::open(path).with_context(|| format!("open {}", path.display()))?;
    let mut hasher = Sha256::new();
    let size = io::copy(&mut file, &mut hasher).context("hash file")?;
    Ok((hasher.finalize().to_vec(), size))
}

fn verify_file_sha256(path: &Path, expected: &str) -> Result<()> {
    ensure!(hex(&hash_file(path)?.0) == expected, "SHA-256 mismatch");
    Ok(())
}

fn read_archive_digest(path: &Path) -> Result<String> {
    let metadata = fs::metadata(path).with_context(|| format!("read {}", path.display()))?;
    ensure!(metadata.len() <= 4096, "SHA256SUMS is unexpectedly large");
    let data = fs::read_to_string(path).context("read SHA256SUMS")?;
    let lines: Vec<_> = data.trim().lines().collect();
    ensure!(
        lines.len() == 1,
        "SHA256SUMS must contain exactly one archive entry"
    );
    let fields: Vec<_> = lines[0].split_ascii_whitespace().collect();
    ensure!(
        fields.len() == 2 && fields[1] == "environment.tar.gz",
        "SHA256SUMS must contain the environment.tar.gz SHA-256"
    );
    ensure!(
        fields[0].len() == 64
            && fields[0]
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase()),
        "SHA256SUMS contains an invalid lowercase SHA-256"
    );
    Ok(fields[0].to_owned())
}

fn hex(value: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(value.len() * 2);
    for byte in value {
        output.push(DIGITS[(byte >> 4) as usize] as char);
        output.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    output
}

fn make_staging_directory(prefix: &str) -> Result<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(value) = env::var_os("TMPDIR") {
        candidates.push(PathBuf::from(value));
    }
    if let Some(value) = env::var_os("PREFIX") {
        candidates.push(PathBuf::from(value).join("tmp"));
    }
    candidates.push(env::temp_dir());
    make_staging_directory_in(candidates, prefix)
}

fn make_staging_directory_in(candidates: Vec<PathBuf>, prefix: &str) -> Result<PathBuf> {
    let mut candidates = candidates;
    candidates.dedup();
    let mut last_error = None;
    for parent in candidates {
        match create_temp_dir(&parent, prefix) {
            Ok(path) => return Ok(path),
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| anyhow::anyhow!("no temporary directory is available")))
}

fn create_temp_dir(parent: &Path, prefix: &str) -> Result<PathBuf> {
    for attempt in 0..32u32 {
        let path = parent.join(format!(
            "{prefix}-{}-{}-{attempt}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        match fs::create_dir(&path) {
            Ok(()) => {
                fs::set_permissions(&path, fs::Permissions::from_mode(0o700))?;
                return Ok(path);
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error).with_context(|| format!("create {}", path.display())),
        }
    }
    bail!(
        "could not create a unique temporary directory under {}",
        parent.display()
    )
}

fn decompress_to_file(
    compression: &str,
    source: &Path,
    destination: &Path,
    maximum: u64,
) -> Result<()> {
    match compression {
        "none" => {
            let mut input = File::open(source).context("open NAR file")?;
            let mut output = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(destination)
                .context("create NAR file")?;
            let size = io::copy(&mut Read::by_ref(&mut input).take(maximum + 1), &mut output)?;
            ensure!(size <= maximum, "NAR exceeds its signed size limit");
            output.sync_all().context("sync NAR file")
        }
        "gzip" => run_decompressor("gzip", source, destination, maximum),
        "xz" => run_decompressor("xz", source, destination, maximum),
        "zstd" => {
            let input = File::open(source).context("open compressed NAR file")?;
            let mut decoder = ruzstd::decoding::StreamingDecoder::new(input)
                .context("start Zstandard NAR decompressor")?;
            let mut output = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(destination)
                .context("create NAR file")?;
            let size = io::copy(&mut decoder.by_ref().take(maximum + 1), &mut output)
                .context("decompress Zstandard NAR")?;
            ensure!(
                size <= maximum,
                "uncompressed NAR exceeds its signed size limit"
            );
            output.sync_all().context("sync NAR file")
        }
        other => bail!("unsupported cache compression {other:?}"),
    }
}

fn run_decompressor(program: &str, source: &Path, destination: &Path, maximum: u64) -> Result<()> {
    let mut child = Command::new(program)
        .args(["-dc", "--"])
        .arg(source)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("start {program} decompressor"))?;
    let mut stdout = child
        .stdout
        .take()
        .context("decompressor has no output pipe")?;
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(destination)
        .context("create NAR file")?;
    let size =
        io::copy(&mut stdout.by_ref().take(maximum + 1), &mut output).context("decompress NAR")?;
    if size > maximum {
        let _ = child.kill();
        let _ = child.wait();
        bail!("uncompressed NAR exceeds its signed size limit");
    }
    output.sync_all().context("sync NAR file")?;
    drop(output);
    let result = child.wait_with_output().context("wait for decompressor")?;
    ensure!(
        result.status.success(),
        "{program} decompression failed: {}",
        String::from_utf8_lossy(&result.stderr).trim()
    );
    Ok(())
}

fn decode_nix_hash(value: &str) -> Result<Vec<u8>> {
    let (algorithm, encoded) = value.split_once(':').context("expected sha256 Nix hash")?;
    ensure!(algorithm == "sha256", "expected sha256 Nix hash");
    nix_base32_decode(encoded)
}

fn nix_base32_decode(value: &str) -> Result<Vec<u8>> {
    ensure!(value.len() == 52, "invalid Nix base32 SHA-256 length");
    let mut output = [0u8; 32];
    for (index, byte) in value.bytes().enumerate() {
        let digit = NIX_BASE32
            .iter()
            .position(|candidate| *candidate == byte)
            .context("invalid Nix base32 digit")?;
        let bit = (value.len() - 1 - index) * 5;
        let byte_index = bit / 8;
        let shift = bit % 8;
        if byte_index < output.len() {
            output[byte_index] |= (digit << shift) as u8;
        }
        if shift > 3 && byte_index + 1 < output.len() {
            output[byte_index + 1] |= (digit >> (8 - shift)) as u8;
        }
    }
    ensure!(
        nix_base32_encode(&output)? == value,
        "non-canonical Nix base32 SHA-256"
    );
    Ok(output.to_vec())
}

fn nix_base32_encode(digest: &[u8]) -> Result<String> {
    ensure!(
        digest.len() == 32,
        "Nix base32 encoding requires a SHA-256 digest"
    );
    let length = (digest.len() * 8 - 1) / 5 + 1;
    let mut output = String::with_capacity(length);
    for index in (0..length).rev() {
        let bit = index * 5;
        let byte_index = bit / 8;
        let shift = bit % 8;
        let mut value = usize::from(digest[byte_index]) >> shift;
        if shift > 3 && byte_index + 1 < digest.len() {
            value |= usize::from(digest[byte_index + 1]) << (8 - shift);
        }
        output.push(NIX_BASE32[value & 0x1f] as char);
    }
    Ok(output)
}

fn extract_verified_nar(path: &Path, info: &NarInfo, destination: &Path) -> Result<()> {
    let (hash, size) = hash_file(path)?;
    ensure!(
        size == info.nar_size,
        "builder NAR size does not match signed metadata"
    );
    ensure!(
        hash == decode_nix_hash(&info.nar_hash)?,
        "builder NAR hash does not match signed metadata"
    );
    let mut input = File::open(path).context("open verified builder NAR")?;
    extract_nar(&mut input, destination)
}

fn extract_nar(input: &mut impl Read, destination: &Path) -> Result<()> {
    let mut nar = NarReader { input };
    nar.expect("nix-archive-1")?;
    extract_node(&mut nar, destination, destination)?;
    let mut trailing = [0u8; 1];
    ensure!(
        nar.input
            .read(&mut trailing)
            .context("check trailing NAR data")?
            == 0,
        "unexpected data after NAR root node"
    );
    Ok(())
}

struct NarReader<'a, R> {
    input: &'a mut R,
}

impl<R: Read> NarReader<'_, R> {
    fn string(&mut self) -> Result<Vec<u8>> {
        let mut encoded = [0u8; 8];
        self.input
            .read_exact(&mut encoded)
            .context("read NAR string length")?;
        let length = u64::from_le_bytes(encoded);
        ensure!(
            length <= MAX_NAR_STRING,
            "NAR string exceeds the 1 GiB safety limit"
        );
        let length =
            usize::try_from(length).context("NAR string length does not fit memory size")?;
        let mut value = vec![0; length];
        self.input
            .read_exact(&mut value)
            .context("read NAR string")?;
        let padding = (8 - length % 8) % 8;
        if padding > 0 {
            let mut bytes = [0u8; 8];
            self.input
                .read_exact(&mut bytes[..padding])
                .context("read NAR padding")?;
            ensure!(
                bytes[..padding].iter().all(|byte| *byte == 0),
                "NAR padding must be zero"
            );
        }
        Ok(value)
    }

    fn expect(&mut self, expected: &str) -> Result<()> {
        let actual = self.string()?;
        ensure!(
            actual == expected.as_bytes(),
            "invalid NAR token; expected {expected:?}"
        );
        Ok(())
    }
}

fn extract_node<R: Read>(nar: &mut NarReader<'_, R>, root: &Path, path: &Path) -> Result<()> {
    nar.expect("(")?;
    nar.expect("type")?;
    let kind = String::from_utf8(nar.string()?).context("NAR node type is not UTF-8")?;
    match kind.as_str() {
        "directory" => {
            fs::create_dir(path).with_context(|| format!("create directory {}", path.display()))?;
            fs::set_permissions(path, fs::Permissions::from_mode(0o755))?;
            loop {
                let token = nar.string()?;
                if token == b")" {
                    break;
                }
                ensure!(token == b"entry", "invalid NAR directory entry");
                nar.expect("(")?;
                nar.expect("name")?;
                let name_bytes = nar.string()?;
                let name = valid_entry_name(&name_bytes)?;
                nar.expect("node")?;
                extract_node(nar, root, &path.join(name))?;
                nar.expect(")")?;
            }
            Ok(())
        }
        "regular" => {
            let field = nar.string()?;
            let executable = if field == b"executable" {
                nar.expect("")?;
                nar.expect("contents")?;
                true
            } else {
                ensure!(field == b"contents", "invalid NAR regular file");
                false
            };
            write_nar_file(nar, path, executable)?;
            nar.expect(")")
        }
        "symlink" => {
            nar.expect("target")?;
            let target =
                String::from_utf8(nar.string()?).context("NAR symlink target is not UTF-8")?;
            safe_symlink(root, path, &target)?;
            std::os::unix::fs::symlink(&target, path)
                .with_context(|| format!("create symlink {}", path.display()))?;
            nar.expect(")")
        }
        _ => bail!("unsupported NAR node type {kind:?}"),
    }
}

fn valid_entry_name(value: &[u8]) -> Result<&OsStr> {
    ensure!(
        !value.is_empty()
            && value != b"."
            && value != b".."
            && !value.iter().any(|byte| matches!(*byte, b'/' | b'\\' | 0)),
        "unsafe NAR entry name {:?}",
        String::from_utf8_lossy(value)
    );
    let text = std::str::from_utf8(value).context("NAR entry name is not UTF-8")?;
    Ok(OsStr::new(text))
}

fn safe_symlink(root: &Path, path: &Path, target: &str) -> Result<()> {
    let target_path = Path::new(target);
    ensure!(
        !target.is_empty() && !target_path.is_absolute(),
        "NAR has an absolute or empty symlink target"
    );
    let relative_parent = path
        .parent()
        .and_then(|parent| parent.strip_prefix(root).ok())
        .context("NAR symlink is outside output root")?;
    let mut components = relative_parent
        .components()
        .filter_map(|component| match component {
            Component::Normal(part) => Some(part.to_os_string()),
            _ => None,
        })
        .collect::<Vec<_>>();
    for component in target_path.components() {
        match component {
            Component::CurDir => {}
            Component::Normal(part) => components.push(part.to_os_string()),
            Component::ParentDir => {
                ensure!(
                    components.pop().is_some(),
                    "NAR symlink escapes output tree"
                );
            }
            Component::RootDir | Component::Prefix(_) => {
                bail!("NAR has an absolute symlink target")
            }
        }
    }
    Ok(())
}

fn write_nar_file<R: Read>(
    nar: &mut NarReader<'_, R>,
    path: &Path,
    executable: bool,
) -> Result<()> {
    let mut encoded = [0u8; 8];
    nar.input
        .read_exact(&mut encoded)
        .context("read NAR file length")?;
    let length = u64::from_le_bytes(encoded);
    ensure!(
        length <= MAX_NAR_SIZE,
        "NAR file exceeds supported size limit"
    );
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(if executable { 0o755 } else { 0o644 })
        .open(path)
        .with_context(|| format!("create file {}", path.display()))?;
    let copied = io::copy(&mut nar.input.by_ref().take(length), &mut output)
        .context("copy NAR file contents")?;
    ensure!(copied == length, "NAR file contents are truncated");
    let padding = ((8 - length % 8) % 8) as usize;
    if padding > 0 {
        let mut bytes = [0u8; 8];
        nar.input
            .read_exact(&mut bytes[..padding])
            .context("read NAR file padding")?;
        ensure!(
            bytes[..padding].iter().all(|byte| *byte == 0),
            "NAR padding must be zero"
        );
    }
    output.sync_all().context("sync extracted file")?;
    output
        .set_permissions(fs::Permissions::from_mode(if executable {
            0o755
        } else {
            0o644
        }))
        .context("set extracted file mode")
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEMP_ID: AtomicU64 = AtomicU64::new(0);

    fn temp_dir(label: &str) -> PathBuf {
        let id = TEMP_ID.fetch_add(1, Ordering::Relaxed);
        let path = env::temp_dir().join(format!("nixpp-test-{label}-{}-{id}", std::process::id()));
        fs::create_dir(&path).unwrap();
        path
    }

    #[test]
    fn reports_current_generation_and_apt_requirements() {
        let root = temp_dir("generations");
        let generations = root.join("generations");
        let current_id = "a".repeat(64);
        let older_id = "b".repeat(64);
        for id in [&current_id, &older_id] {
            let directory = generations.join(id);
            fs::create_dir_all(&directory).unwrap();
            fs::write(
                directory.join("manifest.json"),
                serde_json::json!({
                    "schema": 1,
                    "architecture": "aarch64",
                    "minimumApi": 35,
                    "basePackages": ["zsh", "bash"],
                    "homePackages": ["zoxide", "nixpp"]
                })
                .to_string(),
            )
            .unwrap();
        }
        std::os::unix::fs::symlink(format!("generations/{current_id}"), root.join("current"))
            .unwrap();
        fs::write(
            root.join("generation-index.tsv"),
            format!("2\t{older_id}\n7\t{current_id}\n"),
        )
        .unwrap();

        let status = inspect_generations(&root).unwrap();
        assert_eq!(
            status.current.as_ref().map(|info| info.id.as_str()),
            Some(current_id.as_str())
        );
        assert_eq!(status.current.as_ref().unwrap().number, Some(7));
        assert_eq!(resolve_generation(&root, "7").unwrap(), current_id);
        assert_eq!(status.generations.len(), 2);
        assert!(status.generations[0].current);
        assert_eq!(
            status.current.as_ref().unwrap().apt_packages,
            ["zsh", "bash"]
        );
        assert_eq!(
            status.current.as_ref().unwrap().nix_packages,
            ["zoxide", "nixpp"]
        );
        assert_eq!(
            sorted_package_list(&status.current.as_ref().unwrap().apt_packages),
            "bash, zsh"
        );
        assert_eq!(
            sorted_package_list(&status.current.as_ref().unwrap().nix_packages),
            "nixpp, zoxide"
        );
        assert!(!status.generations[1].current);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_invalid_generation_index() {
        let root = temp_dir("invalid-generation-index");
        fs::write(root.join("generation-index.tsv"), "1\tnot-a-generation\n").unwrap();
        assert!(generation_numbers(&root).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn malformed_historical_generation_does_not_hide_current_generation() {
        let root = temp_dir("malformed-history");
        let generations = root.join("generations");
        let current_id = "a".repeat(64);
        let broken_id = "b".repeat(64);
        let current_dir = generations.join(&current_id);
        let broken_dir = generations.join(&broken_id);
        fs::create_dir_all(&current_dir).unwrap();
        fs::create_dir_all(&broken_dir).unwrap();
        fs::write(
            current_dir.join("manifest.json"),
            serde_json::json!({
                "schema": 1,
                "architecture": "aarch64",
                "minimumApi": 35,
                "basePackages": ["bash"],
                "homePackages": ["nixpp"]
            })
            .to_string(),
        )
        .unwrap();
        fs::write(broken_dir.join("manifest.json"), "").unwrap();
        std::os::unix::fs::symlink(format!("generations/{current_id}"), root.join("current"))
            .unwrap();

        let status = inspect_generations(&root).unwrap();
        assert_eq!(
            status.current.as_ref().map(|info| info.id.as_str()),
            Some(current_id.as_str())
        );
        assert_eq!(status.generations.len(), 1);
        assert_eq!(status.invalid_generations.len(), 1);
        assert_eq!(status.invalid_generations[0].id, broken_id);
        assert!(
            status.invalid_generations[0]
                .error
                .contains("parse generation")
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_unsafe_or_missing_current_generation_targets() {
        let root = temp_dir("bad-current");
        fs::create_dir_all(root.join("generations")).unwrap();
        std::os::unix::fs::symlink("../../outside", root.join("current")).unwrap();
        assert!(inspect_generations(&root).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    fn nar_string(output: &mut Vec<u8>, value: &[u8]) {
        output.extend_from_slice(&(value.len() as u64).to_le_bytes());
        output.extend_from_slice(value);
        output.resize(output.len() + (8 - value.len() % 8) % 8, 0);
    }

    fn nar_header(output: &mut Vec<u8>) {
        nar_string(output, b"nix-archive-1");
    }

    fn nar_executable_file(output: &mut Vec<u8>, name: &[u8], contents: &[u8]) {
        nar_string(output, b"entry");
        nar_string(output, b"(");
        nar_string(output, b"name");
        nar_string(output, name);
        nar_string(output, b"node");
        nar_string(output, b"(");
        nar_string(output, b"type");
        nar_string(output, b"regular");
        nar_string(output, b"executable");
        nar_string(output, b"");
        nar_string(output, b"contents");
        nar_string(output, contents);
        nar_string(output, b")");
        nar_string(output, b")");
    }

    fn nar_directory_with_executable(name: &[u8], contents: &[u8]) -> Vec<u8> {
        let mut output = Vec::new();
        nar_header(&mut output);
        nar_string(&mut output, b"(");
        nar_string(&mut output, b"type");
        nar_string(&mut output, b"directory");
        nar_executable_file(&mut output, name, contents);
        nar_string(&mut output, b")");
        output
    }

    #[test]
    fn nix_base32_matches_nix_and_round_trips() {
        let digest = Sha256::digest(b"abc");
        let expected = "1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s";
        let encoded = nix_base32_encode(&digest).unwrap();
        assert_eq!(encoded, expected);
        assert_eq!(nix_base32_decode(expected).unwrap(), digest.as_slice());
        assert!(nix_base32_decode("z".repeat(52).as_str()).is_err());
    }

    #[test]
    fn verifies_nix_narinfo_signature() {
        let signing_key = SigningKey::from_bytes(&[7u8; 32]);
        let public_key = format!(
            "test:{}",
            BASE64.encode(signing_key.verifying_key().as_bytes())
        );
        let mut info = NarInfo {
            store_path: "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-package".into(),
            url: "nar/test.nar.gz".into(),
            compression: "gzip".into(),
            nar_hash: "sha256:1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s".into(),
            nar_size: 42,
            file_hash: None,
            file_size: None,
            references: Vec::new(),
            signatures: Vec::new(),
        };
        let fingerprint = format!("1;{};{};{};", info.store_path, info.nar_hash, info.nar_size);
        info.signatures.push(format!(
            "test:{}",
            BASE64.encode(signing_key.sign(fingerprint.as_bytes()).to_bytes())
        ));
        verify_signature(&info, &public_key).unwrap();
        info.nar_size += 1;
        assert!(verify_signature(&info, &public_key).is_err());
    }

    #[test]
    fn parses_reference_free_narinfo_and_requires_references() {
        let data = b"StorePath: /nix/store/0123456789abcdfghijklmnpqrsvwxyz-package\n\
            URL: nar/test.nar.gz\n\
            Compression: gzip\n\
            NarHash: sha256:1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s\n\
            NarSize: 3\n\
            References: \n\
            Sig: test:signature\n";
        let info = parse_nar_info(data).unwrap();
        assert!(info.references.is_empty());
        assert_eq!(info.compression, "gzip");
        let without_references = String::from_utf8(data.to_vec())
            .unwrap()
            .replace("References: \n", "");
        assert!(parse_nar_info(without_references.as_bytes()).is_err());
    }

    #[test]
    fn parses_zstandard_narinfo_and_decompresses_zstandard_nars() {
        use ruzstd::encoding::{CompressionLevel, compress_to_vec};

        let narinfo = b"StorePath: /nix/store/0123456789abcdfghijklmnpqrsvwxyz-package\n\
            URL: nar/test.nar.zst\n\
            Compression: zstd\n\
            NarHash: sha256:1b8m03r63zqhnjf7l5wnldhh7c134ap5vpj0850ymkq1iyzicy5s\n\
            NarSize: 3\n\
            References: \n\
            Sig: test:signature\n";
        let compressed_info = compress_to_vec(narinfo.as_slice(), CompressionLevel::Fastest);
        let info = parse_nar_info_response(&compressed_info).unwrap();
        assert_eq!(info.compression, "zstd");

        let directory = temp_dir("zstd-nar");
        let source = directory.join("source.zst");
        let destination = directory.join("nar");
        fs::write(
            &source,
            compress_to_vec(b"nar".as_slice(), CompressionLevel::Fastest),
        )
        .unwrap();
        decompress_to_file("zstd", &source, &destination, 3).unwrap();
        assert_eq!(fs::read(&destination).unwrap(), b"nar");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn cache_urls_reject_unsafe_paths() {
        let base = parse_http_cache_url("https://cache.example/private/termux/cache").unwrap();
        for candidate in [
            "../outside",
            "/outside",
            "https://evil.example/nar",
            "nar/x?redirect=1",
            "nar/%2e%2e/out",
        ] {
            assert!(
                safe_cache_url(&base, candidate).is_err(),
                "accepted {candidate:?}"
            );
        }
        assert_eq!(
            safe_cache_url(&base, "nar/abc.nar.xz").unwrap(),
            "https://cache.example/private/termux/cache/nar/abc.nar.xz"
        );
    }

    #[test]
    fn parses_nix_s3_substituter_as_path_style_https_url() {
        let target = parse_cache_target(
            "s3://nix-cache-brkn-lol?endpoint=s3.openstack.de-west-01.wiit-cloud.io&region=default&scheme=https&profile=niks3&priority=30",
            Some(Path::new("~/.aws/credentials")),
            None,
        )
        .unwrap();
        assert_eq!(
            target.base.as_str(),
            "https://s3.openstack.de-west-01.wiit-cloud.io/nix-cache-brkn-lol"
        );
        let object = safe_cache_url(&target.base, "nar/abc.nar.xz").unwrap();
        assert_eq!(
            object,
            "https://s3.openstack.de-west-01.wiit-cloud.io/nix-cache-brkn-lol/nar/abc.nar.xz"
        );
        assert_eq!(target.s3.unwrap().region, "default");
    }

    #[test]
    fn rejects_ambiguous_or_unknown_s3_substituter_options() {
        for url in [
            "s3://cache.example?endpoint=s3.example&profile=one&profile=two",
            "s3://cache.example?endpoint=s3.example&token=secret",
        ] {
            assert!(
                parse_cache_target(url, None, None).is_err(),
                "accepted {url}"
            );
        }
    }

    #[test]
    fn loads_private_aws_profile_for_s3_signing() {
        let directory = temp_dir("aws-credentials");
        let path = directory.join("credentials");
        fs::write(
            &path,
            "[default]\naws_access_key_id = ignored\naws_secret_access_key = ignored\n\
             [niks3]\naws_access_key_id = test-access\naws_secret_access_key = test-secret\n\
             aws_session_token = test-session\n",
        )
        .unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        assert_eq!(
            load_aws_profile(&path, "niks3").unwrap(),
            (
                "test-access".to_owned(),
                "test-secret".to_owned(),
                Some("test-session".to_owned())
            )
        );
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(load_aws_profile(&path, "niks3").is_err());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn reads_default_fetch_and_switch_settings_from_config() {
        let config: NixppConfig = toml::from_str(
            r#"
                [defaults]
                substituter = "s3://cache.example?endpoint=s3.example&profile=cache"
                flake = "path:/tmp/nixos-config#termux-native-zf10-bundle"
                builders = ["builder", "backup-builder"]
                public_keys = ["cache:abc", "builder:def"]
                aws_credentials_command = ["rbw", "get", "--raw", "--exact", "nixpp Niks3 cache"]
            "#,
        )
        .unwrap();
        assert_eq!(
            config.defaults.substituter.as_deref(),
            Some("s3://cache.example?endpoint=s3.example&profile=cache")
        );
        assert_eq!(config.defaults.public_keys, ["cache:abc", "builder:def"]);
        assert_eq!(config.defaults.builders, ["builder", "backup-builder"]);
        assert_eq!(
            config.defaults.configured_builders(),
            ["builder", "backup-builder"]
        );
        let credentials_command: Vec<_> = config
            .defaults
            .aws_credentials_command
            .unwrap()
            .iter()
            .map(String::as_str)
            .collect();
        assert_eq!(
            credentials_command,
            ["rbw", "get", "--raw", "--exact", "nixpp Niks3 cache"]
        );
    }

    #[test]
    fn netrc_must_be_private_regular_file() {
        let directory = temp_dir("netrc");
        let path = directory.join("netrc");
        fs::write(&path, "machine cache.example login user password secret\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        validate_netrc(&path).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(validate_netrc(&path).is_err());
        fs::remove_file(&path).unwrap();
        std::os::unix::fs::symlink(directory.join("external"), &path).unwrap();
        assert!(validate_netrc(&path).is_err());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn validates_store_paths_ssh_targets_and_shell_quoting() {
        for path in [
            "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-termux-bundle",
            "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-name+with.dots",
        ] {
            assert!(valid_store_path(path), "rejected {path:?}");
        }
        for path in [
            "/nix/store/../etc/passwd",
            "/nix/store/0123456789abcdfghijklmnpqrsvwxy-termux-bundle",
            "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-name/child",
        ] {
            assert!(!valid_store_path(path), "accepted {path:?}");
        }
        for target in ["rofl-13", "pschmitt@rofl-13", "builder.example"] {
            assert!(valid_ssh_target(target), "rejected {target:?}");
        }
        for target in ["-oProxyCommand=id", "host;id", "host\ncommand"] {
            assert!(!valid_ssh_target(target), "accepted {target:?}");
        }
        assert_eq!(
            shell_quote("path with ' quote"),
            "'path with '\"'\"' quote'"
        );
        assert!(valid_remote_temp("/tmp/nixpp-switch.aB0dEF19"));
        assert!(!valid_remote_temp("/tmp/nixpp-switch.aB0dEF19;rm"));
    }

    #[test]
    fn parses_digest_and_verifies_file_hash() {
        let directory = temp_dir("digest");
        let archive = directory.join("environment.tar.gz");
        let contents = b"termux bundle fixture";
        fs::write(&archive, contents).unwrap();
        let digest = hex(&Sha256::digest(contents));
        let manifest = directory.join("SHA256SUMS");
        fs::write(&manifest, format!("{digest}  environment.tar.gz\n")).unwrap();
        assert_eq!(read_archive_digest(&manifest).unwrap(), digest);
        verify_file_sha256(&archive, &digest).unwrap();
        assert!(verify_file_sha256(&archive, &"0".repeat(64)).is_err());
        fs::write(&manifest, format!("{digest}  ../environment.tar.gz\n")).unwrap();
        assert!(read_archive_digest(&manifest).is_err());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn extracts_nar_file_with_executable_mode() {
        let directory = temp_dir("nar-file");
        let destination = directory.join("output");
        let bytes = nar_directory_with_executable(b"tool", b"hello");
        extract_nar(&mut bytes.as_slice(), &destination).unwrap();
        assert_eq!(fs::read(destination.join("tool")).unwrap(), b"hello");
        assert_eq!(
            fs::metadata(destination.join("tool"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o755
        );
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn rejects_nar_traversal_and_absolute_symlinks() {
        let directory = temp_dir("nar-traversal");
        let destination = directory.join("output");
        let mut bytes = Vec::new();
        nar_header(&mut bytes);
        nar_string(&mut bytes, b"(");
        nar_string(&mut bytes, b"type");
        nar_string(&mut bytes, b"directory");
        nar_string(&mut bytes, b"entry");
        nar_string(&mut bytes, b"(");
        nar_string(&mut bytes, b"name");
        nar_string(&mut bytes, b"../escape");
        assert!(extract_nar(&mut bytes.as_slice(), &destination).is_err());
        let _ = fs::remove_dir_all(&destination);

        let mut symlink = Vec::new();
        nar_header(&mut symlink);
        nar_string(&mut symlink, b"(");
        nar_string(&mut symlink, b"type");
        nar_string(&mut symlink, b"directory");
        nar_string(&mut symlink, b"entry");
        nar_string(&mut symlink, b"(");
        nar_string(&mut symlink, b"name");
        nar_string(&mut symlink, b"link");
        nar_string(&mut symlink, b"node");
        nar_string(&mut symlink, b"(");
        nar_string(&mut symlink, b"type");
        nar_string(&mut symlink, b"symlink");
        nar_string(&mut symlink, b"target");
        nar_string(&mut symlink, b"/etc/passwd");
        nar_string(&mut symlink, b")");
        nar_string(&mut symlink, b")");
        nar_string(&mut symlink, b")");
        assert!(extract_nar(&mut symlink.as_slice(), &destination).is_err());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn staging_uses_termux_prefix_when_tmpdir_is_missing() {
        let prefix = temp_dir("prefix");
        let termux_tmp = prefix.join("tmp");
        fs::create_dir(&termux_tmp).unwrap();
        let stage = make_staging_directory_in(
            vec![prefix.join("missing"), termux_tmp.clone()],
            "nixpp-test",
        )
        .unwrap();
        assert_eq!(stage.parent(), Some(termux_tmp.as_path()));
        fs::remove_dir(stage).unwrap();
        fs::remove_dir_all(prefix).unwrap();
    }
}

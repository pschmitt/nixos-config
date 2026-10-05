use anyhow::{Context, Result, bail, ensure};
use base64::{Engine, engine::general_purpose::STANDARD as BASE64};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};
use std::env;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, IsTerminal, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use url::Url;

const NIX_BASE32: &[u8; 32] = b"0123456789abcdfghijklmnpqrsvwxyz";
const MAX_NAR_SIZE: u64 = 20 << 30;
const MAX_NAR_STRING: u64 = 1 << 30;

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

    fn paint(&self, code: &str, value: &str) -> String {
        if self.color {
            format!("\x1b[{code}m{value}\x1b[0m")
        } else {
            value.to_owned()
        }
    }

    fn title(&self) {
        eprintln!("\nnixpp ✨ {}", self.paint("2", "Termux environment"));
    }

    fn stage(&self, label: &str, action: impl FnOnce() -> Result<()>) -> Result<()> {
        eprintln!("  {} {label}", self.paint("36", "✦"));
        let started = Instant::now();
        match action() {
            Ok(()) => {
                eprintln!(
                    "  {} {} ({})",
                    self.paint("1;32", "✓"),
                    self.paint("32", "Done"),
                    elapsed(started.elapsed())
                );
                Ok(())
            }
            Err(error) => {
                eprintln!(
                    "  {} {} ({})",
                    self.paint("1;31", "✗"),
                    self.paint("31", "Failed"),
                    elapsed(started.elapsed())
                );
                Err(error)
            }
        }
    }

    fn warning(&self, message: &str) {
        eprintln!("  {} {message}", self.paint("1;33", "!"));
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
    path: String,
    architecture: String,
    minimum_api: u64,
    apt_packages: Vec<String>,
    nix_packages: Vec<String>,
}

#[derive(Debug, serde::Serialize)]
struct GenerationEntry {
    id: String,
    current: bool,
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

fn inspect_generation(root: &Path, id: &str) -> Result<GenerationInfo> {
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
        path: path.display().to_string(),
        architecture,
        minimum_api,
        apt_packages: manifest_string_array(&manifest, "basePackages")?,
        nix_packages: manifest_string_array(&manifest, "homePackages")?,
    })
}

fn inspect_generations(root: &Path) -> Result<GenerationStatus> {
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
        match inspect_generation(root, &id) {
            Ok(info) if Some(&id) == current.as_ref() => current_info = Some(info),
            Ok(_) => generations.push(GenerationEntry { id, current: false }),
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
                current: true,
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
    println!("{}", ui.paint("1;36", "nixpp ✨ Termux generations"));
    if let Some(current) = &status.current {
        println!("Current: {}", ui.paint("1;32", &current.id));
        println!(
            "    {} · Android API {}+",
            current.architecture, current.minimum_api
        );
        println!("    Termux APT: {}", current.apt_packages.join(", "));
        println!("    Nix outputs: {}", current.nix_packages.join(", "));
        println!("    Path: {}", current.path);
    } else {
        println!("Current: {}", ui.paint("1;33", "none"));
        println!("Run `nixpp switch --flake …` to install a generation.");
    }
    println!(
        "Readable generation manifests: {}",
        status.generations.len()
    );
    if !status.invalid_generations.is_empty() {
        println!(
            "Unusable historical generations: {} (details: `nixpp status --json`)",
            status.invalid_generations.len()
        );
    }
    Ok(())
}

fn print_generations(status: &GenerationStatus) {
    let ui = Progress::new();
    println!("{}", ui.paint("1;36", "nixpp ✨ generation IDs"));
    if status.generations.is_empty() {
        println!("No generations are installed.");
        return;
    }
    println!(
        "Rollback with: bash \"$HOME/.local/share/termux-native/current/activate.sh\" rollback ID"
    );
    for generation in &status.generations {
        let marker = if generation.current { "◆" } else { "◇" };
        let id = if generation.current {
            ui.paint("1;32", &generation.id)
        } else {
            ui.paint("2", &generation.id)
        };
        println!("  {marker} {id}");
    }
    if !status.invalid_generations.is_empty() {
        println!(
            "Skipped {} unusable historical generation(s).",
            status.invalid_generations.len()
        );
    }
}

pub fn status(json: bool) -> Result<()> {
    let status = inspect_generations(&termux_generation_root()?)?;
    print_generation_status(&status, json)
}

pub fn generations() -> Result<()> {
    let status = inspect_generations(&termux_generation_root()?)?;
    print_generations(&status);
    Ok(())
}

pub fn fetch(
    cache: &str,
    store_path: &str,
    destination: &Path,
    public_key: &str,
    netrc_file: Option<&Path>,
) -> Result<()> {
    let store_hash = store_hash(store_path)?;
    let base = parse_cache_url(cache)?;
    let has_credentials = env::var_os("NIXPP_USERNAME").is_some()
        || env::var_os("NIXPP_PASSWORD").is_some()
        || netrc_file.is_some();
    ensure!(
        base.scheme() == "https" || !has_credentials,
        "refusing to send cache credentials over plain HTTP"
    );

    let (netrc, remove_netrc) = match netrc_file {
        Some(path) => {
            validate_netrc(path)?;
            (Some(path.to_path_buf()), None)
        }
        None => make_netrc(base.host_str().context("cache URL has no host")?)?,
    };
    let result = (|| {
        let mut info_url = base.clone();
        info_url
            .path_segments_mut()
            .map_err(|_| anyhow::anyhow!("cache URL cannot accept a path"))?
            .pop_if_empty()
            .push(&format!("{store_hash}.narinfo"));
        let narinfo =
            curl_read(info_url.as_str(), netrc.as_deref(), 1 << 20).context("fetch narinfo")?;
        let info = parse_nar_info(&narinfo)?;
        ensure!(
            info.store_path == store_path,
            "narinfo StorePath does not match requested store path"
        );
        ensure!(
            info.references.is_empty(),
            "refusing cache output with Nix store references"
        );
        verify_signature(&info, public_key)?;
        ensure!(
            matches!(info.compression.as_str(), "none" | "gzip" | "xz"),
            "unsupported cache compression {:?}; supported formats are none, gzip, and xz",
            info.compression
        );
        let archive_url = safe_cache_url(&base, &info.url)?;
        download_and_extract(&archive_url, netrc.as_deref(), &info, destination)
    })();
    let cleanup_result = remove_netrc.map_or(Ok(()), |path| {
        fs::remove_file(&path).with_context(|| format!("remove temporary netrc {}", path.display()))
    });
    result.and(cleanup_result)
}

pub fn status(all: bool) -> Result<()> {
    let home = env::var_os("HOME").context("HOME is not set")?;
    let root = env::var_os("TERMUX_NATIVE_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(home).join(".local/share/termux-native"));
    let generations_path = root.join("generations");
    let current_path = root.join("current");
    let active = fs::canonicalize(&current_path)
        .ok()
        .and_then(|path| path.file_name().map(OsStr::to_os_string))
        .and_then(|name| name.into_string().ok());
    let stdout = io::stdout();
    let color = stdout.is_terminal()
        && env::var_os("NO_COLOR").is_none()
        && env::var("TERM").as_deref() != Ok("dumb");
    let paint = |code: &str, value: &str| {
        if color {
            format!("\x1b[{code}m{value}\x1b[0m")
        } else {
            value.to_owned()
        }
    };

    println!("\nnixpp ✨ Termux generations");
    match &active {
        Some(generation) => println!("  active: {}", paint("1;32", generation)),
        None if current_path.symlink_metadata().is_ok() => {
            println!("  active: {}", paint("1;31", "broken current link"))
        }
        None => println!("  active: {}", paint("2", "none")),
    }

    let mut generations = Vec::new();
    if let Ok(entries) = fs::read_dir(&generations_path) {
        for entry in entries {
            let entry = entry.context("read generation directory entry")?;
            let file_type = entry.file_type().context("inspect generation entry")?;
            let name = entry.file_name();
            let Some(name) = name.to_str() else {
                continue;
            };
            if !file_type.is_dir()
                || name.len() != 64
                || !name.bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                continue;
            }
            let modified = entry
                .metadata()
                .and_then(|metadata| metadata.modified())
                .unwrap_or(std::time::UNIX_EPOCH);
            generations.push((name.to_owned(), modified));
        }
    }
    generations.sort_by(|left, right| right.1.cmp(&left.1));

    if generations.is_empty() {
        println!("  {}", paint("2", "No installed generations found."));
        return Ok(());
    }
    let rollback_generations: Vec<_> = generations
        .iter()
        .filter(|(generation, _)| active.as_deref() != Some(generation.as_str()))
        .collect();
    println!(
        "  rollback generations retained: {}",
        rollback_generations.len()
    );
    let shown = if all {
        rollback_generations.len()
    } else {
        rollback_generations.len().min(5)
    };
    for (generation, _) in rollback_generations.iter().take(shown) {
        println!("    {generation}");
    }
    if shown < rollback_generations.len() {
        println!(
            "    {} more; pass --all to list every generation",
            rollback_generations.len() - shown
        );
    }

    if let Some(generation) = active {
        let package_file = generations_path.join(generation).join("base-packages.txt");
        if let Ok(packages) = fs::read_to_string(package_file) {
            let packages: Vec<_> = packages.lines().filter(|line| !line.is_empty()).collect();
            println!("  Termux APT packages: {}", packages.len());
            if !packages.is_empty() {
                println!("    {}", packages.join(" "));
            }
        }
    }
    println!(
        "  {}",
        paint(
            "2",
            "APT packages are shared across generations and are not rolled back."
        )
    );
    Ok(())
}

pub fn switch_profile(flake: &str, builder: &str, public_key: &str) -> Result<()> {
    ensure!(!flake.is_empty(), "--flake is required");
    ensure!(
        flake.len() <= 4096 && !flake.contains(['\0', '\r', '\n']),
        "flake installable is invalid or too long"
    );
    ensure!(
        valid_ssh_target(builder),
        "builder must be an SSH host or user@host alias without command-line options"
    );
    ensure!(
        !public_key.is_empty(),
        "a trusted signing key is required; pass --public-key or set NIXPP_PUBLIC_KEY"
    );
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
    let mut store_path = String::new();
    ui.stage(&format!("🧱 Build flake on {builder}"), || {
        store_path = remote_build(builder, flake)?;
        Ok(())
    })?;

    let mut remote_temp = None;
    let result = (|| {
        let mut info = None;
        ui.stage("🔏 Sign and inspect the Nix output", || {
            let path = remote_output_cache(builder, &store_path)?;
            remote_temp = Some(path.clone());
            let store_hash = store_hash(&store_path)?;
            let metadata_path = format!("{path}/cache/{store_hash}.narinfo");
            let data = remote_output(builder, &format!("cat -- {}", shell_quote(&metadata_path)))?;
            let parsed = parse_nar_info(data.as_bytes())?;
            ensure!(
                parsed.store_path == store_path,
                "builder metadata StorePath does not match the requested flake output"
            );
            ensure!(
                parsed.references.is_empty(),
                "refusing Termux bundle with Nix store references"
            );
            verify_signature(&parsed, public_key).context("verify builder signature")?;
            info = Some(parsed);
            Ok(())
        })?;
        let info = info.context("builder returned no Nix metadata")?;

        let stage = make_staging_directory("nixpp-switch-")?;
        let result = (|| {
            let mut archive_path = PathBuf::new();
            let mut digest = String::new();
            let mut bootstrap_path = PathBuf::new();
            ui.stage("📦 Transfer and verify the bundle", || {
                let nar_path = stage.join("output.nar");
                remote_nar(builder, &store_path, &nar_path, info.nar_size)?;
                let bundle_dir = stage.join("bundle");
                extract_verified_nar(&nar_path, &info, &bundle_dir)?;
                archive_path = bundle_dir.join("environment.tar.gz");
                digest = read_archive_digest(&bundle_dir.join("SHA256SUMS"))?;
                verify_file_sha256(&archive_path, &digest).context("verify Termux archive")?;
                bootstrap_path = bundle_dir.join("bootstrap.sh");
                ensure!(
                    fs::metadata(&bootstrap_path)
                        .is_ok_and(|metadata| metadata.file_type().is_file()),
                    "Termux bundle is missing a regular bootstrap.sh"
                );
                Ok(())
            })?;
            ui.stage("🚀 Install and health-check the new generation", || {
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
        result.and(cleanup)
    })();

    if let Some(path) = remote_temp
        && let Err(error) = remote_run(builder, &format!("rm -rf -- {}", shell_quote(&path)))
    {
        ui.warning(&format!(
            "could not remove temporary builder output {path}: {error:#}"
        ));
    }
    result
}

fn remote_build(builder: &str, flake: &str) -> Result<String> {
    let command = format!(
        "nix build --accept-flake-config --no-link --print-out-paths -- {}",
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

fn parse_cache_url(value: &str) -> Result<Url> {
    let url = Url::parse(value).context("cache must be an HTTP(S) URL")?;
    ensure!(
        matches!(url.scheme(), "http" | "https"),
        "cache must be an HTTP(S) URL"
    );
    ensure!(url.host_str().is_some(), "cache URL has no host");
    ensure!(
        url.username().is_empty() && url.password().is_none(),
        "cache URL must not contain credentials"
    );
    ensure!(
        url.query().is_none() && url.fragment().is_none(),
        "cache URL must not contain a query or fragment"
    );
    Ok(url)
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

fn curl_args(netrc: Option<&Path>, progress: bool) -> Vec<String> {
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
    if let Some(path) = netrc {
        arguments.extend(["--netrc-file".to_owned(), path.display().to_string()]);
    }
    arguments
}

fn curl_read(url: &str, netrc: Option<&Path>, max_size: u64) -> Result<Vec<u8>> {
    let mut command = Command::new("curl");
    command
        .args(curl_args(netrc, false))
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
    let output = command.output().context("start curl")?;
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

fn download_and_extract(
    url: &str,
    netrc: Option<&Path>,
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
        curl_download(url, netrc, &compressed_path, compressed_limit)?;
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

fn curl_download(url: &str, netrc: Option<&Path>, destination: &Path, maximum: u64) -> Result<()> {
    let mut command = Command::new("curl");
    command
        .args(curl_args(netrc, true))
        .args(["--max-filesize", &maximum.to_string(), "--output"])
        .arg(destination)
        .arg(url)
        .env_remove("NIXPP_USERNAME")
        .env_remove("NIXPP_PASSWORD");
    if io::stderr().is_terminal() {
        let status = command.status().context("start curl")?;
        ensure!(status.success(), "curl failed fetching NAR: {status}");
    } else {
        let output = command.output().context("start curl")?;
        ensure!(
            output.status.success(),
            "curl failed fetching NAR: {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
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
                    "basePackages": ["bash", "zsh"],
                    "homePackages": ["nixpp"]
                })
                .to_string(),
            )
            .unwrap();
        }
        std::os::unix::fs::symlink(format!("generations/{current_id}"), root.join("current"))
            .unwrap();

        let status = inspect_generations(&root).unwrap();
        assert_eq!(
            status.current.as_ref().map(|info| info.id.as_str()),
            Some(current_id.as_str())
        );
        assert_eq!(status.generations.len(), 2);
        assert!(status.generations[0].current);
        assert_eq!(
            status.current.as_ref().unwrap().apt_packages,
            ["bash", "zsh"]
        );
        assert_eq!(status.current.as_ref().unwrap().nix_packages, ["nixpp"]);
        assert!(!status.generations[1].current);

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
    fn cache_urls_reject_unsafe_paths() {
        let base = parse_cache_url("https://cache.example/private/termux/cache").unwrap();
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

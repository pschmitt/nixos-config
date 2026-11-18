//! Native preparation of the isolated full-Nix runtime.
//!
//! Nothing here touches the normal Termux prefix. A runtime lives in one
//! caller-provided directory:
//!
//! ```text
//! DIRECTORY/
//!   launcher            provided externally (pinned, hash-verified by the caller)
//!   nixpp               copy of the running executable, used by the launch scripts
//!   session.sh ...      launch scripts embedded in this module (see `SCRIPTS`)
//!   root/               extracted, hash-verified bootstrap (never overwritten)
//!   session.env         sourced by session.sh
//!   session.json        copy of the pinned session manifest
//!   packages.txt        pinned store paths still to be imported
//!   proc-stat, proc-uptime
//!   ready               written by `install` after the final checks pass
//! ```
//!
//! [`prepare`] extracts and configures; [`install`] imports the pinned packages
//! through the bootstrap Nix (it is also the resume operation after an
//! interrupted download). Neither function deletes existing data: an existing
//! `root` aborts `prepare`, and a partially extracted `root` is left in place
//! for inspection.

use anyhow::{Context, Result, bail, ensure};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{ErrorKind, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use zip::ZipArchive;

use crate::progress;

/// SHA-256 of the bootstrap seed built alongside this executable, the only
/// accepted seed. The Nix package build sets it; a build without it refuses
/// to prepare a runtime.
pub const BOOTSTRAP_SHA256: Option<&str> = option_env!("NIXPP_BOOTSTRAP_SHA256");
/// File name of the bootstrap seed in the bundled assets directory.
pub const BOOTSTRAP_NAME: &str = "bootstrap-aarch64.zip";
/// Default guest username.
pub const DEFAULT_USERNAME: &str = "nix";
/// Name of the externally provided launcher binary inside the runtime directory.
pub const LAUNCHER_NAME: &str = "launcher";
/// Name under which the running executable is staged inside the runtime directory.
pub const NIXPP_NAME: &str = "nixpp";

/// Runtime launch scripts embedded verbatim, as `(file name, content)`.
///
/// `login.sh` optionally starts the Android bridge and the system controller
/// when the `bridge.enabled` / `system.enabled` marker files exist.
pub const SCRIPTS: [(&str, &str); 5] = [
    ("session.sh", include_str!("assets/session.sh")),
    (
        "system-session.sh",
        include_str!("assets/system-session.sh"),
    ),
    ("login.sh", include_str!("assets/login.sh")),
    (
        "start-system-control.sh",
        include_str!("assets/start-system-control.sh"),
    ),
    (
        "start-android-bridge.sh",
        include_str!("assets/start-android-bridge.sh"),
    ),
];

const GCROOT_DIR: &str = "nix/var/nix/gcroots/termuxpp-session";
const MAX_BOOTSTRAP_ARCHIVE_BYTES: u64 = 1 << 30;
const MAX_EXTRACTED_BYTES: u64 = 512 << 20;
const MAX_ENTRIES: usize = 100_000;
const MAX_LIST_BYTES: u64 = 16 << 20;
const MAX_MANIFEST_BYTES: u64 = 1 << 20;
const MAX_NAME_BYTES: usize = 4096;

#[derive(Clone, Copy, Debug)]
struct Limits {
    /// Largest accepted bootstrap seed ZIP.
    archive_bytes: u64,
    /// Largest accepted total of extracted file bytes.
    extracted_bytes: u64,
    entries: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            archive_bytes: MAX_BOOTSTRAP_ARCHIVE_BYTES,
            extracted_bytes: MAX_EXTRACTED_BYTES,
            entries: MAX_ENTRIES,
        }
    }
}

/// Pinned session manifest produced by `session.nix` on the trusted builder.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    schema: u64,
    system: String,
    page_size: u64,
    packages: Vec<String>,
    shell: String,
    nix: String,
    python: String,
    zsh: String,
    certificate: String,
    terminfo: String,
    path: String,
}

/// Check that this device can run the AArch64/4096-byte-page runtime.
///
/// `uname -m` must be `aarch64` and `getconf PAGE_SIZE` must be `4096`.
pub fn check_platform() -> Result<()> {
    let query = |program: &str, argument: &str| -> Result<String> {
        let output = Command::new(program)
            .arg(argument)
            .output()
            .with_context(|| format!("failed to run {program} {argument}"))?;
        ensure!(output.status.success(), "{program} {argument} failed");
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
    };
    platform_ok(
        &query("/system/bin/uname", "-m")?,
        &query("/system/bin/getconf", "PAGE_SIZE")?,
    )
}

fn platform_ok(arch: &str, page_size: &str) -> Result<()> {
    ensure!(
        arch == "aarch64" && page_size == "4096",
        "only AArch64 with 4096-byte pages is qualified for this runtime"
    );
    Ok(())
}

/// Full first-time setup: `nixpp init --runtime DIR --bootstrap ZIP --manifest FILE
/// --certificate FILE --user USER`.
///
/// Checks the platform and that the externally provided `launcher` is already
/// staged at `DIR/launcher`, then runs [`prepare`], stages the running
/// executable as `DIR/nixpp` and runs [`install`]. If the package import is
/// interrupted, continue with [`resume`].
pub fn init(
    directory: &Path,
    seed: &Path,
    manifest: &Path,
    certificate: &Path,
    username: &str,
) -> Result<()> {
    check_platform()?;
    let launcher = directory.join(LAUNCHER_NAME);
    ensure!(
        launcher.is_file(),
        "the pinned launcher must be staged at {} before init",
        launcher.display()
    );
    prepare(directory, seed, manifest, certificate, username)?;
    stage_executable(directory)?;
    install(directory)
}

/// Continue an interrupted setup: `nixpp init --runtime DIR --resume`.
///
/// Re-checks the platform, requires `session.env` and `packages.txt` to be
/// readable (otherwise "No prepared runtime to resume"), refreshes the embedded
/// scripts and `DIR/nixpp`, and re-runs the whole package import loop (`nix
/// copy` is idempotent, so already imported packages are cheap). Nothing is
/// extracted or overwritten.
pub fn resume(directory: &Path) -> Result<()> {
    check_platform()?;
    for name in ["session.env", "packages.txt"] {
        let path = directory.join(name);
        File::open(&path).with_context(|| {
            format!(
                "No prepared runtime to resume: cannot read {}",
                path.display()
            )
        })?;
    }
    install_scripts(directory)?;
    stage_executable(directory)?;
    install(directory)
}

/// Prepare a new isolated runtime from a verified bootstrap and pinned manifest.
///
/// `directory` is created if needed and must not yet contain a runtime;
/// `certificate` is the native CA bundle exposed to the bootstrap Nix. Package
/// import is a separate step, see [`install`]. Existing runtime data is never
/// overwritten or removed.
pub fn prepare(
    directory: &Path,
    seed: &Path,
    manifest: &Path,
    certificate: &Path,
    username: &str,
) -> Result<()> {
    validate_username(username)?;
    let expected = BOOTSTRAP_SHA256
        .context("this nixpp build has no pinned bootstrap seed; use the Nix-built package")?;
    prepare_with(
        directory,
        seed,
        manifest,
        certificate,
        username,
        expected,
        Limits::default(),
    )
}

fn prepare_with(
    directory: &Path,
    seed: &Path,
    manifest_path: &Path,
    certificate: &Path,
    username: &str,
    expected_sha256: &str,
    limits: Limits,
) -> Result<()> {
    validate_username(username)?;
    let home = format!("/home/{username}");
    let manifest_bytes = read_limited(manifest_path, MAX_MANIFEST_BYTES)
        .with_context(|| format!("failed to read manifest {}", manifest_path.display()))?;
    let manifest: Manifest =
        serde_json::from_slice(&manifest_bytes).context("invalid session manifest")?;
    validate_manifest(&manifest)?;
    let android_ca = fs::canonicalize(certificate)
        .with_context(|| format!("certificate {} is not readable", certificate.display()))?;
    let android_ca = android_ca
        .to_str()
        .context("certificate path is not valid UTF-8")?
        .to_owned();

    let root = directory.join("root");
    let outputs = [
        root.clone(),
        directory.join("session.env"),
        directory.join("packages.txt"),
        directory.join("session.json"),
        directory.join("proc-stat"),
        directory.join("proc-uptime"),
    ];
    for output in &outputs {
        ensure_absent(output)?;
    }
    private_dirs(directory)?;

    progress::extract();
    extract_bootstrap(seed, &root, expected_sha256, limits)?;
    let root_real =
        fs::canonicalize(&root).with_context(|| format!("failed to resolve {}", root.display()))?;
    let store = root.join("nix/store");
    let busybox = format!("/nix/store/{}", find_store_dir(&store, "-busybox-static-")?);
    let nix = format!("/nix/store/{}", find_store_dir(&store, "-nix-static-")?);

    for name in [
        home.trim_start_matches('/'),
        "tmp",
        "dev/shm",
        "usr/bin",
        "etc",
    ] {
        mkdir_inside(&root_real, &root, name)?;
    }
    for (name, target) in [
        ("bin/sh", format!("{busybox}/bin/sh")),
        ("usr/bin/env", format!("{busybox}/bin/env")),
    ] {
        let destination = root.join(name);
        if fs::symlink_metadata(&destination).is_err() {
            if let Some(parent) = Path::new(name).parent().and_then(Path::to_str) {
                mkdir_inside(&root_real, &root, parent)?;
            }
            symlink(&target, &destination)
                .with_context(|| format!("failed to link {}", destination.display()))?;
        }
    }

    // Ownership matches the (just created) root; the guest maps to the app uid.
    let owner = fs::metadata(&root)?;
    let (uid, gid) = (owner.uid(), owner.gid());
    let files = [
        (
            "etc/passwd",
            format!(
                "{username}:x:{uid}:{gid}:Nix user:{home}:{}\n",
                manifest.shell
            ),
        ),
        ("etc/group", format!("{username}:x:{gid}:\n")),
        (
            "etc/nsswitch.conf",
            "passwd: files\ngroup: files\nhosts: files dns\n".to_owned(),
        ),
        (
            "etc/resolv.conf",
            "nameserver 1.1.1.1\nnameserver 9.9.9.9\n".to_owned(),
        ),
        (
            "etc/hosts",
            "127.0.0.1 localhost\n::1 localhost\n".to_owned(),
        ),
        (
            "etc/bashrc",
            concat!(
                "export PATH=\"$HOME/.nix-profile/bin:$PATH\"\n",
                "PS1='(nix) \\u:\\w\\$ '\n",
                "cd \"$HOME\"\n"
            )
            .to_owned(),
        ),
    ];
    for (name, content) in &files {
        let output = root.join(name);
        if fs::symlink_metadata(&output).is_ok_and(|meta| meta.file_type().is_symlink()) {
            fs::remove_file(&output)
                .with_context(|| format!("failed to replace link {}", output.display()))?;
        }
        write_file(&output, content.as_bytes(), 0o600)?;
    }
    write_new(
        &directory.join("proc-stat"),
        b"cpu  100 0 100 1000 0 0 0 0 0 0\nbtime 1700000000\n",
        0o600,
    )?;
    write_new(&directory.join("proc-uptime"), b"1000.00 1000.00\n", 0o600)?;

    mkdir_inside(&root_real, &root, GCROOT_DIR)?;
    let roots = root.join(GCROOT_DIR);
    for (index, package) in manifest.packages.iter().enumerate() {
        let link = roots.join(index.to_string());
        symlink(package, &link)
            .with_context(|| format!("failed to create GC root {}", link.display()))?;
    }

    let values = [
        ("SESSION_USER", username.to_owned()),
        ("SESSION_HOME", home),
        ("BOOTSTRAP_NIX", nix),
        ("BOOTSTRAP_BUSYBOX", busybox),
        ("ANDROID_CA", android_ca),
        ("SESSION_PATH", manifest.path.clone()),
        ("SESSION_SHELL", manifest.shell.clone()),
        ("SESSION_CERTIFICATE", manifest.certificate.clone()),
        ("SESSION_TERMINFO", manifest.terminfo.clone()),
    ];
    let environment: String = values
        .iter()
        .map(|(key, value)| format!("{key}={}\n", shell_quote(value)))
        .collect();
    write_new(
        &directory.join("session.env"),
        environment.as_bytes(),
        0o600,
    )?;
    let mut packages = manifest.packages.join("\n");
    packages.push('\n');
    write_new(&directory.join("packages.txt"), packages.as_bytes(), 0o600)?;
    write_new(&directory.join("session.json"), &manifest_bytes, 0o600)?;

    install_scripts(directory)?;
    let launcher = directory.join(LAUNCHER_NAME);
    if fs::symlink_metadata(&launcher).is_ok_and(|meta| meta.file_type().is_file()) {
        fs::set_permissions(&launcher, fs::Permissions::from_mode(0o700))
            .with_context(|| format!("failed to chmod {}", launcher.display()))?;
    }
    progress::prepared();
    Ok(())
}

/// Write the embedded launch scripts into `directory` with mode 0700.
///
/// An existing script (or a link in its place) is replaced atomically, never
/// followed; see [`replace_with`].
pub fn install_scripts(directory: &Path) -> Result<()> {
    for (name, content) in SCRIPTS {
        replace_with(directory, name, 0o700, |file| {
            file.write_all(content.as_bytes())
        })?;
    }
    Ok(())
}

/// Copy the running executable to `DIR/nixpp` (mode 0700), so the launch
/// scripts find the controller even when `nixpp` was started from elsewhere.
/// Does nothing when `DIR/nixpp` already is the running executable.
pub fn stage_executable(directory: &Path) -> Result<()> {
    let current = std::env::current_exe().context("failed to locate the running executable")?;
    stage_executable_from(directory, &current)
}

fn stage_executable_from(directory: &Path, source: &Path) -> Result<()> {
    let source = fs::canonicalize(source)
        .with_context(|| format!("failed to resolve {}", source.display()))?;
    let directory = resolve_directory(directory)?;
    let target = directory.join(NIXPP_NAME);
    if fs::canonicalize(&target).is_ok_and(|existing| existing == source) {
        return Ok(());
    }
    replace_with(&directory, NIXPP_NAME, 0o700, |file| {
        std::io::copy(&mut File::open(&source)?, file).map(|_| ())
    })
}

/// Run `command` with its output reported line by line as progress, so
/// stdout carries only JSON. Both streams are read concurrently.
fn run_reporting(command: &mut Command) -> Result<std::process::ExitStatus> {
    use std::io::{BufRead, BufReader};
    use std::process::Stdio;
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("failed to run session.sh")?;
    let stdout = child.stdout.take().context("session.sh stdout")?;
    let reader = std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            progress::output_line(&line);
        }
    });
    if let Some(stderr) = child.stderr.take() {
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            progress::output_line(&line);
        }
    }
    let status = child.wait().context("failed to wait for session.sh")?;
    let _ = reader.join();
    Ok(status)
}

/// Import the pinned packages and run the final checks (also the resume
/// operation after an interrupted download). Writes `ready` only on success.
pub fn install(directory: &Path) -> Result<()> {
    install_with(directory, &mut |directory, args| {
        let mut command = Command::new(directory.join("session.sh"));
        command.args(args);
        let status = if progress::json() {
            run_reporting(&mut command)?
        } else {
            command.status().context("failed to run session.sh")?
        };
        ensure!(
            status.success(),
            "session.sh {} failed: {status}",
            args.join(" ")
        );
        Ok(())
    })
}

fn install_with(directory: &Path, run: &mut dyn FnMut(&Path, &[&str]) -> Result<()>) -> Result<()> {
    for name in ["session.env", "packages.txt", "session.sh", LAUNCHER_NAME] {
        ensure!(
            directory.join(name).is_file(),
            "No prepared runtime to resume: {} is missing",
            directory.join(name).display()
        );
    }
    let list = fs::read_to_string(directory.join("packages.txt"))
        .context("failed to read packages.txt")?;
    let packages: Vec<&str> = list.lines().filter(|line| !line.is_empty()).collect();
    for package in &packages {
        validate_store_path(package)?;
    }
    for (index, package) in packages.iter().copied().enumerate() {
        progress::package(index, packages.len(), package);
        run(
            directory,
            &[
                "--bootstrap",
                "--",
                "nix",
                "copy",
                "--from",
                "https://cache.nixos.org",
                package,
            ],
        )?;
        let gc_root = format!("/{GCROOT_DIR}/{index}");
        run(
            directory,
            &[
                "--bootstrap",
                "--",
                "nix-store",
                "--add-root",
                gc_root.as_str(),
                "--realise",
                package,
            ],
        )?;
    }
    progress::check();
    run(directory, &["--", "nix", "--version"])?;
    run(
        directory,
        &[
            "--",
            "python3",
            "-I",
            "-c",
            "import os; print(os.confstr(\"CS_GNU_LIBC_VERSION\"))",
        ],
    )?;
    write_file(&directory.join("ready"), b"ready\n", 0o600)?;
    progress::ready(directory);
    Ok(())
}

fn validate_username(username: &str) -> Result<()> {
    let bytes = username.as_bytes();
    let valid = (1..=32).contains(&bytes.len())
        && (bytes[0].is_ascii_lowercase() || bytes[0] == b'_')
        && bytes[1..].iter().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'_' | b'-')
        });
    ensure!(valid, "invalid guest username");
    Ok(())
}

/// `/nix/store/<32 chars [a-z0-9]>-<non-empty name without whitespace or ':'>`
/// with no `..` component.
fn validate_store_path(value: &str) -> Result<()> {
    let invalid = || anyhow::anyhow!("invalid pinned store path: {value:?}");
    let rest = value.strip_prefix("/nix/store/").ok_or_else(invalid)?;
    let bytes = rest.as_bytes();
    if bytes.len() < 34
        || !bytes[..32]
            .iter()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit())
        || bytes[32] != b'-'
    {
        return Err(invalid());
    }
    let name = &rest[33..];
    if name
        .chars()
        .any(|c| c.is_whitespace() || c == ':' || c == '\0')
        || value.split('/').any(|part| part == "..")
    {
        return Err(invalid());
    }
    Ok(())
}

fn validate_manifest(manifest: &Manifest) -> Result<()> {
    ensure!(
        manifest.schema == 1 && manifest.system == "aarch64-linux" && manifest.page_size == 4096,
        "unsupported session manifest"
    );
    for value in manifest.packages.iter().chain([
        &manifest.shell,
        &manifest.nix,
        &manifest.python,
        &manifest.zsh,
        &manifest.certificate,
        &manifest.terminfo,
    ]) {
        validate_store_path(value)?;
    }
    let expected = manifest
        .packages
        .iter()
        .map(|package| format!("{package}/bin"))
        .collect::<Vec<_>>()
        .join(":");
    ensure!(manifest.path == expected, "unexpected session PATH");
    Ok(())
}

/// POSIX single-quote quoting for values written to `session.env`.
fn shell_quote(value: &str) -> String {
    let safe = |c: char| {
        c.is_ascii_alphanumeric()
            || matches!(c, '_' | '@' | '%' | '+' | '=' | ':' | ',' | '.' | '/' | '-')
    };
    if !value.is_empty() && value.chars().all(safe) {
        value.to_owned()
    } else {
        format!("'{}'", value.replace('\'', "'\"'\"'"))
    }
}

fn sha256_hex(reader: &mut impl Read) -> Result<String> {
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect())
}

/// Copy at most `*remaining` bytes in total, decrementing the shared budget.
fn copy_bounded(
    reader: &mut impl Read,
    writer: &mut impl Write,
    remaining: &mut u64,
) -> Result<u64> {
    let mut buffer = [0u8; 64 * 1024];
    let mut total = 0u64;
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            return Ok(total);
        }
        let read_bytes = read as u64;
        ensure!(read_bytes <= *remaining, "bootstrap too large");
        *remaining -= read_bytes;
        total += read_bytes;
        writer.write_all(&buffer[..read])?;
    }
}

fn read_limited(path: &Path, limit: u64) -> Result<Vec<u8>> {
    let mut data = Vec::new();
    File::open(path)?.take(limit + 1).read_to_end(&mut data)?;
    ensure!(
        data.len() as u64 <= limit,
        "{} is too large",
        path.display()
    );
    Ok(data)
}

fn ensure_absent(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(_) => bail!("{} already exists; refusing to overwrite", path.display()),
        Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("failed to inspect {}", path.display())),
    }
}

fn private_dirs(path: &Path) -> Result<()> {
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(path)
        .with_context(|| format!("failed to create {}", path.display()))
}

/// Create a relative directory chain below `root` without ever following a
/// link out of it (existing links must resolve to a directory inside `root`).
fn mkdir_inside(root_real: &Path, root: &Path, relative: &str) -> Result<()> {
    let mut current = root.to_path_buf();
    for part in relative.split('/').filter(|part| !part.is_empty()) {
        current.push(part);
        match fs::symlink_metadata(&current) {
            Ok(_) => {
                let real = fs::canonicalize(&current)
                    .with_context(|| format!("cannot resolve {}", current.display()))?;
                ensure!(
                    real.starts_with(root_real) && real.is_dir(),
                    "{} escapes the runtime root or is not a directory",
                    current.display()
                );
            }
            Err(error) if error.kind() == ErrorKind::NotFound => {
                DirBuilder::new()
                    .mode(0o700)
                    .create(&current)
                    .with_context(|| format!("failed to create {}", current.display()))?;
            }
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("failed to inspect {}", current.display()));
            }
        }
    }
    Ok(())
}

fn write_new(path: &Path, content: &[u8], mode: u32) -> Result<()> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(mode)
        .open(path)
        .and_then(|mut file| file.write_all(content))
        .with_context(|| format!("failed to create {}", path.display()))
}

/// Resolve `directory` once; ancestors that are links (e.g. `/data/data`) are
/// followed here and never again.
fn resolve_directory(directory: &Path) -> Result<PathBuf> {
    let resolved = fs::canonicalize(directory)
        .with_context(|| format!("failed to resolve {}", directory.display()))?;
    ensure!(
        resolved.is_dir(),
        "{} is not a directory",
        resolved.display()
    );
    Ok(resolved)
}

/// Atomically replace `directory/name` with content produced by `fill`.
///
/// The content goes to an exclusively created unique temporary file next to
/// the target, is synced, and renamed over it. A link or file already at the
/// target is replaced, never followed or written through. A failure removes
/// the temporary file and leaves the target as it was.
fn replace_with(
    directory: &Path,
    name: &str,
    mode: u32,
    fill: impl FnOnce(&mut File) -> std::io::Result<()>,
) -> Result<()> {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let directory = resolve_directory(directory)?;
    let target = directory.join(name);
    ensure!(
        !fs::symlink_metadata(&target).is_ok_and(|meta| meta.is_dir()),
        "{} is a directory",
        target.display()
    );
    let mut attempts = 0;
    let (temporary, mut file) = loop {
        let temporary = directory.join(format!(
            ".{name}.{}.{}.tmp",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .open(&temporary)
        {
            Ok(file) => break (temporary, file),
            Err(error) if error.kind() == ErrorKind::AlreadyExists && attempts < 16 => {
                attempts += 1;
            }
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("failed to create {}", temporary.display()));
            }
        }
    };
    let mut cleanup = TempFile(Some(temporary.clone()));
    file.set_permissions(fs::Permissions::from_mode(mode))
        .and_then(|()| fill(&mut file))
        .and_then(|()| file.sync_all())
        .with_context(|| format!("failed to write {}", temporary.display()))?;
    drop(file);
    fs::rename(&temporary, &target)
        .with_context(|| format!("failed to install {}", target.display()))?;
    cleanup.0 = None;
    // Best effort: make the rename itself durable.
    let _ = File::open(&directory).and_then(|handle| handle.sync_all());
    Ok(())
}

/// Removes its file on drop unless disarmed by clearing the path.
struct TempFile(Option<PathBuf>);

impl Drop for TempFile {
    fn drop(&mut self) {
        if let Some(path) = self.0.take() {
            let _ = fs::remove_file(path);
        }
    }
}

fn write_file(path: &Path, content: &[u8], mode: u32) -> Result<()> {
    OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(mode)
        .open(path)
        .and_then(|mut file| file.write_all(content))
        .with_context(|| format!("failed to write {}", path.display()))
}

/// Map an archive member name below `root`, rejecting absolute names, `..`
/// components and NUL bytes. Empty and `.` components are ignored.
fn safe_join(root: &Path, name: &str) -> Result<PathBuf> {
    ensure!(
        !name.starts_with('/') && !name.contains('\0') && name.len() <= MAX_NAME_BYTES,
        "unsafe archive path"
    );
    let mut output = root.to_path_buf();
    let mut any = false;
    for part in name.split('/') {
        match part {
            "" | "." => {}
            ".." => bail!("unsafe archive path"),
            part => {
                output.push(part);
                any = true;
            }
        }
    }
    ensure!(any, "unsafe archive path");
    Ok(output)
}

/// Exactly one real directory in `store` whose name contains `marker`.
fn find_store_dir(store: &Path, marker: &str) -> Result<String> {
    let mut found = Vec::new();
    for entry in
        fs::read_dir(store).with_context(|| format!("failed to list {}", store.display()))?
    {
        let entry = entry?;
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if !name.starts_with('.') && name.contains(marker) && entry.file_type()?.is_dir() {
            found.push(name);
        }
    }
    found.sort();
    ensure!(
        found.len() == 1,
        "expected exactly one {marker} store directory, found {}",
        found.len()
    );
    Ok(found.remove(0))
}

/// Verify the seed hash, then extract the seed ZIP into a new `root`.
/// Nothing is created when the hash does not match; an existing `root` is
/// never touched. A failed extraction leaves the partial `root` for
/// inspection.
fn extract_bootstrap(
    seed: &Path,
    root: &Path,
    expected_sha256: &str,
    limits: Limits,
) -> Result<()> {
    // Hash and read the very same open file so the verified bytes are the used bytes.
    let mut file =
        File::open(seed).with_context(|| format!("failed to open {}", seed.display()))?;
    ensure!(
        file.metadata()?.len() <= limits.archive_bytes,
        "bootstrap too large"
    );
    ensure!(
        sha256_hex(&mut file)? == expected_sha256,
        "bootstrap seed checksum mismatch"
    );
    file.seek(SeekFrom::Start(0))?;
    let mut inner = ZipArchive::new(file).context("bootstrap seed is not a ZIP archive")?;

    DirBuilder::new()
        .mode(0o700)
        .create(root)
        .with_context(|| format!("failed to create runtime root {}", root.display()))?;

    ensure!(
        inner.len() <= limits.entries,
        "bootstrap has too many entries"
    );
    let mut declared = 0u64;
    for index in 0..inner.len() {
        declared = declared.saturating_add(inner.by_index(index)?.size());
    }
    ensure!(declared <= limits.extracted_bytes, "bootstrap too large");

    let mut remaining = limits.extracted_bytes;
    for index in 0..inner.len() {
        let mut member = inner.by_index(index)?;
        let output = safe_join(root, member.name())?;
        if let Some(mode) = member.unix_mode() {
            match mode & 0o170_000 {
                0 | 0o100_000 | 0o040_000 => {}
                0o120_000 => bail!("unexpected ZIP symlink"),
                _ => bail!("unsupported ZIP entry type"),
            }
        }
        if member.is_dir() {
            private_dirs(&output)?;
            continue;
        }
        if let Some(directory) = output.parent() {
            private_dirs(directory)?;
        }
        let mut out = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&output)
            .with_context(|| format!("failed to create {}", output.display()))?;
        let written = copy_bounded(&mut member, &mut out, &mut remaining)?;
        ensure!(
            written == member.size(),
            "archive member {} has an unexpected size",
            member.name()
        );
    }

    let executables =
        String::from_utf8(read_limited(&root.join("EXECUTABLES.txt"), MAX_LIST_BYTES)?)
            .context("EXECUTABLES.txt is not UTF-8")?;
    for name in executables.lines() {
        let path = safe_join(root, name)?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700))
            .with_context(|| format!("failed to chmod {}", path.display()))?;
    }
    let links = String::from_utf8(read_limited(&root.join("SYMLINKS.txt"), MAX_LIST_BYTES)?)
        .context("SYMLINKS.txt is not UTF-8")?;
    for line in links.lines() {
        let (target, name) = line
            .split_once('←')
            .with_context(|| format!("malformed SYMLINKS.txt line {line:?}"))?;
        let output = safe_join(root, name)?;
        if let Some(directory) = output.parent() {
            // Checked before creating anything: no ancestor may be a link.
            let mut ancestor = Some(directory);
            while let Some(path) = ancestor {
                if !path.starts_with(root) {
                    break;
                }
                if fs::symlink_metadata(path).is_ok_and(|meta| meta.file_type().is_symlink()) {
                    bail!("symlink parent");
                }
                ancestor = path.parent();
            }
            private_dirs(directory)?;
        }
        symlink(target, &output).with_context(|| format!("failed to link {}", output.display()))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use zip::write::SimpleFileOptions;
    use zip::{CompressionMethod, ZipWriter};

    struct TestDir(PathBuf);

    impl TestDir {
        fn new(label: &str) -> Self {
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let path = std::env::temp_dir().join(format!(
                "nixpp-bootstrap-{label}-{}-{}",
                std::process::id(),
                COUNTER.fetch_add(1, Ordering::SeqCst)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    enum Member<'a> {
        File(&'a str, &'a [u8]),
        Symlink(&'a str, &'a str),
    }

    fn options() -> SimpleFileOptions {
        SimpleFileOptions::default().compression_method(CompressionMethod::Stored)
    }

    fn zip_bytes(members: &[Member]) -> Vec<u8> {
        let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
        for member in members {
            match member {
                Member::File(name, content) => {
                    writer.start_file(*name, options()).unwrap();
                    writer.write_all(content).unwrap();
                }
                Member::Symlink(name, target) => {
                    writer.add_symlink(*name, *target, options()).unwrap();
                }
            }
        }
        writer.finish().unwrap().into_inner()
    }

    /// Write a bootstrap seed ZIP holding `members`.
    fn seed(directory: &Path, members: &[Member]) -> (PathBuf, String) {
        let bytes = zip_bytes(members);
        let path = directory.join(BOOTSTRAP_NAME);
        fs::write(&path, &bytes).unwrap();
        let digest = sha256_hex(&mut Cursor::new(bytes)).unwrap();
        (path, digest)
    }

    const BUSYBOX: &str =
        "nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-busybox-static-1.36/bin/busybox";
    const NIX: &str = "nix/store/cccccccccccccccccccccccccccccccc-nix-static-2.24/bin/nix";

    fn fixture_members() -> Vec<Member<'static>> {
        vec![
            Member::File(BUSYBOX, b"busybox"),
            Member::File(NIX, b"nix"),
            Member::File(
                "EXECUTABLES.txt",
                concat!(
                    "nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-busybox-static-1.36/bin/busybox\n",
                    "nix/store/cccccccccccccccccccccccccccccccc-nix-static-2.24/bin/nix\n"
                )
                .as_bytes(),
            ),
            Member::File("SYMLINKS.txt", "busybox←bin/applet\n".as_bytes()),
        ]
    }

    fn package(letter: char, name: &str) -> String {
        format!("/nix/store/{}-{name}", letter.to_string().repeat(32))
    }

    fn manifest_json(packages: &[String], path: Option<&str>) -> String {
        let first = &packages[0];
        let joined = packages
            .iter()
            .map(|p| format!("{p}/bin"))
            .collect::<Vec<_>>()
            .join(":");
        serde_json::json!({
            "schema": 1,
            "system": "aarch64-linux",
            "pageSize": 4096,
            "packages": packages,
            "shell": format!("{first}/bin/bash"),
            "nix": format!("{first}/bin/nix"),
            "python": format!("{first}/bin/python3"),
            "zsh": format!("{first}/bin/zsh"),
            "certificate": format!("{first}/etc/ssl/certs/ca-bundle.crt"),
            "terminfo": format!("{first}/share/terminfo"),
            "path": path.map_or(joined, str::to_owned),
        })
        .to_string()
    }

    struct Prepared {
        _dir: TestDir,
        directory: PathBuf,
    }

    fn run_prepare(username: &str) -> Prepared {
        let dir = TestDir::new("prepare");
        let directory = dir.path().join("runtime");
        let sources = dir.path().join("sources");
        fs::create_dir_all(&sources).unwrap();
        let (seed_path, digest) = seed(&sources, &fixture_members());
        let manifest = sources.join("manifest.json");
        fs::write(&manifest, manifest_json(&[package('a', "session")], None)).unwrap();
        let certificate = sources.join("cert.pem");
        fs::write(&certificate, "cert").unwrap();
        prepare_with(
            &directory,
            &seed_path,
            &manifest,
            &certificate,
            username,
            &digest,
            Limits::default(),
        )
        .unwrap();
        Prepared {
            _dir: dir,
            directory,
        }
    }

    #[test]
    fn guest_identity_and_runtime_files() {
        for username in ["nix", "pschmitt"] {
            let prepared = run_prepare(username);
            let directory = &prepared.directory;
            let root = directory.join("root");
            let home = format!("/home/{username}");
            assert!(root.join(home.trim_start_matches('/')).is_dir());
            let passwd = fs::read_to_string(root.join("etc/passwd")).unwrap();
            let fields: Vec<&str> = passwd.trim().split(':').collect();
            assert_eq!(fields[0], username);
            assert_eq!(fields[5], home);
            assert_eq!(fields[6], format!("{}/bin/bash", package('a', "session")));
            assert!(
                fs::read_to_string(root.join("etc/group"))
                    .unwrap()
                    .starts_with(&format!("{username}:"))
            );
            let environment = fs::read_to_string(directory.join("session.env")).unwrap();
            assert!(environment.contains(&format!("SESSION_USER={username}\n")));
            assert!(environment.contains(&format!("SESSION_HOME={home}\n")));
            assert!(environment.contains(
                "BOOTSTRAP_NIX=/nix/store/cccccccccccccccccccccccccccccccc-nix-static-2.24\n"
            ));
            assert!(environment.contains("ANDROID_CA="));
            assert_eq!(
                fs::read_to_string(directory.join("packages.txt")).unwrap(),
                format!("{}\n", package('a', "session"))
            );
            assert!(directory.join("session.json").is_file());
            assert!(directory.join("proc-stat").is_file());
            assert_eq!(
                fs::read_link(root.join(GCROOT_DIR).join("0")).unwrap(),
                PathBuf::from(package('a', "session"))
            );
            assert_eq!(
                fs::read_link(root.join("bin/sh")).unwrap(),
                PathBuf::from(
                    "/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-busybox-static-1.36/bin/sh"
                )
            );
            assert_eq!(
                fs::metadata(root.join(BUSYBOX))
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o700
            );
            assert_eq!(
                fs::read_link(root.join("bin/applet")).unwrap(),
                PathBuf::from("busybox")
            );
            for (name, content) in SCRIPTS {
                assert_eq!(fs::read_to_string(directory.join(name)).unwrap(), content);
                assert_eq!(
                    fs::metadata(directory.join(name))
                        .unwrap()
                        .permissions()
                        .mode()
                        & 0o777,
                    0o700
                );
            }
            assert!(!directory.join("bootstrap.zip").exists());
        }
    }

    #[test]
    fn invalid_usernames_rejected() {
        for username in [
            "../outside",
            "/root",
            "a:b",
            "",
            "a b",
            "x".repeat(33).as_str(),
            "1abc",
            "Abc",
        ] {
            assert!(validate_username(username).is_err(), "{username:?}");
        }
        for username in ["nix", "_x", "a-b_c9", "x".repeat(32).as_str()] {
            assert!(validate_username(username).is_ok(), "{username:?}");
        }
        let dir = TestDir::new("username");
        let missing = dir.path().join("missing");
        let error =
            prepare(&dir.path().join("rt"), &missing, &missing, &missing, "../x").unwrap_err();
        assert!(error.to_string().contains("username"));
        assert!(!dir.path().join("rt").exists());
    }

    #[test]
    fn unpinned_build_refuses_to_prepare() {
        if BOOTSTRAP_SHA256.is_some() {
            return;
        }
        let dir = TestDir::new("unpinned");
        let missing = dir.path().join("missing");
        let error =
            prepare(&dir.path().join("rt"), &missing, &missing, &missing, "nix").unwrap_err();
        assert!(error.to_string().contains("no pinned bootstrap seed"));
        assert!(!dir.path().join("rt").exists());
    }

    #[test]
    fn bad_hash_does_not_create_root() {
        let dir = TestDir::new("hash");
        let (seed_path, _) = seed(dir.path(), &fixture_members());
        let root = dir.path().join("root");
        let error =
            extract_bootstrap(&seed_path, &root, &"0".repeat(64), Limits::default()).unwrap_err();
        assert!(error.to_string().contains("checksum"));
        assert!(!root.exists());
        assert!(!dir.path().join("bootstrap.zip").exists());
    }

    #[test]
    fn safe_archive() {
        let dir = TestDir::new("safe");
        let members = [
            Member::File("bin/tool", b"ok"),
            Member::File("EXECUTABLES.txt", b"bin/tool\n"),
            Member::File("SYMLINKS.txt", "tool←bin/link\n".as_bytes()),
        ];
        let (seed_path, digest) = seed(dir.path(), &members);
        let root = dir.path().join("root");
        extract_bootstrap(&seed_path, &root, &digest, Limits::default()).unwrap();
        assert_eq!(fs::read_to_string(root.join("bin/link")).unwrap(), "ok");
        assert_eq!(
            fs::metadata(root.join("bin/tool"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
        assert!(!dir.path().join("bootstrap.zip").exists());
    }

    #[test]
    fn traversal_rejected() {
        for name in ["../escape", "a/../../escape", "/abs/escape"] {
            let dir = TestDir::new("traversal");
            let (seed_path, digest) = seed(dir.path(), &[Member::File(name, b"bad")]);
            let root = dir.path().join("root");
            let error =
                extract_bootstrap(&seed_path, &root, &digest, Limits::default()).unwrap_err();
            assert!(error.to_string().contains("unsafe"), "{name}: {error}");
            assert!(!dir.path().join("escape").exists());
            assert!(!Path::new("/abs/escape").exists());
        }
    }

    #[test]
    fn safe_join_rules() {
        let root = Path::new("/r");
        assert_eq!(
            safe_join(root, "a//b/./c/").unwrap(),
            PathBuf::from("/r/a/b/c")
        );
        for name in ["", ".", "/", "/a", "a/..", "../a", "a\0b"] {
            assert!(safe_join(root, name).is_err(), "{name:?}");
        }
    }

    #[test]
    fn zip_symlink_member_rejected() {
        let dir = TestDir::new("zip-symlink");
        let (seed_path, digest) = seed(dir.path(), &[Member::Symlink("link", "/etc")]);
        let error = extract_bootstrap(
            &seed_path,
            &dir.path().join("root"),
            &digest,
            Limits::default(),
        )
        .unwrap_err();
        assert!(error.to_string().contains("symlink"));
    }

    #[test]
    fn existing_root_is_not_overwritten() {
        let dir = TestDir::new("existing");
        let root = dir.path().join("root");
        fs::create_dir(&root).unwrap();
        fs::write(root.join("keep"), "preserved").unwrap();
        let (seed_path, digest) = seed(dir.path(), &fixture_members());
        let error = extract_bootstrap(&seed_path, &root, &digest, Limits::default()).unwrap_err();
        assert!(format!("{error:#}").contains("exists"), "{error:#}");
        assert_eq!(fs::read_to_string(root.join("keep")).unwrap(), "preserved");

        // The full entry point refuses before doing anything else.
        let sources = dir.path().join("src");
        fs::create_dir(&sources).unwrap();
        let manifest = sources.join("manifest.json");
        fs::write(&manifest, manifest_json(&[package('a', "session")], None)).unwrap();
        let error = prepare_with(
            dir.path(),
            &seed_path,
            &manifest,
            &manifest,
            "nix",
            &digest,
            Limits::default(),
        )
        .unwrap_err();
        assert!(error.to_string().contains("already exists"));
        assert_eq!(fs::read_to_string(root.join("keep")).unwrap(), "preserved");
        assert!(!dir.path().join("session.env").exists());
    }

    #[test]
    fn symlink_parent_rejected() {
        let dir = TestDir::new("symlink-parent");
        let members = [
            Member::File("EXECUTABLES.txt", b""),
            Member::File(
                "SYMLINKS.txt",
                "/outside←escape\ntarget←escape/file\n".as_bytes(),
            ),
        ];
        let (seed_path, digest) = seed(dir.path(), &members);
        let error = extract_bootstrap(
            &seed_path,
            &dir.path().join("root"),
            &digest,
            Limits::default(),
        )
        .unwrap_err();
        assert!(error.to_string().contains("symlink parent"));
        assert!(!Path::new("/outside").exists());
    }

    #[test]
    fn extraction_is_bounded() {
        let dir = TestDir::new("bounded");
        let (seed_path, digest) = seed(dir.path(), &fixture_members());
        let root = dir.path().join("root");
        let small = Limits {
            extracted_bytes: 4,
            ..Limits::default()
        };
        let error = extract_bootstrap(&seed_path, &root, &digest, small).unwrap_err();
        assert!(error.to_string().contains("too large"));

        let few = Limits {
            entries: 1,
            ..Limits::default()
        };
        let error =
            extract_bootstrap(&seed_path, &dir.path().join("root2"), &digest, few).unwrap_err();
        assert!(error.to_string().contains("too many"));

        let tiny = Limits {
            archive_bytes: 8,
            ..Limits::default()
        };
        let error =
            extract_bootstrap(&seed_path, &dir.path().join("root3"), &digest, tiny).unwrap_err();
        assert!(error.to_string().contains("too large"));
        assert!(!dir.path().join("root3").exists());
    }

    #[test]
    fn copy_bounded_enforces_shared_budget() {
        let mut budget = 5;
        let mut out = Vec::new();
        assert_eq!(
            copy_bounded(&mut Cursor::new(b"abc"), &mut out, &mut budget).unwrap(),
            3
        );
        assert!(copy_bounded(&mut Cursor::new(b"def"), &mut out, &mut budget).is_err());
    }

    #[test]
    fn manifest_validation() {
        let good = vec![package('a', "session")];
        let parse = |json: String| -> Result<()> {
            let manifest: Manifest = serde_json::from_str(&json)?;
            validate_manifest(&manifest)
        };
        parse(manifest_json(&good, None)).unwrap();

        let error = parse(manifest_json(&good, Some("/usr/bin"))).unwrap_err();
        assert!(error.to_string().contains("PATH"));

        let mut value: serde_json::Value =
            serde_json::from_str(&manifest_json(&good, None)).unwrap();
        value["schema"] = 2.into();
        assert!(
            parse(value.to_string())
                .unwrap_err()
                .to_string()
                .contains("unsupported")
        );
        value["schema"] = 1.into();
        value["pageSize"] = 16384.into();
        assert!(
            parse(value.to_string())
                .unwrap_err()
                .to_string()
                .contains("unsupported")
        );
        value["pageSize"] = 4096.into();
        value["system"] = "x86_64-linux".into();
        assert!(
            parse(value.to_string())
                .unwrap_err()
                .to_string()
                .contains("unsupported")
        );
        value["system"] = "aarch64-linux".into();
        value["shell"] = "/bin/sh".into();
        assert!(
            parse(value.to_string())
                .unwrap_err()
                .to_string()
                .contains("store path")
        );

        let bad = vec![format!("{}/../x", package('a', "session"))];
        assert!(parse(manifest_json(&bad, None)).is_err());
    }

    #[test]
    fn store_path_validation() {
        for valid in [
            package('a', "x"),
            format!("{}/bin/bash", package('0', "bash-5.2")),
        ] {
            assert!(validate_store_path(&valid).is_ok(), "{valid}");
        }
        for invalid in [
            "/nix/store/short-x".to_owned(),
            format!("/nix/store/{}-", "a".repeat(32)),
            format!("/nix/store/{}x", "a".repeat(33)),
            format!("/nix/store/{}-x", "A".repeat(32)),
            format!("/nix/store/{}-x y", "a".repeat(32)),
            format!("/nix/store/{}-x:y", "a".repeat(32)),
            format!("{}/../etc", package('a', "x")),
            format!("-{}", package('a', "x")),
            "/tmp/x".to_owned(),
        ] {
            assert!(validate_store_path(&invalid).is_err(), "{invalid}");
        }
    }

    #[test]
    fn shell_quote_matches_shlex() {
        assert_eq!(shell_quote("/nix/store/a-b:/c.d"), "/nix/store/a-b:/c.d");
        assert_eq!(shell_quote(""), "''");
        assert_eq!(shell_quote("a b"), "'a b'");
        assert_eq!(shell_quote("it's"), "'it'\"'\"'s'");
        assert_eq!(shell_quote("$HOME"), "'$HOME'");
    }

    #[test]
    fn platform_check() {
        assert!(platform_ok("aarch64", "4096").is_ok());
        assert!(platform_ok("aarch64", "16384").is_err());
        assert!(platform_ok("x86_64", "4096").is_err());
    }

    #[test]
    fn find_store_dir_requires_exactly_one() {
        let dir = TestDir::new("store");
        fs::create_dir(dir.path().join("a-nix-static-1")).unwrap();
        fs::write(dir.path().join("b-nix-static-file"), "").unwrap();
        assert_eq!(
            find_store_dir(dir.path(), "-nix-static-").unwrap(),
            "a-nix-static-1"
        );
        fs::create_dir(dir.path().join("c-nix-static-2")).unwrap();
        assert!(find_store_dir(dir.path(), "-nix-static-").is_err());
        assert!(find_store_dir(dir.path(), "-busybox-static-").is_err());
    }

    #[test]
    fn scripts_are_embedded_and_replaced_atomically() {
        for (name, content) in SCRIPTS {
            assert!(content.starts_with("#!/system/bin/sh\n"), "{name}");
            assert!(!content.lines().any(|line| line.ends_with(' ')), "{name}");
        }
        let dir = TestDir::new("scripts");
        fs::write(dir.path().join("session.sh"), "old").unwrap();
        install_scripts(dir.path()).unwrap();
        install_scripts(dir.path()).unwrap();
        assert_eq!(
            fs::read_to_string(dir.path().join("session.sh")).unwrap(),
            SCRIPTS[0].1
        );
        let leftovers = fs::read_dir(dir.path())
            .unwrap()
            .filter_map(Result::ok)
            .filter(|entry| entry.file_name().to_string_lossy().ends_with(".tmp"))
            .count();
        assert_eq!(leftovers, 0);
    }

    fn entries(directory: &Path) -> Vec<String> {
        let mut names: Vec<String> = fs::read_dir(directory)
            .unwrap()
            .filter_map(Result::ok)
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    #[test]
    fn script_links_are_replaced_not_followed() {
        let dir = TestDir::new("script-link");
        let victim = dir.path().join("victim");
        fs::write(&victim, "precious").unwrap();
        let runtime = dir.path().join("runtime");
        fs::create_dir(&runtime).unwrap();
        symlink(&victim, runtime.join("session.sh")).unwrap();
        install_scripts(&runtime).unwrap();
        assert_eq!(fs::read_to_string(&victim).unwrap(), "precious");
        let installed = fs::symlink_metadata(runtime.join("session.sh")).unwrap();
        assert!(installed.file_type().is_file());
        assert_eq!(installed.permissions().mode() & 0o777, 0o700);
        assert_eq!(
            fs::read_to_string(runtime.join("session.sh")).unwrap(),
            SCRIPTS[0].1
        );
    }

    #[test]
    fn runtime_directory_link_is_resolved_once() {
        let dir = TestDir::new("directory-link");
        let real = dir.path().join("real");
        fs::create_dir(&real).unwrap();
        let link = dir.path().join("link");
        symlink(&real, &link).unwrap();
        install_scripts(&link).unwrap();
        assert!(real.join("login.sh").is_file());
        assert!(entries(&real).iter().all(|name| !name.ends_with(".tmp")));

        let file = dir.path().join("file");
        fs::write(&file, "").unwrap();
        assert!(install_scripts(&file).is_err());
        assert!(install_scripts(&dir.path().join("missing")).is_err());
    }

    #[test]
    fn failed_replace_keeps_target_and_removes_temporary() {
        let dir = TestDir::new("replace-fail");
        fs::write(dir.path().join("target"), "old").unwrap();
        let result = replace_with(dir.path(), "target", 0o600, |file| {
            file.write_all(b"partial")?;
            Err(std::io::Error::other("boom"))
        });
        assert!(result.is_err());
        assert_eq!(
            fs::read_to_string(dir.path().join("target")).unwrap(),
            "old"
        );
        assert_eq!(entries(dir.path()), ["target"]);

        fs::create_dir(dir.path().join("folder")).unwrap();
        assert!(replace_with(dir.path(), "folder", 0o600, |_| Ok(())).is_err());
        assert!(dir.path().join("folder").is_dir());
    }

    #[test]
    fn stage_executable_copies_privately_and_replaces_links() {
        let dir = TestDir::new("stage");
        let source = dir.path().join("elsewhere-nixpp");
        fs::write(&source, "binary").unwrap();
        fs::set_permissions(&source, fs::Permissions::from_mode(0o755)).unwrap();
        let runtime = dir.path().join("runtime");
        fs::create_dir(&runtime).unwrap();
        let victim = dir.path().join("victim");
        fs::write(&victim, "precious").unwrap();
        symlink(&victim, runtime.join(NIXPP_NAME)).unwrap();

        stage_executable_from(&runtime, &source).unwrap();
        let staged = fs::symlink_metadata(runtime.join(NIXPP_NAME)).unwrap();
        assert!(staged.file_type().is_file());
        assert_eq!(staged.permissions().mode() & 0o777, 0o700);
        assert_eq!(
            fs::read_to_string(runtime.join(NIXPP_NAME)).unwrap(),
            "binary"
        );
        assert_eq!(fs::read_to_string(&victim).unwrap(), "precious");
        assert_eq!(entries(&runtime), [NIXPP_NAME]);

        fs::write(&source, "newer").unwrap();
        stage_executable_from(&runtime, &source).unwrap();
        assert_eq!(
            fs::read_to_string(runtime.join(NIXPP_NAME)).unwrap(),
            "newer"
        );
    }

    #[test]
    fn stage_executable_is_a_noop_for_the_same_path() {
        let dir = TestDir::new("stage-same");
        let runtime = dir.path().join("runtime");
        fs::create_dir(&runtime).unwrap();
        let staged = runtime.join(NIXPP_NAME);
        fs::write(&staged, "binary").unwrap();
        let before = fs::metadata(&staged).unwrap().ino();

        stage_executable_from(&runtime, &staged).unwrap();
        // Reached through a link to the same file, as when invoked via a symlink.
        let alias = dir.path().join("alias");
        symlink(&staged, &alias).unwrap();
        stage_executable_from(&runtime, &alias).unwrap();

        assert_eq!(fs::metadata(&staged).unwrap().ino(), before);
        assert_eq!(entries(&runtime), [NIXPP_NAME]);
        assert!(stage_executable_from(&runtime, &dir.path().join("missing")).is_err());
    }

    fn prepared_for_install(packages: &[&str]) -> TestDir {
        let dir = TestDir::new("install");
        for name in ["session.env", "session.sh", LAUNCHER_NAME] {
            fs::write(dir.path().join(name), "").unwrap();
        }
        let mut list = packages.join("\n");
        list.push('\n');
        fs::write(dir.path().join("packages.txt"), list).unwrap();
        dir
    }

    #[test]
    fn install_runs_import_roots_and_checks_then_marks_ready() {
        let first = package('a', "one");
        let second = package('d', "two");
        let dir = prepared_for_install(&[first.as_str(), second.as_str()]);
        let mut calls: Vec<Vec<String>> = Vec::new();
        install_with(dir.path(), &mut |_, args| {
            calls.push(args.iter().map(ToString::to_string).collect());
            Ok(())
        })
        .unwrap();
        assert_eq!(calls.len(), 6);
        assert_eq!(
            calls[0],
            [
                "--bootstrap",
                "--",
                "nix",
                "copy",
                "--from",
                "https://cache.nixos.org",
                first.as_str()
            ]
        );
        assert_eq!(
            calls[1],
            [
                "--bootstrap",
                "--",
                "nix-store",
                "--add-root",
                "/nix/var/nix/gcroots/termuxpp-session/0",
                "--realise",
                first.as_str()
            ]
        );
        assert_eq!(calls[2][6], second);
        assert_eq!(calls[3][4], "/nix/var/nix/gcroots/termuxpp-session/1");
        assert_eq!(calls[4], ["--", "nix", "--version"]);
        assert_eq!(calls[5][..4], ["--", "python3", "-I", "-c"]);
        assert_eq!(
            fs::read_to_string(dir.path().join("ready")).unwrap(),
            "ready\n"
        );
    }

    #[test]
    fn install_failure_does_not_mark_ready() {
        let first = package('a', "one");
        let dir = prepared_for_install(&[first.as_str()]);
        let mut count = 0;
        let result = install_with(dir.path(), &mut |_, _| {
            count += 1;
            if count == 2 {
                bail!("nix-store failed")
            } else {
                Ok(())
            }
        });
        assert!(result.is_err());
        assert!(!dir.path().join("ready").exists());
    }

    #[test]
    fn install_rejects_unprepared_runtime_and_option_like_packages() {
        let dir = TestDir::new("install-missing");
        let error = install_with(dir.path(), &mut |_, _| Ok(())).unwrap_err();
        assert!(error.to_string().contains("No prepared runtime"));

        let dir = prepared_for_install(&["--option"]);
        let mut ran = false;
        let error = install_with(dir.path(), &mut |_, _| {
            ran = true;
            Ok(())
        })
        .unwrap_err();
        assert!(error.to_string().contains("store path"));
        assert!(!ran);
    }
}

//! Enroll a new managed guest beside the current runtime.

use crate::{bootstrap, controller, fsutil, guest, provision, runner::SessionRunner, store};
use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};
use std::fs::{self, DirBuilder};
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

pub fn enroll(
    runtime: &Path,
    user: &str,
    flake: &str,
    host: &str,
    credentials: &Path,
) -> Result<()> {
    ensure!(
        cfg!(target_os = "android"),
        "run bootstrap in a native TermuxPP session"
    );
    ensure!(runtime.is_absolute(), "the runtime path must be absolute");
    ensure!(store::is_user_name(user), "invalid guest user");
    let build = guest::build_command(flake, host, false)?;
    let build_host = fsutil::read_bounded(&credentials.join("build_host"), 4096)
        .context("missing initial build worker")?;
    let build_host = std::str::from_utf8(&build_host)?.trim();
    ensure!(
        store::is_host_name(build_host),
        "invalid initial build worker SSH alias"
    );
    let target = build.last().context("missing Nix build target")?;
    let parent = runtime
        .parent()
        .context("runtime requires a parent directory")?;
    fs::create_dir_all(parent)?;
    let staged = sibling(runtime, ".enrollment")?;
    let previous = sibling(runtime, ".before-enrollment")?;
    let _lock = fsutil::FileLock::acquire(&sibling(runtime, ".enrollment.lock")?)?;

    if runtime.join("system-state.json").is_file() {
        ensure!(
            fs::read_to_string(runtime.join("enrolled-host"))
                .unwrap_or_default()
                .trim()
                == host
                && fs::read_to_string(runtime.join("enrolled-user"))
                    .unwrap_or_default()
                    .trim()
                    == user,
            "this runtime is already managed; use nixpp rebuild in the guest"
        );
        println!("The guest is already enrolled. Open a new TermuxPP session.");
        return Ok(());
    }
    ensure!(
        runtime.try_exists()? || !previous.try_exists()? || staged.try_exists()?,
        "an earlier enrollment backup exists without a staged runtime"
    );
    ensure!(
        !runtime.try_exists()? || !previous.try_exists()?,
        "the enrollment backup path is already occupied"
    );

    let staged_config = staged.join("session.env");
    if staged_config.is_file() {
        ensure!(
            fs::read_to_string(staged_config)?
                .lines()
                .any(|line| line == format!("SESSION_USER={user}")),
            "an incomplete enrollment exists for a different user"
        );
    }
    match provision::setup_state(&staged) {
        provision::Setup::Ready => {}
        provision::Setup::Resume => bootstrap::resume(&staged)?,
        provision::Setup::Init => provision::init(
            &staged,
            provision::Inputs {
                seed: None,
                manifest: None,
                certificate: None,
                bootstrap_dir: None,
                user,
            },
        )?,
    }

    // Guest sockets are translated to native paths. The staging directory
    // suffix would push tmux and other Unix sockets past Android's limit.
    use_short_tmp(&staged, runtime)?;
    // Enrollment only writes into the newly created private guest home.
    let home = staged.join("root/home").join(user);
    let cache = EnrollmentCache::read(credentials)?;
    install_credentials(&home, credentials)?;
    let activate_result = if !staged.join("current-system").is_file()
        || fs::read_to_string(staged.join("current-system"))?
            .trim()
            .is_empty()
        || staged.join("system-pending.json").exists()
    {
        activate(&staged, user, build_host, target, cache.as_ref())
    } else {
        Ok(())
    };
    let cached_credentials = home.join(".config/nixpp-enrollment/cache_credentials");
    match fs::remove_file(cached_credentials) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error).context("remove temporary cache credentials"),
    }
    activate_result?;

    fs::remove_dir_all(
        staged
            .join("root/home")
            .join(user)
            .join(".config/nixpp-enrollment"),
    )
    .context("failed to remove initial worker SSH settings")?;
    fsutil::atomic_write(&staged.join("system.enabled"), "")?;
    fsutil::atomic_write(&staged.join("enrolled-host"), host)?;
    fsutil::atomic_write(&staged.join("enrolled-user"), user)?;
    if runtime.try_exists()? {
        fs::rename(runtime, &previous).context("failed to retain the previous guest")?;
    }
    if let Err(error) = fs::rename(&staged, runtime) {
        if previous.try_exists()? {
            fs::rename(&previous, runtime)
                .context("failed to restore previous guest after enrollment")?;
        }
        return Err(error).context("failed to select the enrolled guest");
    }
    println!("Enrollment complete. Open a new TermuxPP session.");
    Ok(())
}

fn sibling(path: &Path, suffix: &str) -> Result<PathBuf> {
    let mut name = path
        .file_name()
        .context("invalid runtime directory")?
        .to_os_string();
    name.push(suffix);
    Ok(path.with_file_name(name))
}

fn use_short_tmp(staged: &Path, runtime: &Path) -> Result<()> {
    let file = staged.join("session.env");
    let mut environment = fs::read_to_string(&file)?;
    if environment
        .lines()
        .any(|line| line.starts_with("SESSION_TMP_DIR="))
    {
        return Ok(());
    }
    let data = std::env::var_os("TERMUX_APP__DATA_DIR")
        .context("enrollment requires the TermuxPP app data directory")?;
    let files = fs::canonicalize(PathBuf::from(data).join("files"))?;
    let key = format!(
        "{:x}",
        Sha256::digest(runtime.as_os_str().as_encoded_bytes())
    );
    let temp = files.join(format!(".npt-{}", &key[..8]));
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&temp)?;
    ensure!(
        fs::symlink_metadata(&temp)?.is_dir(),
        "guest temp must be a directory"
    );
    let temp = temp.to_str().context("guest temp path must be UTF-8")?;
    environment.push_str(&format!(
        "SESSION_TMP_DIR={}\n",
        bootstrap::shell_quote(temp)
    ));
    fsutil::atomic_write(&file, &environment)?;
    Ok(())
}

struct EnrollmentCache {
    store: String,
    public_keys: String,
}

impl EnrollmentCache {
    fn read(source: &Path) -> Result<Option<Self>> {
        if !source.join("cache_credentials").is_file() {
            return Ok(None);
        }
        let read = |name: &str| {
            String::from_utf8(fsutil::read_bounded(&source.join(name), 4096)?)
                .map(|value| value.trim().to_owned())
                .context("enrollment cache settings must be UTF-8")
        };
        let store = read("cache_store")?;
        let public_keys = read("cache_public_keys")?;
        ensure!(
            store.starts_with("s3://"),
            "expected an S3 enrollment cache"
        );
        ensure!(
            !public_keys.is_empty(),
            "enrollment cache signing keys are missing"
        );
        Ok(Some(Self { store, public_keys }))
    }

    fn copy(&self, runtime: &Path, user: &str, generation: &str) -> Result<()> {
        session(
            runtime,
            &[
                "env",
                &format!(
                    "AWS_SHARED_CREDENTIALS_FILE=/home/{user}/.config/nixpp-enrollment/cache_credentials"
                ),
                "nix",
                "--option",
                "trusted-public-keys",
                &self.public_keys,
                "--option",
                "require-sigs",
                "true",
                "copy",
                "--from",
                &self.store,
                generation,
            ],
        )?;
        Ok(())
    }
}

fn install_credentials(home: &Path, source: &Path) -> Result<()> {
    for (input, target, required) in [
        ("id_ed25519", ".ssh/id_ed25519", true),
        ("id_ed25519.pub", ".ssh/id_ed25519.pub", true),
        ("ssh_config", ".config/nixpp-enrollment/ssh_config", true),
        ("known_hosts", ".config/nixpp-enrollment/known_hosts", true),
        ("age_key", ".config/sops/age/keys.txt", false),
        (
            "cache_credentials",
            ".config/nixpp-enrollment/cache_credentials",
            false,
        ),
    ] {
        let source = source.join(input);
        if !required && !source.try_exists()? {
            continue;
        }
        let bytes = fsutil::read_bounded(&source, 128 * 1024)
            .with_context(|| format!("cannot read enrollment credential {input}"))?;
        let value = std::str::from_utf8(&bytes).context("enrollment credential must be text")?;
        ensure!(
            !value.trim().is_empty(),
            "empty enrollment credential {input}"
        );
        let target = home.join(target);
        let parent = target.parent().context("invalid credential destination")?;
        DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(parent)?;
        fsutil::atomic_write(&target, value)?;
    }
    Ok(())
}

fn activate(
    runtime: &Path,
    user: &str,
    build_host: &str,
    target: &str,
    cache: Option<&EnrollmentCache>,
) -> Result<()> {
    let mut runner = SessionRunner::new();
    if runtime.join("system-pending.json").exists() {
        let status = controller::recover(runtime, &mut runner)?;
        ensure!(status == 0, "enrollment recovery failed ({status})");
    }
    eprintln!("Building the guest configuration through Nix…");
    // Keep private flake access on the initial worker. OpenSSH passes a
    // command string to the remote shell, so quote the validated target.
    let target = target.replace('\'', "'\"'\"'");
    let command = format!("nix build --no-link --print-out-paths -- '{target}'");
    let ssh_config = format!("/home/{user}/.config/nixpp-enrollment/ssh_config");
    let output = session(
        runtime,
        &[
            "ssh",
            "-F",
            &ssh_config,
            "-oBatchMode=yes",
            build_host,
            &command,
        ],
    )?;
    let generation = std::str::from_utf8(&output.stdout)?.trim();
    ensure!(
        store::is_store_root(generation),
        "Nix returned an invalid generation"
    );
    let copied_from_cache = cache.is_some_and(|cache| {
        eprintln!("Checking the signed enrollment cache…");
        match cache.copy(runtime, user, generation) {
            Ok(()) => true,
            Err(_) => {
                eprintln!("Could not use the signed cache. Copying from the pinned worker.");
                false
            }
        }
    });
    if !copied_from_cache {
        // This is the same pinned worker that returned the verified store path.
        // Its disposable store does not sign locally built outputs.
        let store = format!("ssh://{build_host}");
        session(
            runtime,
            &[
                "env",
                &format!("NIX_SSHOPTS=-F {ssh_config}"),
                "nix",
                "copy",
                "--no-check-sigs",
                "--from",
                &store,
                generation,
            ],
        )?;
    }
    let candidate = generation
        .strip_prefix("/nix/store/")
        .context("invalid candidate path")?;
    if !runtime.join("system-candidates").join(candidate).is_dir() {
        session(runtime, &["nixpp", "prepare", generation])?;
    }
    let data = controller::candidate_manifest(runtime, candidate)?;
    let home = data.home_manager;
    let has_state = runtime.join("system-state.json").is_file();
    if !has_state {
        eprintln!("Activating the initial Home Manager generation…");
        session(
            runtime,
            &[
                "bash",
                "-c",
                r#"set -eu
if [ ! -e "$HOME/.nix-profile" ]; then
  nix profile add "$1/home-path"
fi
exec "$1/activate""#,
                "nixpp",
                &home,
            ],
        )?;
    }
    let status = controller::switch(
        runtime,
        candidate,
        (!has_state).then_some(home.as_str()),
        &mut runner,
        None,
    )?;
    ensure!(status == 0, "system activation checks failed ({status})");
    Ok(())
}

fn session(runtime: &Path, args: &[impl AsRef<std::ffi::OsStr>]) -> Result<Output> {
    let output = Command::new(runtime.join("session.sh"))
        .args(["--legacy", "--"])
        .args(args)
        .stdin(Stdio::inherit())
        .stderr(Stdio::inherit())
        .output()
        .context("unable to start the enrollment guest")?;
    ensure!(
        output.status.success(),
        "enrollment guest command failed ({})",
        output.status
    );
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn credentials_install_with_private_permissions_and_support_retry() {
        let fixture = tempfile::tempdir().unwrap();
        let input = fixture.path().join("input");
        let home = fixture.path().join("home");
        fs::create_dir(&input).unwrap();
        for name in ["id_ed25519", "id_ed25519.pub", "ssh_config", "known_hosts"] {
            fs::write(input.join(name), format!("fixture for {name}\n")).unwrap();
        }
        install_credentials(&home, &input).unwrap();
        assert!(!home.join(".config/sops/age/keys.txt").exists());
        fs::write(input.join("age_key"), "fixture age key\n").unwrap();
        install_credentials(&home, &input).unwrap();
        for name in [
            ".ssh/id_ed25519",
            ".config/nixpp-enrollment/ssh_config",
            ".config/sops/age/keys.txt",
        ] {
            let path = home.join(name);
            assert_eq!(
                fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
            assert!(fs::read_to_string(path).unwrap().starts_with("fixture"));
        }
    }
}

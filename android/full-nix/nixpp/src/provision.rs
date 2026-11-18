//! First-run handoff from a signed TermuxPP bootstrap to the isolated runtime.
//!
//! Every input (nixpp, the launcher, the seed and the manifest) comes from the
//! signed TermuxPP bundle; nothing is fetched from third parties.

use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::Read;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

use crate::bootstrap;

pub struct Inputs<'a> {
    pub seed: Option<&'a Path>,
    pub manifest: Option<&'a Path>,
    pub certificate: Option<&'a Path>,
    pub bootstrap_dir: Option<&'a Path>,
    pub user: &'a str,
}

pub fn default_runtime(home: &Path) -> Result<PathBuf> {
    ensure!(home.is_absolute(), "HOME must be an absolute path");
    Ok(home.join(".local/share/termuxpp-nix"))
}

fn prefix(executable: &Path) -> Result<&Path> {
    executable
        .parent()
        .and_then(Path::parent)
        .context("cannot determine the native prefix")
}

pub fn init(runtime: &Path, inputs: Inputs<'_>) -> Result<()> {
    bootstrap::check_platform()?;
    ensure!(
        !runtime.join("root").exists(),
        "runtime already exists; use nixpp init --resume for an interrupted package import"
    );
    let executable = fs::canonicalize(std::env::current_exe()?)?;
    let prefix = prefix(&executable)?;
    let seed = inputs
        .bootstrap_dir
        .map(Path::to_path_buf)
        .unwrap_or_else(|| prefix.join("share/nixpp"));
    let manifest = inputs
        .manifest
        .map(Path::to_path_buf)
        .unwrap_or_else(|| seed.join("manifest.json"));
    let certificate = inputs
        .certificate
        .map(Path::to_path_buf)
        .unwrap_or_else(|| prefix.join("etc/tls/cert.pem"));
    ensure!(
        manifest.is_file(),
        "pinned manifest is missing: {}; supply --manifest or install a provisioned bootstrap",
        manifest.display()
    );
    ensure!(
        certificate.is_file(),
        "native CA bundle is missing: {}",
        certificate.display()
    );
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(runtime)?;
    stage_launcher(runtime, &seed.join("launcher"))?;
    // The seed ships in the same signed bundle as this executable, and its
    // hash is compiled in; nothing is downloaded.
    let seed_zip = inputs
        .seed
        .map(Path::to_path_buf)
        .unwrap_or_else(|| seed.join(bootstrap::BOOTSTRAP_NAME));
    ensure!(
        seed_zip.is_file(),
        "bootstrap seed is missing: {}; supply --bootstrap or install a provisioned bootstrap",
        seed_zip.display()
    );
    bootstrap::init(runtime, &seed_zip, &manifest, &certificate, inputs.user)
}

fn stage_launcher(runtime: &Path, source: &Path) -> Result<()> {
    let target = runtime.join("launcher");
    if fs::symlink_metadata(&target).is_ok() {
        ensure!(
            fs::symlink_metadata(&target)?.file_type().is_file(),
            "runtime launcher must be a regular file"
        );
        if source.is_file() {
            ensure!(
                digest(&target)? == digest(source)?,
                "runtime launcher differs from the bundled launcher; refusing to replace it"
            );
        }
        return Ok(());
    }
    ensure!(
        source.is_file(),
        "bundled launcher is missing: {}; stage a trusted launcher or supply --bootstrap-dir",
        source.display()
    );
    let mut input = File::open(source)?;
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o700)
        .open(&target)?;
    let copied = std::io::copy(&mut input, &mut output);
    if let Err(error) = copied.and_then(|_| output.sync_all()) {
        drop(output);
        let _ = fs::remove_file(&target);
        return Err(error.into());
    }
    Ok(())
}

fn digest(path: &Path) -> Result<String> {
    let mut file = File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0; 65536];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
    }
    Ok(format!("{:x}", hash.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn runtime_is_separate_from_native_prefix() {
        assert_eq!(
            default_runtime(Path::new("/native/home")).unwrap(),
            Path::new("/native/home/.local/share/termuxpp-nix")
        );
        assert!(default_runtime(Path::new("relative")).is_err());
    }

    #[test]
    fn launcher_is_staged_without_overwriting_existing_files() {
        let dir = tempdir().unwrap();
        let runtime = dir.path().join("runtime");
        fs::create_dir(&runtime).unwrap();
        let source = dir.path().join("launcher");
        fs::write(&source, b"trusted launcher").unwrap();
        stage_launcher(&runtime, &source).unwrap();
        stage_launcher(&runtime, &source).unwrap();
        fs::write(&source, b"different launcher").unwrap();
        assert!(stage_launcher(&runtime, &source).is_err());
        assert_eq!(
            fs::read(runtime.join("launcher")).unwrap(),
            b"trusted launcher"
        );
    }

    #[test]
    fn existing_legacy_launcher_does_not_require_bundled_assets() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("launcher"), b"legacy").unwrap();
        stage_launcher(dir.path(), &dir.path().join("missing")).unwrap();
    }

    #[test]
    fn symlink_launcher_is_rejected() {
        let dir = tempdir().unwrap();
        let source = dir.path().join("source");
        fs::write(&source, b"launcher").unwrap();
        std::os::unix::fs::symlink(&source, dir.path().join("launcher")).unwrap();
        assert!(stage_launcher(dir.path(), &source).is_err());
    }
}

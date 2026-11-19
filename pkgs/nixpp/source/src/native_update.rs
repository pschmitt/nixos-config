//! Install the native nixpp that the selected generation ships.
//!
//! The native executable came only with the APK's bootstrap, so existing
//! installs never received a newer one. A generation now carries it as
//! `native/nixpp`; after a switch the daemon installs it when it differs from
//! its own executable and restarts through the start script.

use anyhow::{Context, Result};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

/// The native nixpp of the selected generation, when it differs from
/// `current`. `checked` remembers the generation already looked at, so the
/// executables are hashed once per switch rather than on every call.
pub(crate) fn pending(runtime: &Path, current: &Path, checked: &mut Option<String>) -> Option<PathBuf> {
    let name = selected(runtime)?;
    if checked.as_deref() == Some(name.as_str()) {
        return None;
    }
    *checked = Some(name.clone());
    let source = shipped(runtime, &name)?;
    (digest(&source).ok()? != digest(current).ok()?).then_some(source)
}

/// Replace `runtime/nixpp` and, when present, `$PREFIX/bin/nixpp` with
/// `source`. Running processes keep their open executable.
pub(crate) fn install(runtime: &Path, source: &Path, prefix: Option<&Path>) -> Result<()> {
    crate::bootstrap::stage_executable_from(runtime, source)?;
    if let Some(prefix) = prefix {
        let bin = prefix.join("bin");
        if bin.join("nixpp").is_file() {
            crate::bootstrap::replace_with(&bin, "nixpp", 0o755, |file| {
                std::io::copy(&mut fs::File::open(source)?, file).map(|_| ())
            })
            .with_context(|| format!("failed to update {}", bin.join("nixpp").display()))?;
        }
    }
    Ok(())
}

fn selected(runtime: &Path) -> Option<String> {
    let text = fs::read_to_string(runtime.join("current-system")).ok()?;
    let name = text.strip_suffix('\n')?;
    crate::store::is_candidate_name(name).then(|| name.to_owned())
}

/// `native/nixpp` of generation `name` as a native path. The link targets the
/// guest's /nix/store, which lives under `runtime/root`.
fn shipped(runtime: &Path, name: &str) -> Option<PathBuf> {
    let link = runtime.join("root/nix/store").join(name).join("native/nixpp");
    let target = fs::read_link(&link).ok()?;
    let source = match target.strip_prefix("/") {
        Ok(relative) => runtime.join("root").join(relative),
        Err(_) => link.parent()?.join(target),
    };
    source.is_file().then_some(source)
}

fn digest(path: &Path) -> std::io::Result<[u8; 32]> {
    let mut hasher = Sha256::new();
    std::io::copy(&mut fs::File::open(path)?, &mut hasher)?;
    Ok(hasher.finalize().into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    fn fixture(content: &[u8]) -> (tempfile::TempDir, PathBuf, String) {
        let directory = tempfile::tempdir().unwrap();
        let runtime = directory.path().join("runtime");
        let name = format!("{}-termuxpp-system-test", "a".repeat(32));
        let package = format!("{}-nixpp-runtime-termux-0.5.0", "b".repeat(32));
        let store = runtime.join("root/nix/store");
        fs::create_dir_all(store.join(&name).join("native")).unwrap();
        fs::create_dir_all(store.join(&package).join("bin")).unwrap();
        fs::write(store.join(&package).join("bin/nixpp"), content).unwrap();
        symlink(
            format!("/nix/store/{package}/bin/nixpp"),
            store.join(&name).join("native/nixpp"),
        )
        .unwrap();
        fs::write(runtime.join("current-system"), format!("{name}\n")).unwrap();
        (directory, runtime, name)
    }

    #[test]
    fn same_executable_is_no_update() {
        let (directory, runtime, _) = fixture(b"same");
        let current = directory.path().join("current");
        fs::write(&current, b"same").unwrap();
        let mut checked = None;
        assert_eq!(pending(&runtime, &current, &mut checked), None);
    }

    #[test]
    fn a_different_executable_is_installed_once_per_generation() {
        let (directory, runtime, name) = fixture(b"new");
        let current = directory.path().join("current");
        fs::write(&current, b"old").unwrap();
        let mut checked = None;
        let source = pending(&runtime, &current, &mut checked).unwrap();
        assert!(source.starts_with(runtime.join("root/nix/store")));
        assert_eq!(checked.as_deref(), Some(name.as_str()));
        assert_eq!(pending(&runtime, &current, &mut checked), None);

        let prefix = directory.path().join("usr");
        fs::create_dir_all(prefix.join("bin")).unwrap();
        fs::write(prefix.join("bin/nixpp"), b"old").unwrap();
        install(&runtime, &source, Some(&prefix)).unwrap();
        assert_eq!(fs::read(runtime.join("nixpp")).unwrap(), b"new");
        assert_eq!(fs::read(prefix.join("bin/nixpp")).unwrap(), b"new");
    }

    #[test]
    fn a_generation_without_native_nixpp_is_no_update() {
        let (directory, runtime, name) = fixture(b"new");
        fs::remove_file(runtime.join("root/nix/store").join(&name).join("native/nixpp")).unwrap();
        let current = directory.path().join("current");
        fs::write(&current, b"old").unwrap();
        assert_eq!(pending(&runtime, &current, &mut None), None);
    }
}

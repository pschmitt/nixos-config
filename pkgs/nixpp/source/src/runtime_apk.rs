//! Refresh processes whose Android package was replaced.

use crate::error::Result;
use crate::fsutil::read_bounded;
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

pub(crate) fn replaced(runtime: &Path) -> bool {
    let Some(loaded) = std::env::var_os("TERMUX_PKG_REDIRECT_SO") else {
        return false;
    };
    marker_differs(runtime, &loaded)
}

fn marker_differs(runtime: &Path, loaded: &OsStr) -> bool {
    let Ok(record) = read_bounded(&runtime.join("apk-library"), 4096) else {
        return false;
    };
    let Some(current) = record.strip_suffix(b"\n") else {
        return false;
    };
    if current == loaded.as_bytes() || !current.starts_with(b"/") {
        return false;
    }
    // Ignore a record left behind when a different APK has already replaced it.
    Path::new(OsStr::from_bytes(current)).is_file()
}

pub(crate) fn restart(runtime: &Path, args: &[&str]) -> Result<()> {
    Err(Command::new("/system/bin/sh")
        .arg(runtime.join("start-system-control.sh"))
        .args(args)
        .env_remove("LD_PRELOAD")
        .env_remove("LD_LIBRARY_PATH")
        .env_remove("TERMUX_PKG_REDIRECT_SO")
        .exec()
        .into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn reloads_only_for_an_installed_replacement() {
        let runtime = tempfile::tempdir().unwrap();
        let current = runtime.path().join("current.so");
        let loaded = runtime.path().join("loaded.so");
        let marker = runtime.path().join("apk-library");

        assert!(!marker_differs(runtime.path(), loaded.as_os_str()));
        fs::write(&marker, format!("{}\n", current.display())).unwrap();
        assert!(!marker_differs(runtime.path(), loaded.as_os_str()));

        fs::write(&current, []).unwrap();
        assert!(marker_differs(runtime.path(), loaded.as_os_str()));
        assert!(!marker_differs(runtime.path(), current.as_os_str()));
    }
}

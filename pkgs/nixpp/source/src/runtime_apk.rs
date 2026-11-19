//! Refresh processes whose Android package was replaced.

use crate::error::Result;
use crate::fsutil::read_bounded;
use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::OsStringExt;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

pub(crate) fn replaced(runtime: &Path) -> bool {
    let Some(loaded) = std::env::var_os("TERMUX_PKG_REDIRECT_SO") else {
        return false;
    };
    marker_differs(runtime, &loaded)
}

pub(crate) fn marker(runtime: &Path) -> Option<OsString> {
    let mut record = read_bounded(&runtime.join("apk-library"), 4096).ok()?;
    (record.pop() == Some(b'\n') && record.starts_with(b"/")).then(|| OsString::from_vec(record))
}

fn marker_differs(runtime: &Path, loaded: &OsStr) -> bool {
    // Ignore a record left behind when a different APK has already replaced it.
    marker(runtime).is_some_and(|current| {
        current != loaded && Path::new(&current).is_file() && !same_file(&current, loaded)
    })
}

// The app and the start scripts may spell one file differently (/data/data
// versus /data/user/0); only a different file means a replaced APK.
fn same_file(a: &OsStr, b: &OsStr) -> bool {
    use std::os::unix::fs::MetadataExt;
    match (std::fs::metadata(a), std::fs::metadata(b)) {
        (Ok(a), Ok(b)) => a.dev() == b.dev() && a.ino() == b.ino(),
        _ => false,
    }
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

    #[test]
    fn another_spelling_of_the_same_library_is_not_a_replacement() {
        let runtime = tempfile::tempdir().unwrap();
        let library = runtime.path().join("lib.so");
        fs::write(&library, []).unwrap();
        let alias = runtime.path().join("alias");
        std::os::unix::fs::symlink(runtime.path(), &alias).unwrap();
        fs::write(runtime.path().join("apk-library"), format!("{}\n", library.display())).unwrap();
        assert!(!marker_differs(runtime.path(), alias.join("lib.so").as_os_str()));
    }

    /// App and runtime update independently. Each combination must restart
    /// a process at most once and then settle.
    #[test]
    fn update_transitions_settle_after_at_most_one_restart() {
        let runtime = tempfile::tempdir().unwrap();
        let apk_v1 = runtime.path().join("apk-v1/libtermux-pkg-redirect.so");
        let apk_v2 = runtime.path().join("apk-v2/libtermux-pkg-redirect.so");
        let stable = runtime.path().join("files/lib/libtermux-pkg-redirect.so");
        for library in [&apk_v2, &stable] {
            fs::create_dir_all(library.parent().unwrap()).unwrap();
            fs::write(library, []).unwrap();
        }
        let marker = runtime.path().join("apk-library");
        let record = |path: &Path| fs::write(&marker, format!("{}\n", path.display())).unwrap();

        // New APK, old start script: the app keeps recording the APK path. A
        // process of the removed APK restarts once onto the new one.
        record(&apk_v2);
        assert!(marker_differs(runtime.path(), apk_v1.as_os_str()));
        assert!(!marker_differs(runtime.path(), apk_v2.as_os_str()));

        // New APK, new start script: the stable copy is recorded. A process
        // still on an APK path restarts once; on the stable copy it settles.
        record(&stable);
        assert!(marker_differs(runtime.path(), apk_v2.as_os_str()));
        assert!(!marker_differs(runtime.path(), stable.as_os_str()));

        // Another spelling of the stable copy (/data/user/0 for /data/data)
        // must not count as a replacement, or the process restarts forever.
        let alias = runtime.path().join("alias");
        std::os::unix::fs::symlink(runtime.path(), &alias).unwrap();
        let spelled = alias.join("files/lib/libtermux-pkg-redirect.so");
        assert!(!marker_differs(runtime.path(), spelled.as_os_str()));

        // Older app after a newer one: the recorded APK path is gone, so the
        // stale record cannot force a restart loop.
        record(&apk_v1);
        assert!(!marker_differs(runtime.path(), stable.as_os_str()));
    }
}

//! Native launcher for the persistent guest runit supervisor.
//!
//! A guest launcher tears down its process namespace when a one-shot command
//! returns. Keep the service root in a separate, locked native process so
//! ordinary `nixpp enter -- svc ...` calls only control an existing runit tree.

use crate::error::{Error, Result};
use crate::fsutil::{FileLock, read_bounded, regular_file_size};
use crate::store::{is_candidate_name, is_store_root};
use std::fs::{self, OpenOptions};
use std::io;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

const SERVICE_STATE: &str = "service-state";
const MANAGER_LOCK: &str = "manager.lock";
const SUPERVISOR_LOG: &str = "supervisor.log";
const SERVICE_COMMAND: &str = "/run/current-system/sw/bin/svc";

/// Start the native manager when a Nix system is selected.
///
/// The manager holds its own nonblocking lock for its lifetime. It is safe to
/// call this for every native guest login; extra helper processes exit as soon
/// as they find the lock held.
pub fn ensure_started(runtime: &Path) -> Result<()> {
    if selected_candidate(runtime)?.is_none() {
        return Ok(());
    }
    let executable = crate::provision::running_executable()
        .map_err(|error| Error::invalid(format!("cannot locate native nixpp: {error}")))?;
    let mut command = Command::new(executable);
    command
        .arg("--runtime")
        .arg(runtime)
        .arg("__service-supervisor")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0);
    command.spawn()?;
    Ok(())
}

/// Run the native manager until its process is stopped.
pub fn run(runtime: &Path) -> Result<()> {
    let state = runtime.join(SERVICE_STATE);
    fs::create_dir_all(&state)?;
    let Some(_lock) = FileLock::try_acquire(&state.join(MANAGER_LOCK))? else {
        return Ok(());
    };
    let log = OpenOptions::new()
        .append(true)
        .create(true)
        .custom_flags(libc::O_NOFOLLOW)
        .mode(0o600)
        .open(state.join(SUPERVISOR_LOG))?;

    loop {
        let Some((name, _generation)) = selected_candidate(runtime)? else {
            sleep(Duration::from_secs(1));
            continue;
        };
        let mut child = Command::new(runtime.join("session.sh"))
            .arg("--system")
            .arg(&name)
            .arg("--")
            .arg(SERVICE_COMMAND)
            .arg("supervise")
            .stdin(Stdio::null())
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log.try_clone()?))
            .spawn()?;
        let status = child.wait()?;

        // 76 means another guest root still owns the guest-side lock. This can
        // happen if the native manager died but its child is still retiring.
        if status.code() == Some(76) {
            sleep(Duration::from_secs(1));
            continue;
        }

        if selected_candidate(runtime)?.is_some_and(|(current, _)| current == name) {
            // Avoid a hot loop if the guest launcher or runsv exits abnormally.
            sleep(Duration::from_secs(1));
        }
    }
}

fn selected_candidate(runtime: &Path) -> Result<Option<(String, String)>> {
    let selector = runtime.join("current-system");
    if regular_file_size(&selector).is_none() {
        if fs::symlink_metadata(&selector)
            .is_err_and(|error| error.kind() == io::ErrorKind::NotFound)
        {
            return Ok(None);
        }
        return Err(Error::invalid("system selector is not a regular file"));
    }
    let selector_text = String::from_utf8(read_bounded(&selector, 4096)?)
        .map_err(|_| Error::invalid("system selector is not UTF-8"))?;
    let name = selector_text
        .strip_suffix('\n')
        .filter(|name| !name.contains('\n') && is_candidate_name(name))
        .ok_or_else(|| Error::invalid("invalid system selector"))?;
    let candidate = runtime.join("system-candidates").join(name);
    if fs::symlink_metadata(runtime.join("system-candidates"))?
        .file_type()
        .is_symlink()
        || fs::symlink_metadata(&candidate)?.file_type().is_symlink()
    {
        return Err(Error::invalid("selected system candidate is a symlink"));
    }
    let generation_file = candidate.join("generation");
    if regular_file_size(&generation_file).is_none() {
        return Err(Error::invalid("selected system generation is unavailable"));
    }
    let generation_text = String::from_utf8(read_bounded(&generation_file, 4096)?)
        .map_err(|_| Error::invalid("system generation is not UTF-8"))?;
    let generation = generation_text
        .strip_suffix('\n')
        .filter(|path| is_store_root(path) && path.strip_prefix("/nix/store/") == Some(name))
        .ok_or_else(|| Error::invalid("invalid selected system generation"))?;
    Ok(Some((name.to_owned(), generation.to_owned())))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    use std::path::PathBuf;

    fn fixture() -> (tempfile::TempDir, PathBuf, String) {
        let directory = tempfile::tempdir().unwrap();
        let runtime = directory.path().join("runtime");
        let name = format!("{}-termuxpp-system-test", "a".repeat(32));
        let candidate = runtime.join("system-candidates").join(&name);
        fs::create_dir_all(&candidate).unwrap();
        fs::write(candidate.join("generation"), format!("/nix/store/{name}\n")).unwrap();
        fs::write(runtime.join("current-system"), format!("{name}\n")).unwrap();
        (directory, runtime, name)
    }

    #[test]
    fn reads_the_selected_generation() {
        let (_directory, runtime, name) = fixture();
        assert_eq!(
            selected_candidate(&runtime).unwrap(),
            Some((name.clone(), format!("/nix/store/{name}")))
        );
    }

    #[test]
    fn rejects_a_symlinked_candidate_tree() {
        let (_directory, runtime, name) = fixture();
        let candidate = runtime.join("system-candidates").join(&name);
        let target = runtime.join("candidate-target");
        fs::rename(&candidate, &target).unwrap();
        symlink(&target, &candidate).unwrap();
        assert!(selected_candidate(&runtime).is_err());
    }

    #[test]
    fn missing_selector_means_no_active_services() {
        let (_directory, runtime, _) = fixture();
        fs::remove_file(runtime.join("current-system")).unwrap();
        assert_eq!(selected_candidate(&runtime).unwrap(), None);
    }
}

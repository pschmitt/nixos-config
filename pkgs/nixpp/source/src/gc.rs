//! Prune system generations without racing a launch or activation.

use crate::controller::{self, CONTROL_LOCK};
use crate::error::{Error, Result};
use crate::fsutil::{FileLock, atomic_write, read_bounded};
use crate::guest::GCROOTS;
use crate::store::is_candidate_name;
use serde::Serialize;
use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::SystemTime;

const HISTORY: &str = "system-pruned";
const LEASE: &str = ".session-lock";
const RETIRED: &str = ".retired-";

#[derive(Debug, Serialize)]
pub struct Report {
    pub dry_run: bool,
    pub deferred: Option<&'static str>,
    pub prune: Vec<String>,
    pub retained: Vec<String>,
}

fn candidate(runtime: &Path, name: &str) -> PathBuf {
    runtime.join("system-candidates").join(name)
}

fn check_directory(directory: &Path) -> Result<()> {
    match fs::symlink_metadata(directory) {
        Ok(metadata) if !metadata.is_dir() => Err(Error::invalid(
            "generation data directory is not a real directory",
        )),
        Ok(_) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn recorded_time(runtime: &Path, name: &str) -> Result<Option<SystemTime>> {
    let path = runtime.join(HISTORY).join(name);
    match fs::symlink_metadata(&path) {
        Ok(metadata) if metadata.is_file() => {
            Ok(Some(serde_json::from_slice(&read_bounded(&path, 4096)?)?))
        }
        Ok(_) => Err(Error::invalid("invalid pruned generation record")),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn generation_time(runtime: &Path, name: &str) -> Result<Option<SystemTime>> {
    check_directory(&runtime.join(HISTORY))?;
    if let Some(time) = recorded_time(runtime, name)? {
        return Ok(Some(time));
    }
    let path = candidate(runtime, name).join("generation");
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_file() => Ok(Some(metadata.modified()?)),
        Ok(_) => Err(Error::invalid("invalid generation record")),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

/// A pruned pin is still comparable to the active generation.
pub fn pin_is_obsolete(runtime: &Path, pin: &str) -> Result<bool> {
    if !is_candidate_name(pin) {
        return Err(Error::invalid("invalid cache pin generation"));
    }
    let _lock = FileLock::acquire(&runtime.join(CONTROL_LOCK))?;
    let generations = controller::generations(runtime)?;
    let Some(active) = generations.iter().find(|item| item.current) else {
        return Ok(false);
    };
    let Some(active_time) = generation_time(runtime, &active.generation)? else {
        return Err(Error::invalid("active generation record is missing"));
    };
    Ok(generation_time(runtime, pin)?
        .is_some_and(|time| (time, pin) <= (active_time, active.generation.as_str())))
}

fn inode(metadata: &fs::Metadata) -> (u64, u64) {
    (metadata.dev(), metadata.ino())
}

fn process_parent(proc_entry: &Path) -> Option<u32> {
    let record = fs::read_to_string(proc_entry.join("stat")).ok()?;
    record
        .rsplit_once(") ")?
        .1
        .split_whitespace()
        .nth(1)?
        .parse()
        .ok()
}

/// Sessions started by an earlier launcher script do not have leases. Defer
/// cleanup if a top-level launcher for this runtime cannot prove its lease.
fn has_unleased_sessions(runtime: &Path, generations: &[controller::Generation]) -> Result<bool> {
    let script = read_bounded(&runtime.join("session.sh"), 64 * 1024)?;
    if script != include_bytes!("assets/session.sh") {
        return Ok(true);
    }
    let launcher = inode(&fs::metadata(runtime.join("launcher"))?);
    let proc = Path::new("/android/proc");
    let leases: HashSet<_> = generations
        .iter()
        .filter_map(|generation| {
            fs::symlink_metadata(candidate(runtime, &generation.generation).join(LEASE))
                .ok()
                .filter(fs::Metadata::is_file)
                .map(|metadata| inode(&metadata))
        })
        .collect();
    // SAFETY: geteuid has no preconditions and cannot fail.
    let uid = unsafe { libc::geteuid() };
    for entry in fs::read_dir(proc)? {
        let path = entry?.path();
        if path
            .file_name()
            .and_then(|name| name.to_str())
            .and_then(|name| name.parse::<u32>().ok())
            .is_none()
        {
            continue;
        }
        let Ok(owner) = fs::metadata(&path) else {
            continue;
        };
        if owner.uid() != uid {
            continue;
        }
        match fs::metadata(path.join("exe")) {
            Ok(executable) if inode(&executable) == launcher => {}
            Ok(_) => {
                if fs::read_link(path.join("exe"))
                    .is_ok_and(|exe| exe.ends_with("launcher (deleted)"))
                {
                    return Ok(true);
                }
                continue;
            }
            Err(_) => {
                if fs::read_to_string(path.join("comm")).is_ok_and(|name| name.trim() == "launcher")
                {
                    return Ok(true);
                }
                continue;
            }
        }
        if fs::metadata(path.join("fd/8")).is_ok_and(|fd| leases.contains(&inode(&fd))) {
            continue;
        }
        if let Some(parent) = process_parent(&path)
            && fs::metadata(proc.join(parent.to_string()).join("exe"))
                .is_ok_and(|exe| inode(&exe) == launcher)
        {
            // An inner launcher is protected by its top-level launcher.
            continue;
        }
        if path.exists() {
            return Ok(true);
        }
    }
    Ok(false)
}

fn retired_path(runtime: &Path, name: &str) -> PathBuf {
    candidate(runtime, &format!("{RETIRED}{name}"))
}

fn finish_retired(runtime: &Path, name: &str) -> Result<()> {
    let path = retired_path(runtime, name);
    if !fs::symlink_metadata(&path)?.is_dir() || recorded_time(runtime, name)?.is_none() {
        return Err(Error::invalid("invalid interrupted generation prune"));
    }
    let root = runtime.join(GCROOTS).join(name);
    match fs::read_link(&root) {
        Ok(target) if target == Path::new("/nix/store").join(name) => fs::remove_file(root)?,
        Ok(_) => {
            return Err(Error::invalid(
                "generation GC root points outside its store path",
            ));
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    fs::remove_dir_all(path)?;
    Ok(())
}

fn remember(runtime: &Path, name: &str) -> Result<()> {
    let directory = runtime.join(HISTORY);
    fs::create_dir_all(&directory)?;
    let path = directory.join(name);
    if recorded_time(runtime, name)?.is_none() {
        let time = fs::metadata(candidate(runtime, name).join("generation"))?.modified()?;
        atomic_write(&path, &serde_json::to_string(&time)?)?;
    }
    Ok(())
}

fn retain(generations: &[controller::Generation], keep: usize) -> HashSet<&str> {
    let mut protected: HashSet<_> = generations
        .iter()
        .filter(|entry| entry.current || entry.previous)
        .map(|entry| entry.generation.as_str())
        .collect();
    for entry in generations.iter().rev() {
        if protected.len() >= keep {
            break;
        }
        protected.insert(&entry.generation);
    }
    protected
}

pub fn run(runtime: &Path, keep: usize, dry_run: bool) -> Result<Report> {
    run_with(runtime, keep, dry_run, has_unleased_sessions, || {
        let status = Command::new("nix")
            .args(["store", "gc"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .status()?;
        if !status.success() {
            return Err(Error::invalid(format!(
                "Nix store garbage collection failed: {status}"
            )));
        }
        Ok(())
    })
}

fn run_with(
    runtime: &Path,
    keep: usize,
    dry_run: bool,
    unleased_sessions: impl FnOnce(&Path, &[controller::Generation]) -> Result<bool>,
    collect: impl FnOnce() -> Result<()>,
) -> Result<Report> {
    let runtime = fs::canonicalize(runtime)?;
    let _lock = FileLock::acquire(&runtime.join(CONTROL_LOCK))?;
    check_directory(&runtime.join(HISTORY))?;
    check_directory(&runtime.join(GCROOTS))?;
    let generations = controller::generations(&runtime)?;
    let protected = retain(&generations, keep);
    let mut report = Report {
        dry_run,
        deferred: None,
        prune: Vec::new(),
        retained: Vec::new(),
    };
    if controller::pending_exists(&runtime)? {
        report.deferred = Some("an activation is unfinished; recover it first");
    } else if let Some(current) = generations.iter().find(|item| item.current) {
        if read_bounded(&runtime.join("current-system"), 4096)?
            != format!("{}\n", current.generation).as_bytes()
        {
            return Err(Error::invalid("system state and active selector disagree"));
        }
        if unleased_sessions(&runtime, &generations)? {
            report.deferred =
                Some("a session is using the old launcher; reopen the app and SSH sessions");
        }
    } else {
        report.deferred = Some("there is no active managed generation");
    }
    if report.deferred.is_none() && !dry_run {
        for entry in fs::read_dir(runtime.join("system-candidates"))? {
            let entry = entry?;
            let filename = entry.file_name();
            if let Some(name) = filename
                .to_str()
                .and_then(|value| value.strip_prefix(RETIRED))
            {
                if !is_candidate_name(name) || candidate(&runtime, name).exists() {
                    return Err(Error::invalid("invalid retired generation directory"));
                }
                finish_retired(&runtime, name)?;
            }
        }
    }
    for generation in &generations {
        let name = &generation.generation;
        if protected.contains(name.as_str()) || report.deferred.is_some() {
            report.retained.push(name.clone());
            continue;
        }
        let lease = candidate(&runtime, name).join(LEASE);
        if dry_run && !lease.try_exists()? {
            report.prune.push(name.clone());
            continue;
        }
        let Some(_lease) = FileLock::try_acquire(&lease)? else {
            report.retained.push(name.clone());
            continue;
        };
        report.prune.push(name.clone());
        if !dry_run {
            remember(&runtime, name)?;
            fs::rename(candidate(&runtime, name), retired_path(&runtime, name))?;
            finish_retired(&runtime, name)?;
        }
    }
    if !dry_run && report.deferred.is_none() {
        collect()?;
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::Fixture;
    use serde_json::json;
    use std::os::unix::fs::symlink;
    use std::time::{Duration, UNIX_EPOCH};

    fn add_candidate(fixture: &Fixture, letter: char, seconds: u64) -> String {
        let name = format!("{}-termuxpp-system-test", letter.to_string().repeat(32));
        let directory = candidate(&fixture.runtime, &name);
        fs::create_dir_all(&directory).unwrap();
        let record = directory.join("generation");
        fs::write(&record, format!("/nix/store/{name}\n")).unwrap();
        fs::File::open(&record)
            .unwrap()
            .set_modified(UNIX_EPOCH + Duration::from_secs(seconds))
            .unwrap();
        fs::write(
            directory.join("manifest.json"),
            fixture.manifest.to_string(),
        )
        .unwrap();
        let roots = fixture.runtime.join(GCROOTS);
        fs::create_dir_all(&roots).unwrap();
        symlink(Path::new("/nix/store").join(&name), roots.join(&name)).unwrap();
        name
    }

    fn select(fixture: &Fixture, active: &str, previous: &str) {
        fs::write(
            fixture.runtime.join("system-state.json"),
            json!({
                "current": active, "previous": previous,
                "homeManager": fixture.home, "previousHomeManager": fixture.baseline,
            })
            .to_string(),
        )
        .unwrap();
        fs::write(
            fixture.runtime.join("current-system"),
            format!("{active}\n"),
        )
        .unwrap();
    }

    #[test]
    fn retention_counts_the_active_and_rollback_generations() {
        let fixture = Fixture::new();
        let active = add_candidate(&fixture, 'b', 10);
        let previous = add_candidate(&fixture, 'c', 20);
        let old = add_candidate(&fixture, 'd', 30);
        select(&fixture, &active, &previous);
        let generations = controller::generations(&fixture.runtime).unwrap();
        assert_eq!(
            retain(&generations, 1),
            HashSet::from([active.as_str(), previous.as_str()])
        );
        assert_eq!(
            retain(&generations, 3),
            HashSet::from([active.as_str(), previous.as_str(), fixture.name.as_str()])
        );
        assert!(!retain(&generations, 3).contains(old.as_str()));
    }

    #[test]
    fn retired_cleanup_removes_the_root_and_preserves_pin_age() {
        let fixture = Fixture::new();
        let old = add_candidate(&fixture, 'b', 10);
        let active = add_candidate(&fixture, 'c', 20);
        select(&fixture, &active, &fixture.name);
        remember(&fixture.runtime, &old).unwrap();
        fs::rename(
            candidate(&fixture.runtime, &old),
            retired_path(&fixture.runtime, &old),
        )
        .unwrap();
        assert!(pin_is_obsolete(&fixture.runtime, &old).unwrap());
        finish_retired(&fixture.runtime, &old).unwrap();
        assert!(pin_is_obsolete(&fixture.runtime, &old).unwrap());
        assert!(fs::symlink_metadata(fixture.runtime.join(GCROOTS).join(&old)).is_err());
        assert!(!retired_path(&fixture.runtime, &old).exists());
        assert!(!pin_is_obsolete(&fixture.runtime, &fixture.name).unwrap());
        assert!(pin_is_obsolete(&fixture.runtime, "../invalid").is_err());
    }

    #[test]
    fn dry_run_and_prune_keep_leased_generations() {
        let fixture = Fixture::new();
        let old = add_candidate(&fixture, 'b', 10);
        let leased = add_candidate(&fixture, 'c', 15);
        let active = add_candidate(&fixture, 'd', 25);
        select(&fixture, &active, &fixture.name);
        let guard = FileLock::acquire(&candidate(&fixture.runtime, &leased).join(LEASE)).unwrap();
        let summary = run_with(
            &fixture.runtime,
            2,
            true,
            |_, _| Ok(false),
            || panic!("dry-run started Nix store GC"),
        )
        .unwrap();
        assert_eq!(summary.prune, vec![old.clone()]);
        assert!(!candidate(&fixture.runtime, &old).join(LEASE).exists());
        assert!(!fixture.runtime.join(HISTORY).exists());
        let summary = run_with(&fixture.runtime, 2, false, |_, _| Ok(false), || Ok(())).unwrap();
        assert_eq!(summary.prune, vec![old.clone()]);
        assert!(!candidate(&fixture.runtime, &old).exists());
        assert!(candidate(&fixture.runtime, &leased).exists());
        assert!(pin_is_obsolete(&fixture.runtime, &old).unwrap());
        drop(guard);
    }

    #[test]
    fn gc_defers_without_mutating_an_interrupted_activation() {
        let fixture = Fixture::new();
        let active = add_candidate(&fixture, 'b', 30);
        let previous = add_candidate(&fixture, 'c', 25);
        select(&fixture, &active, &previous);
        fs::write(fixture.runtime.join("system-pending.json"), "{}").unwrap();
        let summary = run(&fixture.runtime, 1, false).unwrap();
        assert!(summary.deferred.is_some());
        assert!(summary.prune.is_empty());
        assert!(fixture.candidate.exists());
        assert!(!fixture.runtime.join(HISTORY).exists());
    }
}

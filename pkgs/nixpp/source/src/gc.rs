//! Prune system generations without racing a launch or activation.

use crate::controller::{self, CONTROL_LOCK};
use crate::error::{Error, Result};
use crate::fsutil::{FileLock, atomic_write, read_bounded};
use crate::guest::GCROOTS;
use crate::store::{is_candidate_name, is_store_root};
use serde::{Deserialize, Serialize};
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

#[derive(Deserialize, Serialize)]
struct HistoryRecord {
    prepared: SystemTime,
    home_manager: String,
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

fn read_history(runtime: &Path, name: &str) -> Result<Option<HistoryRecord>> {
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
    if let Some(record) = read_history(runtime, name)? {
        return Ok(Some(record.prepared));
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
    if !fs::symlink_metadata(&path)?.is_dir() || read_history(runtime, name)?.is_none() {
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
    if read_history(runtime, name)?.is_none() {
        let time = fs::metadata(candidate(runtime, name).join("generation"))?.modified()?;
        let candidate = controller::candidate_manifest(runtime, name)?;
        let record = HistoryRecord {
            prepared: time,
            home_manager: candidate.home_manager,
        };
        atomic_write(&path, &serde_json::to_string(&record)?)?;
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
    if !dry_run && inode(&fs::metadata(runtime.join("root/nix"))?) != inode(&fs::metadata("/nix")?)
    {
        return Err(Error::invalid(
            "gc must run inside the guest that owns the selected runtime",
        ));
    }
    run_with(runtime, keep, dry_run, has_unleased_sessions, || {
        prune_home_profiles(runtime)?;
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

/// Select only standard Nix profile links to a retired HM closure. The active
/// profile may have been activated independently of nixpp, so protect it too.
fn obsolete_home_links(profile: &Path, retired: &HashSet<PathBuf>) -> Result<Vec<String>> {
    let Some(directory) = profile.parent() else {
        return Ok(Vec::new());
    };
    if !directory.exists() {
        return Ok(Vec::new());
    }
    let selected = match fs::read_link(profile) {
        Ok(path) => Some(path),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => return Err(error.into()),
    };
    let mut result = Vec::new();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let filename = entry.file_name();
        let Some(number) = filename
            .to_str()
            .and_then(|name| name.strip_prefix("home-manager-"))
            .and_then(|name| name.strip_suffix("-link"))
            .filter(|number| {
                !number.is_empty() && number.bytes().all(|byte| byte.is_ascii_digit())
            })
        else {
            continue;
        };
        if selected.as_deref().and_then(Path::file_name) == Some(filename.as_os_str()) {
            continue;
        }
        if entry.file_type()?.is_symlink() && retired.contains(&fs::read_link(entry.path())?) {
            result.push(number.to_owned());
        }
    }
    result.sort_unstable();
    Ok(result)
}

fn prune_home_profiles(runtime: &Path) -> Result<()> {
    let history = runtime.join(HISTORY);
    if !history.exists() {
        return Ok(());
    }
    let mut protected: HashSet<_> = controller::generations(runtime)?
        .into_iter()
        .map(|generation| generation.home_manager)
        .collect();
    if let Some(state) = controller::read_state(runtime)? {
        protected.extend(state.home_manager);
        protected.extend(state.previous_home_manager);
    }
    let mut retired = HashSet::new();
    for entry in fs::read_dir(history)? {
        let name = entry?.file_name();
        let Some(name) = name.to_str().filter(|name| is_candidate_name(name)) else {
            continue;
        };
        if let Some(record) = read_history(runtime, name)?
            && is_store_root(&record.home_manager)
            && !protected.contains(&record.home_manager)
        {
            retired.insert(PathBuf::from(record.home_manager));
        }
    }
    if retired.is_empty() {
        return Ok(());
    }
    let state_home = std::env::var_os("XDG_STATE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .ok_or_else(|| Error::invalid("home profile GC requires HOME or XDG_STATE_HOME"))?;
    let profile = state_home.join("nix/profiles/home-manager");
    let obsolete = obsolete_home_links(&profile, &retired)?;
    if !obsolete.is_empty() {
        let status = Command::new("nix-env")
            .arg("--profile")
            .arg(profile)
            .arg("--delete-generations")
            .args(obsolete)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .status()?;
        if !status.success() {
            return Err(Error::invalid(format!(
                "Home Manager profile pruning failed: {status}"
            )));
        }
    }
    Ok(())
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
        let summary = run_with(
            &fixture.runtime,
            1,
            false,
            |_, _| panic!("GC inspected sessions during an unfinished activation"),
            || panic!("GC collected during an unfinished activation"),
        )
        .unwrap();
        assert!(summary.deferred.is_some());
        assert!(summary.prune.is_empty());
        assert!(fixture.candidate.exists());
        assert!(!fixture.runtime.join(HISTORY).exists());
    }

    #[test]
    fn home_profile_pruning_keeps_the_active_link_and_unrelated_history() {
        let directory = tempfile::tempdir().unwrap();
        let profile = directory.path().join("home-manager");
        let retired = "/nix/store/retired-home-manager-generation";
        symlink(retired, directory.path().join("home-manager-1-link")).unwrap();
        symlink(retired, directory.path().join("home-manager-2-link")).unwrap();
        symlink(
            "/nix/store/independent-home-manager-generation",
            directory.path().join("home-manager-3-link"),
        )
        .unwrap();
        symlink("home-manager-2-link", &profile).unwrap();
        assert_eq!(
            obsolete_home_links(&profile, &HashSet::from([PathBuf::from(retired)])).unwrap(),
            ["1"]
        );
    }
}

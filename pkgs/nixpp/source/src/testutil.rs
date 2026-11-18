//! Shared fixtures for the unit tests.

use crate::error::{Error, Result};
use crate::runner::Runner;
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;
use tempfile::TempDir;

/// What a scripted command does when it is "run".
#[derive(Debug, Clone, Copy)]
pub enum Outcome {
    Status(i32),
    Interrupted,
    Terminated,
    TimedOut,
}

/// Callback run before each scripted command, with its index and arguments.
pub type Hook = Box<dyn FnMut(usize, &[String]) + Send>;

/// A recording [`Runner`] that never starts a process.
pub struct MockRunner {
    script: VecDeque<Outcome>,
    default: i32,
    pub calls: Vec<(Vec<String>, Duration)>,
    pub hook: Option<Hook>,
}

impl MockRunner {
    /// Always succeeds with `status`.
    pub fn returning(status: i32) -> Self {
        Self {
            script: VecDeque::new(),
            default: status,
            calls: Vec::new(),
            hook: None,
        }
    }

    /// Replays the given statuses, then succeeds.
    pub fn statuses(statuses: &[i32]) -> Self {
        Self::script(
            statuses
                .iter()
                .map(|status| Outcome::Status(*status))
                .collect(),
        )
    }

    pub fn script(script: Vec<Outcome>) -> Self {
        Self {
            script: script.into(),
            default: 0,
            calls: Vec::new(),
            hook: None,
        }
    }

    pub fn with_hook(mut self, hook: impl FnMut(usize, &[String]) + Send + 'static) -> Self {
        self.hook = Some(Box::new(hook));
        self
    }

    /// The final argument of every call, in order.
    pub fn last_arguments(&self) -> Vec<String> {
        self.calls
            .iter()
            .map(|(command, _)| command.last().cloned().unwrap_or_default())
            .collect()
    }

    pub fn command(&self, index: usize) -> &Vec<String> {
        &self.calls[index].0
    }
}

impl Runner for MockRunner {
    fn run(&mut self, command: &[String], timeout: Duration) -> Result<i32> {
        let index = self.calls.len();
        self.calls.push((command.to_vec(), timeout));
        if let Some(hook) = self.hook.as_mut() {
            hook(index, command);
        }
        match self.script.pop_front() {
            None => Ok(self.default),
            Some(Outcome::Status(status)) => Ok(status),
            Some(Outcome::Interrupted) => Err(Error::Interrupted),
            Some(Outcome::Terminated) => Err(Error::Terminated),
            Some(Outcome::TimedOut) => Err(Error::Timeout { seconds: 1 }),
        }
    }
}

/// A runtime directory with one prepared, activatable candidate.
pub struct Fixture {
    _dir: TempDir,
    pub runtime: PathBuf,
    pub name: String,
    pub candidate: PathBuf,
    pub home: String,
    pub baseline: String,
    pub manifest: Value,
}

impl Fixture {
    pub fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let runtime = fs::canonicalize(dir.path()).unwrap();
        let name = format!("{}-termuxpp-system-test", "a".repeat(32));
        let candidate = runtime.join("system-candidates").join(&name);
        fs::create_dir_all(&candidate).unwrap();
        fs::write(candidate.join("generation"), format!("/nix/store/{name}\n")).unwrap();
        let home = format!("/nix/store/{}-home-manager-generation", "b".repeat(32));
        let baseline = format!("/nix/store/{}-home-manager-generation", "c".repeat(32));
        let activate = runtime
            .join("root")
            .join(baseline.trim_start_matches('/'))
            .join("activate");
        fs::create_dir_all(activate.parent().unwrap()).unwrap();
        fs::write(&activate, "").unwrap();
        fs::create_dir_all(runtime.join("root/nix/var/nix/gcroots")).unwrap();
        let fixture = Self {
            _dir: dir,
            runtime,
            name,
            candidate,
            manifest: json!({
                "formatVersion": 1,
                "stateVersion": "1",
                "runtime": "droid-nix",
                "homeManager": home,
                "activationSupported": true,
            }),
            home,
            baseline,
        };
        fixture.save();
        fixture
    }

    /// Persist `self.manifest` as the candidate manifest.
    pub fn save(&self) {
        fs::write(
            self.candidate.join("manifest.json"),
            self.manifest.to_string(),
        )
        .unwrap();
    }

    pub fn path(&self, name: &str) -> PathBuf {
        self.runtime.join(name)
    }

    pub fn exists(&self, name: &str) -> bool {
        fs::symlink_metadata(self.path(name)).is_ok()
    }

    pub fn read(&self, name: &str) -> String {
        fs::read_to_string(self.path(name)).unwrap()
    }

    pub fn read_json(&self, name: &str) -> Value {
        serde_json::from_str(&self.read(name)).unwrap()
    }

    pub fn session_script(&self) -> String {
        self.path("session.sh").to_str().unwrap().to_owned()
    }
}

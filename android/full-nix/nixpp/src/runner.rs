//! Running guest commands in their own session with a budget and cancellation.

use crate::error::{Error, Result};
use std::io;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Child, Command, ExitStatus};
use std::sync::atomic::{AtomicI32, Ordering};
use std::thread::sleep;
use std::time::{Duration, Instant};

/// Time a stopped command gets between SIGTERM and SIGKILL.
pub const DEFAULT_GRACE: Duration = Duration::from_secs(10);

/// Executes one command to completion and reports its status.
///
/// A non-negative status is the exit code, a negative one is minus the signal
/// that killed the command. Budget overruns and cancellation are errors.
pub trait Runner {
    fn run(&mut self, command: &[String], timeout: Duration) -> Result<i32>;
}

/// Last SIGINT or SIGTERM seen while a session was running (0 for none).
static SIGNAL: AtomicI32 = AtomicI32::new(0);

extern "C" fn record_signal(signal: libc::c_int) {
    SIGNAL.store(signal, Ordering::SeqCst);
}

/// Installs recording handlers for SIGINT and SIGTERM and restores the
/// previous dispositions on drop.
struct SignalGuard {
    term: libc::sigaction,
    int: libc::sigaction,
}

impl SignalGuard {
    fn install() -> io::Result<Self> {
        SIGNAL.store(0, Ordering::SeqCst);
        // SAFETY: plain sigaction calls with zero-initialised structures; the
        // handler only stores into an atomic, which is async-signal-safe.
        unsafe {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = record_signal as *const () as usize;
            libc::sigemptyset(&mut action.sa_mask);
            action.sa_flags = 0;
            let mut term: libc::sigaction = std::mem::zeroed();
            let mut int: libc::sigaction = std::mem::zeroed();
            if libc::sigaction(libc::SIGTERM, &action, &mut term) != 0 {
                return Err(io::Error::last_os_error());
            }
            if libc::sigaction(libc::SIGINT, &action, &mut int) != 0 {
                let error = io::Error::last_os_error();
                libc::sigaction(libc::SIGTERM, &term, std::ptr::null_mut());
                return Err(error);
            }
            Ok(Self { term, int })
        }
    }
}

impl Drop for SignalGuard {
    fn drop(&mut self) {
        // SAFETY: restores the dispositions saved by `install`.
        unsafe {
            libc::sigaction(libc::SIGTERM, &self.term, std::ptr::null_mut());
            libc::sigaction(libc::SIGINT, &self.int, std::ptr::null_mut());
        }
    }
}

/// Runs commands as the leader of a new session, so the whole process group
/// can be stopped without touching the controller itself.
#[derive(Debug, Clone, Copy)]
pub struct SessionRunner {
    grace: Duration,
}

impl SessionRunner {
    pub fn new() -> Self {
        Self {
            grace: DEFAULT_GRACE,
        }
    }

    /// Use a custom SIGTERM-to-SIGKILL grace period.
    pub fn with_grace(grace: Duration) -> Self {
        Self { grace }
    }
}

impl Default for SessionRunner {
    fn default() -> Self {
        Self::new()
    }
}

fn status_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => -status.signal().unwrap_or(0),
    }
}

fn spawn(command: &[String]) -> Result<Child> {
    let (program, arguments) = command
        .split_first()
        .ok_or_else(|| Error::invalid("empty command"))?;
    let mut process = Command::new(program);
    process.args(arguments);
    // SAFETY: setsid is async-signal-safe and the closure touches no memory.
    unsafe {
        process.pre_exec(|| {
            if libc::setsid() == -1 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    process
        .spawn()
        .map_err(|error| Error::invalid(format!("cannot start {program}: {error}")))
}

fn wait(child: &mut Child, timeout: Duration) -> Result<i32> {
    let deadline = Instant::now() + timeout;
    let mut delay = Duration::from_millis(5);
    loop {
        if let Some(status) = child.try_wait()? {
            return Ok(status_code(status));
        }
        match SIGNAL.load(Ordering::SeqCst) {
            0 => {}
            libc::SIGINT => return Err(Error::Interrupted),
            _ => return Err(Error::Terminated),
        }
        let now = Instant::now();
        if now >= deadline {
            return Err(Error::Timeout {
                seconds: timeout.as_secs(),
            });
        }
        sleep(delay.min(deadline - now));
        delay = (delay * 2).min(Duration::from_millis(100));
    }
}

fn signal_group(child: &Child, signal: libc::c_int) {
    // SAFETY: the child is its own process-group leader (setsid), so this can
    // only reach the group this runner created; ESRCH is harmless.
    unsafe {
        libc::killpg(child.id() as libc::pid_t, signal);
    }
}

fn stop_group(child: &mut Child, grace: Duration) {
    signal_group(child, libc::SIGTERM);
    let end = Instant::now() + grace;
    while Instant::now() < end {
        if matches!(child.try_wait(), Ok(Some(_))) {
            return;
        }
        sleep(Duration::from_millis(10));
    }
    signal_group(child, libc::SIGKILL);
    let _ = child.wait();
}

impl Runner for SessionRunner {
    fn run(&mut self, command: &[String], timeout: Duration) -> Result<i32> {
        let _guard = SignalGuard::install()?;
        let mut child = spawn(command)?;
        match wait(&mut child, timeout) {
            Ok(status) => Ok(status),
            Err(error) => {
                stop_group(&mut child, self.grace);
                Err(error)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// The signal flag and handlers are process-wide: run these one at a time.
    static SERIAL: Mutex<()> = Mutex::new(());

    fn serial() -> std::sync::MutexGuard<'static, ()> {
        SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn shell(script: &str) -> Vec<String> {
        ["/bin/sh", "-c", script].map(str::to_owned).to_vec()
    }

    fn alive(pid: i32) -> bool {
        // SAFETY: signal 0 only probes for existence.
        unsafe { libc::kill(pid, 0) == 0 }
    }

    fn pid_from(path: &std::path::Path) -> i32 {
        for _ in 0..200 {
            if let Ok(text) = std::fs::read_to_string(path)
                && let Ok(pid) = text.trim().parse()
            {
                return pid;
            }
            sleep(Duration::from_millis(25));
        }
        panic!("child did not publish its pid");
    }

    fn handler_is_default(signal: libc::c_int) -> bool {
        // SAFETY: queries the current disposition without changing it.
        unsafe {
            let mut current: libc::sigaction = std::mem::zeroed();
            libc::sigaction(signal, std::ptr::null(), &mut current);
            current.sa_sigaction != record_signal as *const () as usize
        }
    }

    #[test]
    fn real_exit_status() {
        let _serial = serial();
        let mut runner = SessionRunner::new();
        let status = runner.run(&shell("exit 7"), Duration::from_secs(10));
        assert_eq!(status.unwrap(), 7);
        let status = runner.run(&shell("exit 0"), Duration::from_secs(10));
        assert_eq!(status.unwrap(), 0);
    }

    #[test]
    fn signal_death_is_negative() {
        let _serial = serial();
        let mut runner = SessionRunner::new();
        let status = runner.run(&shell("kill -KILL $$"), Duration::from_secs(10));
        assert_eq!(status.unwrap(), -libc::SIGKILL);
    }

    #[test]
    fn missing_program_and_empty_command_fail_to_start() {
        let _serial = serial();
        let mut runner = SessionRunner::new();
        let missing = vec!["/definitely/not/a/program".to_owned()];
        assert!(runner.run(&missing, Duration::from_secs(1)).is_err());
        assert!(runner.run(&[], Duration::from_secs(1)).is_err());
        assert!(handler_is_default(libc::SIGTERM));
    }

    #[test]
    fn timeout_stops_the_owned_group_and_restores_handlers() {
        let _serial = serial();
        let dir = tempfile::tempdir().unwrap();
        let pidfile = dir.path().join("pid");
        let script = format!("sleep 30 & echo $! > {}; wait", pidfile.display());
        let mut runner = SessionRunner::with_grace(Duration::from_secs(5));
        let started = Instant::now();
        let error = runner
            .run(&shell(&script), Duration::from_millis(400))
            .unwrap_err();
        assert!(matches!(error, Error::Timeout { .. }));
        assert!(started.elapsed() < Duration::from_secs(10));
        let pid = pid_from(&pidfile);
        for _ in 0..100 {
            if !alive(pid) {
                break;
            }
            sleep(Duration::from_millis(50));
        }
        assert!(!alive(pid), "the grandchild survived the group stop");
        assert!(handler_is_default(libc::SIGTERM));
        assert!(handler_is_default(libc::SIGINT));
    }

    #[test]
    fn timeout_escalates_to_sigkill_after_grace() {
        let _serial = serial();
        let mut runner = SessionRunner::with_grace(Duration::from_millis(300));
        let started = Instant::now();
        let error = runner
            .run(
                &shell("trap '' TERM; while :; do sleep 0.1; done"),
                Duration::from_millis(300),
            )
            .unwrap_err();
        assert!(matches!(error, Error::Timeout { .. }));
        assert!(started.elapsed() < Duration::from_secs(10));
    }

    fn cancelled_by(signal: libc::c_int) -> Error {
        let mut runner = SessionRunner::with_grace(Duration::from_secs(5));
        let sender = std::thread::spawn(move || {
            sleep(Duration::from_millis(300));
            // SAFETY: the runner's handler is installed for the whole sleep.
            unsafe {
                libc::kill(libc::getpid(), signal);
            }
        });
        let error = runner
            .run(&shell("sleep 30"), Duration::from_secs(60))
            .unwrap_err();
        sender.join().unwrap();
        error
    }

    #[test]
    fn cancellation_cleans_up_and_restores_handlers() {
        let _serial = serial();
        assert!(matches!(cancelled_by(libc::SIGTERM), Error::Terminated));
        assert!(handler_is_default(libc::SIGTERM));
        assert!(matches!(cancelled_by(libc::SIGINT), Error::Interrupted));
        assert!(handler_is_default(libc::SIGINT));
    }
}

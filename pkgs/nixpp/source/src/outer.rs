//! Foreground terminal handoff to the native parent of an interactive guest.

use crate::watch::Watch;
use anyhow::{Context, Result, ensure};
use std::ffi::{OsStr, OsString};
use std::fs::{self, DirBuilder};
use std::io::{BufRead, BufReader, IsTerminal, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus};
use std::time::Duration;

const SOCKET_ENV: &str = "NIXPP_OUTER_SOCKET";
const MESSAGE_LIMIT: u64 = 64 * 1024;
const TERMINAL_HINT: &str = "Run directly in a fresh TermuxPP app terminal, outside tmux. For ADB, use termuxpp-adb-shell --outer on your computer.";

/// What a terminal's outer server holds. All of it survives a re-exec into a
/// newer nixpp: the PID stays, so the guest remains this process's child.
struct Terminal {
    directory: PathBuf,
    listener: UnixListener,
    child: libc::pid_t,
}

pub fn supervise(guest: &mut Command) -> Result<u8> {
    let directory = std::env::var_os("TMPDIR")
        .map(PathBuf::from)
        .context("native TMPDIR is not set")?
        .join(format!("nixpp-outer-{}", std::process::id()));
    DirBuilder::new().mode(0o700).create(&directory)?;
    let result = (|| {
        let socket = directory.join("s");
        let listener = UnixListener::bind(&socket)?;
        listener.set_nonblocking(true)?;
        // Reject paths that would become too long after the launcher maps /android.
        let guest_socket = PathBuf::from("/android").join(socket.strip_prefix("/")?);
        std::os::unix::net::SocketAddr::from_pathname(&guest_socket)?;
        let child = guest.env(SOCKET_ENV, guest_socket).spawn()?;
        let child = libc::pid_t::try_from(child.id()).context("guest PID out of range")?;
        serve(Terminal {
            directory: directory.clone(),
            listener,
            child,
        })
    })();
    remove_socket(&directory);
    result
}

/// Continue serving a terminal after a re-exec into a newer nixpp.
pub fn resume(listener: RawFd, child: libc::pid_t, directory: PathBuf) -> Result<u8> {
    ensure!(listener > 2 && child > 0, "invalid outer terminal state");
    // SAFETY: the previous executable handed over this listening socket.
    let listener = unsafe { UnixListener::from_raw_fd(listener) };
    set_cloexec(listener.as_raw_fd(), true)?;
    listener.set_nonblocking(true)?;
    let result = serve(Terminal {
        directory: directory.clone(),
        listener,
        child,
    });
    remove_socket(&directory);
    result
}

fn remove_socket(directory: &Path) {
    let _ = fs::remove_file(directory.join("s"));
    let _ = fs::remove_dir(directory);
}

/// How long to block without pidfd or inotify (old kernels): the guest's exit
/// and a replaced nixpp are then noticed within this time.
const FALLBACK_WAIT_MS: i32 = 2000;

/// Serves the terminal until the guest exits. Blocks in poll(2) on the
/// listening socket, a pidfd for the guest and an inotify watch on the
/// executable, so an idle terminal never wakes up.
fn serve(terminal: Terminal) -> Result<u8> {
    let mut executable = Executable::current();
    let mut watch = executable.as_ref().and_then(|current| {
        let name = current.path.file_name()?.as_bytes().to_vec();
        Watch::new(current.path.parent()?, vec![name])
    });
    let guest = pidfd(terminal.child);
    loop {
        if let Some(code) = child_exit(terminal.child)? {
            return Ok(code);
        }
        let mut fds = vec![libc::pollfd {
            fd: terminal.listener.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        }];
        for fd in [guest.as_ref(), watch.as_ref().map(Watch::fd)]
            .into_iter()
            .flatten()
        {
            fds.push(libc::pollfd {
                fd: fd.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            });
        }
        let fallback = guest.is_none() || (executable.is_some() && watch.is_none());
        let timeout = if fallback { FALLBACK_WAIT_MS } else { -1 };
        // SAFETY: fds points to fds.len() initialised pollfd entries.
        let ready = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout) };
        if ready < 0 {
            let error = std::io::Error::last_os_error();
            if error.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err(error.into());
        }
        if fds[0].revents != 0 {
            accept_one(&terminal.listener)?;
        }
        let changed = match &mut watch {
            Some(watch) => watch.drain(),
            None => ready == 0,
        };
        if changed
            && let Some(current) = &executable
            && current.replaced()
        {
            // Only returns on failure; keep serving with this code.
            let error = reexec(&terminal, &current.path);
            eprintln!("nixpp: this terminal keeps the previous nixpp: {error:#}");
            executable = None;
            watch = None;
        }
    }
}

fn accept_one(listener: &UnixListener) -> Result<()> {
    let mut stream = match listener.accept() {
        Ok((stream, _)) => stream,
        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    let code = match run_request(&mut stream) {
        // A client that found this socket unusable (another session, for
        // example under script(1)) hangs up without a request and falls back
        // to the daemon.
        Ok(None) => return Ok(()),
        Ok(Some(status)) => status,
        Err(error) => {
            eprintln!("nixpp outer: {error:#}");
            1
        }
    };
    let _ = writeln!(stream, "{code}");
    Ok(())
}

/// A pidfd that becomes readable when `child` exits; None before Linux 5.3.
fn pidfd(child: libc::pid_t) -> Option<OwnedFd> {
    // SAFETY: pidfd_open takes a PID and flags and returns a new descriptor.
    let fd = unsafe { libc::syscall(libc::SYS_pidfd_open, child, 0) };
    let fd = RawFd::try_from(fd).ok().filter(|fd| *fd >= 0)?;
    // SAFETY: the kernel just returned this descriptor to us.
    Some(unsafe { OwnedFd::from_raw_fd(fd) })
}

/// The guest's exit code once it has exited, reaping it.
fn child_exit(child: libc::pid_t) -> Result<Option<u8>> {
    let mut status = 0;
    // SAFETY: waitpid on our own child with WNOHANG and a valid status pointer.
    let reaped = unsafe { libc::waitpid(child, &mut status, libc::WNOHANG) };
    if reaped == 0 {
        return Ok(None);
    }
    ensure!(
        reaped == child,
        "cannot wait for the guest shell: {}",
        std::io::Error::last_os_error()
    );
    Ok(Some(exit_code(ExitStatus::from_raw(status))))
}

/// The executable this process runs, to notice when an update replaces it.
struct Executable {
    path: PathBuf,
    identity: (u64, u64),
}

impl Executable {
    fn current() -> Option<Self> {
        let path = crate::provision::running_executable().ok()?;
        let identity = identity(&path)?;
        Some(Self { path, identity })
    }

    /// Whether another executable file now sits at the path (an update
    /// installs a new file rather than rewriting this one).
    fn replaced(&self) -> bool {
        use std::os::unix::fs::PermissionsExt;
        fs::metadata(&self.path).is_ok_and(|found| {
            found.is_file()
                && found.permissions().mode() & 0o111 != 0
                && identity(&self.path).is_some_and(|new| new != self.identity)
        })
    }
}

fn identity(path: &Path) -> Option<(u64, u64)> {
    use std::os::unix::fs::MetadataExt;
    fs::metadata(path)
        .ok()
        .map(|found| (found.dev(), found.ino()))
}

/// Replace this process with `executable`, handing over the terminal. Returns
/// only when the exec failed.
fn reexec(terminal: &Terminal, executable: &Path) -> anyhow::Error {
    let fd = terminal.listener.as_raw_fd();
    if let Err(error) = set_cloexec(fd, false) {
        return error;
    }
    // Android starts executables from app data through its linker; so must we.
    let mut command = match std::env::current_exe() {
        Ok(current)
            if matches!(
                current.file_name().and_then(|name| name.to_str()),
                Some("linker" | "linker64")
            ) =>
        {
            let mut command = Command::new(current);
            command.arg(executable);
            command
        }
        _ => Command::new(executable),
    };
    command
        .arg("__outer-resume")
        .arg("--listener-fd")
        .arg(fd.to_string())
        .arg("--child")
        .arg(terminal.child.to_string())
        .arg("--dir")
        .arg(&terminal.directory);
    let error = anyhow::Error::from(command.exec()).context("cannot start the updated nixpp");
    let _ = set_cloexec(fd, true);
    error
}

fn set_cloexec(fd: RawFd, on: bool) -> Result<()> {
    // SAFETY: fcntl on a descriptor this process owns.
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFD) };
    ensure!(flags >= 0, "fcntl: {}", std::io::Error::last_os_error());
    let flags = if on {
        flags | libc::FD_CLOEXEC
    } else {
        flags & !libc::FD_CLOEXEC
    };
    // SAFETY: as above.
    let result = unsafe { libc::fcntl(fd, libc::F_SETFD, flags) };
    ensure!(result >= 0, "fcntl: {}", std::io::Error::last_os_error());
    Ok(())
}

pub fn request(args: &[OsString]) -> Result<u8> {
    let terminal = std::io::stdin().is_terminal()
        && std::io::stdout().is_terminal()
        && std::io::stderr().is_terminal();
    let stream = std::env::var_os(SOCKET_ENV)
        .filter(|socket| terminal && !socket.is_empty())
        .and_then(|socket| UnixStream::connect(socket).ok())
        .filter(|stream| {
            crate::server::peer_credentials(stream).is_some_and(|peer| {
                // SAFETY: getsid only queries sessions; zero denotes this process.
                unsafe { peer.pid > 0 && libc::getsid(peer.pid) == libc::getsid(0) }
            })
        });
    let Some(mut stream) = stream else {
        return crate::outer_remote::request(args).with_context(|| TERMINAL_HINT);
    };
    let args: Vec<&[u8]> = args.iter().map(|arg| OsStr::new(arg).as_bytes()).collect();
    let request = serde_json::to_vec(&args)?;
    ensure!(
        request.len() < MESSAGE_LIMIT as usize,
        "outer command is too long"
    );
    stream.write_all(&request)?;
    stream.write_all(b"\n")?;
    let mut response = String::new();
    BufReader::new(stream).take(8).read_line(&mut response)?;
    response
        .trim()
        .parse()
        .context("outer command returned no exit status")
}

/// Runs one request; None when the client hung up without sending one.
fn run_request(stream: &mut UnixStream) -> Result<Option<u8>> {
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    let mut request = Vec::new();
    BufReader::new(&mut *stream)
        .take(MESSAGE_LIMIT)
        .read_until(b'\n', &mut request)?;
    if request.is_empty() {
        return Ok(None);
    }
    ensure!(request.ends_with(b"\n"), "incomplete outer command request");
    let args: Vec<Vec<u8>> = serde_json::from_slice(&request)?;
    let args: Vec<OsString> = args.into_iter().map(OsString::from_vec).collect();
    let credentials =
        crate::server::peer_credentials(stream).context("missing outer command peer")?;
    // SAFETY: these scalar calls query credentials, process groups and the owned terminal.
    let foreground = unsafe {
        let group = libc::getpgid(credentials.pid);
        let terminal = libc::tcgetpgrp(std::io::stdin().as_raw_fd());
        (credentials.uid == libc::geteuid()
            && credentials.pid > 0
            && libc::getsid(credentials.pid) == libc::getsid(0)
            && group > 0
            && group == terminal)
            .then_some(group)
    }
    .with_context(|| {
        format!(
            "outer commands must run in the original terminal's foreground job. {TERMINAL_HINT}"
        )
    })?;
    let status = crate::provision::native_command(&args)?
        .process_group(foreground)
        .status()
        .context("cannot run the outer command")?;
    Ok(Some(exit_code(status)))
}

pub(crate) fn exit_code(status: ExitStatus) -> u8 {
    u8::try_from(
        status
            .code()
            .unwrap_or_else(|| 128 + status.signal().unwrap_or(1)),
    )
    .unwrap_or(1)
}

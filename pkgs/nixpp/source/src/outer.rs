//! Foreground terminal handoff to the native parent of an interactive guest.

use anyhow::{Context, Result, ensure};
use std::ffi::{OsStr, OsString};
use std::fs::{self, DirBuilder};
use std::io::{BufRead, BufReader, IsTerminal, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::PathBuf;
use std::process::{Command, ExitStatus};
use std::time::Duration;

const SOCKET_ENV: &str = "NIXPP_OUTER_SOCKET";
const MESSAGE_LIMIT: u64 = 64 * 1024;
const TERMINAL_HINT: &str = "Run directly in a fresh TermuxPP app terminal, outside tmux. For ADB, use termuxpp-adb-shell --outer on your computer.";

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
        let mut child = guest.env(SOCKET_ENV, guest_socket).spawn()?;
        loop {
            if let Some(status) = child.try_wait()? {
                return Ok(exit_code(status));
            }
            match listener.accept() {
                Ok((mut stream, _)) => {
                    let code = match run_request(&mut stream) {
                        Ok(status) => status,
                        Err(error) => {
                            eprintln!("nixpp outer: {error:#}");
                            1
                        }
                    };
                    let _ = writeln!(stream, "{code}");
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(20));
                }
                Err(error) => return Err(error.into()),
            }
        }
    })();
    let _ = fs::remove_file(directory.join("s"));
    let _ = fs::remove_dir(&directory);
    result
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

fn run_request(stream: &mut UnixStream) -> Result<u8> {
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    let mut request = Vec::new();
    BufReader::new(&mut *stream)
        .take(MESSAGE_LIMIT)
        .read_until(b'\n', &mut request)?;
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
    Ok(exit_code(status))
}

pub(crate) fn exit_code(status: ExitStatus) -> u8 {
    u8::try_from(
        status
            .code()
            .unwrap_or_else(|| 128 + status.signal().unwrap_or(1)),
    )
    .unwrap_or(1)
}

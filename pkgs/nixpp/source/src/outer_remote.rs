//! Native command transport for guests without an app-terminal parent.

use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use std::ffi::OsString;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, IsTerminal, Read, Write};
use std::mem::{self, MaybeUninit};
use std::os::fd::{AsFd, AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::{
    ffi::OsStringExt,
    fs::{FileTypeExt, PermissionsExt},
    net::{UnixListener, UnixStream},
    process::CommandExt,
};
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

const SOCKET: &str = "outer.sock";
const GUEST_SOCKET: &str = "/run/nixpp-runtime/outer.sock";
const MAX_REQUEST: usize = 64 * 1024;
const CONCURRENT_SESSIONS: usize = 8;
// Android/aarch64 uses the asm-generic Linux PTY ioctl numbers.
#[cfg(target_os = "android")]
const TIOCGPTPEER: libc::c_int = 0x5441;
#[cfg(not(target_os = "android"))]
use libc::TIOCGPTPEER;

#[derive(Deserialize, Serialize)]
struct Request {
    args: Vec<Vec<u8>>,
    terminal: Option<Window>,
    term: Option<String>,
}

#[derive(Clone, Copy, Deserialize, Serialize)]
struct Window {
    rows: u16,
    cols: u16,
    xpixel: u16,
    ypixel: u16,
}

impl Window {
    fn read(fd: RawFd) -> Result<Self> {
        let mut size = MaybeUninit::<libc::winsize>::uninit();
        // SAFETY: TIOCGWINSZ writes a winsize into the supplied buffer on success.
        let value = unsafe {
            if libc::ioctl(fd, libc::TIOCGWINSZ, size.as_mut_ptr()) < 0 {
                return Err(io::Error::last_os_error().into());
            }
            size.assume_init()
        };
        Ok(Self {
            rows: value.ws_row,
            cols: value.ws_col,
            xpixel: value.ws_xpixel,
            ypixel: value.ws_ypixel,
        })
    }

    fn apply(self, fd: RawFd) -> io::Result<()> {
        let size = libc::winsize {
            ws_row: self.rows,
            ws_col: self.cols,
            ws_xpixel: self.xpixel,
            ws_ypixel: self.ypixel,
        };
        // SAFETY: TIOCSWINSZ reads the initialized winsize; the fd remains open.
        cvt(unsafe { libc::ioctl(fd, libc::TIOCSWINSZ, &size) }).map(|_| ())
    }
}

pub(crate) fn start(runtime: &Path) -> Result<()> {
    let path = runtime.join(SOCKET);
    crate::server::remove_stale_socket(&path)?;
    let listener = UnixListener::bind(&path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    for _ in 0..CONCURRENT_SESSIONS {
        let listener = listener.try_clone()?;
        std::thread::Builder::new()
            .name("outer-command".into())
            .spawn(move || {
                for connection in listener.incoming() {
                    let Ok(mut stream) = connection else { continue };
                    if let Err(error) =
                        serve_connection(&mut stream, crate::provision::native_command)
                    {
                        let _ = stream.write_all(&[1]);
                        let _ = writeln!(stream, "{error:#}");
                    }
                }
            })?;
    }
    Ok(())
}

pub(crate) fn request(args: &[OsString]) -> Result<u8> {
    use std::os::unix::ffi::OsStrExt;
    let mut stream = UnixStream::connect(GUEST_SOCKET).context(
        "native outer socket unavailable; update or restart the TermuxPP native runtime",
    )?;
    require_same_uid(&stream)?;
    let terminal =
        io::stdin().is_terminal() && io::stdout().is_terminal() && io::stderr().is_terminal();
    ensure!(
        terminal || !args.is_empty(),
        "a native shell needs a terminal; use ssh -t"
    );
    let request = Request {
        args: args
            .iter()
            .map(|arg| arg.as_os_str().as_bytes().to_vec())
            .collect(),
        terminal: terminal
            .then(|| Window::read(libc::STDIN_FILENO))
            .transpose()?,
        term: std::env::var("TERM").ok(),
    };
    let body = serde_json::to_vec(&request)?;
    ensure!(body.len() <= MAX_REQUEST, "outer command is too long");
    stream.write_all(&(body.len() as u32).to_be_bytes())?;
    stream.write_all(&body)?;

    if terminal {
        let mut ready = [0];
        stream.read_exact(&mut ready)?;
        check_reply(&mut stream, ready[0])?;
        let mut descriptors = receive_fds(&stream, 1)?;
        let master = File::from(descriptors.pop().context("missing native PTY")?);
        relay_terminal(&mut stream, master)
    } else {
        send_fds(
            &stream,
            &[libc::STDIN_FILENO, libc::STDOUT_FILENO, libc::STDERR_FILENO],
        )?;
        let mut ready = [0];
        stream.read_exact(&mut ready)?;
        check_reply(&mut stream, ready[0])?;
        read_status(&mut stream)
    }
}

fn check_reply(stream: &mut UnixStream, ready: u8) -> Result<()> {
    if ready != 0 {
        let mut message = String::new();
        BufReader::new(stream).take(4096).read_line(&mut message)?;
        anyhow::bail!("{}", message.trim());
    }
    Ok(())
}

fn read_status(stream: &mut UnixStream) -> Result<u8> {
    let mut status = [0];
    stream
        .read_exact(&mut status)
        .context("native command returned no exit status")?;
    Ok(status[0])
}

fn require_same_uid(stream: &UnixStream) -> Result<()> {
    let credentials =
        crate::server::peer_credentials(stream).context("missing native outer peer")?;
    // SAFETY: geteuid has no preconditions.
    ensure!(
        credentials.uid == unsafe { libc::geteuid() },
        "native outer socket requires the same UID"
    );
    Ok(())
}

fn serve_connection(
    stream: &mut UnixStream,
    command: impl FnOnce(&[OsString]) -> Result<Command>,
) -> Result<()> {
    require_same_uid(stream)?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    let mut length = [0; 4];
    stream.read_exact(&mut length)?;
    let length = u32::from_be_bytes(length) as usize;
    ensure!(length <= MAX_REQUEST, "native command is too long");
    let mut body = vec![0; length];
    stream.read_exact(&mut body)?;
    let request: Request = serde_json::from_slice(&body)?;
    let mut command = command(
        &request
            .args
            .into_iter()
            .map(OsString::from_vec)
            .collect::<Vec<_>>(),
    )?;
    if let Some(term) = request.term {
        command.env("TERM", term);
    }
    let (mut child, master, output_watch) = match request.terminal {
        Some(size) => {
            let (master, slave) = open_pty(size)?;
            let (stdin, stdout) = (slave.try_clone()?, slave.try_clone()?);
            command.stdin(stdin).stdout(stdout).stderr(slave);
            // SAFETY: the child only performs async-signal-safe syscalls; fd 0
            // is the slave installed by Command before this hook.
            unsafe {
                command.pre_exec(|| {
                    for signal in [libc::SIGINT, libc::SIGQUIT, libc::SIGHUP, libc::SIGTERM] {
                        if libc::signal(signal, libc::SIG_DFL) == libc::SIG_ERR {
                            return Err(io::Error::last_os_error());
                        }
                    }
                    cvt(libc::setsid())?;
                    cvt(libc::ioctl(libc::STDIN_FILENO, libc::TIOCSCTTY, 0))?;
                    cvt(libc::tcsetpgrp(libc::STDIN_FILENO, libc::getpgrp()))?;
                    Ok(())
                });
            }
            (command.spawn()?, Some(master), Vec::new())
        }
        None => {
            let [stdin, stdout, stderr]: [OwnedFd; 3] = receive_fds(stream, 3)?
                .try_into()
                .map_err(|_| anyhow::anyhow!("expected three native stream descriptors"))?;
            let stdout = File::from(stdout);
            let stderr = File::from(stderr);
            let output_watch = watch_outputs([&stdout, &stderr])?;
            command
                .stdin(Stdio::from(stdin))
                .stdout(Stdio::from(stdout))
                .stderr(Stdio::from(stderr))
                .process_group(0);
            (command.spawn()?, None, output_watch)
        }
    };
    // Command keeps its Stdio handles until dropped, including the PTY slave.
    drop(command);
    let result = (|| {
        stream.write_all(&[0])?;
        if let Some(master) = master {
            send_fds(stream, &[master.as_raw_fd()])?;
        }
        let status = wait_for_client(stream, &output_watch, &mut child)?;
        stream.write_all(&[status])?;
        Ok(())
    })();
    if result.is_err() {
        // SAFETY: the child owns a process group named by its PID. It has not
        // been reaped unless wait_for_client already returned a status.
        if child.try_wait()?.is_none() {
            unsafe {
                libc::kill(-(child.id() as libc::pid_t), libc::SIGKILL);
            }
            let _ = child.wait();
        }
    }
    result
}

fn watch_outputs(outputs: [&File; 2]) -> io::Result<Vec<File>> {
    let mut watched = Vec::new();
    for output in outputs {
        let kind = output.metadata()?.file_type();
        if kind.is_fifo() || kind.is_socket() || output.is_terminal() {
            watched.push(output.try_clone()?);
        }
    }
    Ok(watched)
}

fn wait_for_client(stream: &UnixStream, outputs: &[File], child: &mut Child) -> Result<u8> {
    let mut control = vec![pollfd(stream.as_raw_fd(), libc::POLLIN)];
    control.extend(outputs.iter().map(|output| pollfd(output.as_raw_fd(), 0)));
    loop {
        if let Some(status) = child.try_wait()? {
            return Ok(super::outer::exit_code(status));
        }
        poll(&mut control, 100)?;
        ensure!(
            control[0].revents == 0,
            "native command client disconnected"
        );
        // OpenSSH can leave the command alive after dropping its streams.
        // Monitor the output peers too, without consuming input or output.
        for output in &mut control[1..] {
            if output.revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0 {
                output.fd = -1;
            }
        }
        ensure!(
            outputs.is_empty() || control[1..].iter().any(|output| output.fd >= 0),
            "native command output disconnected"
        );
    }
}

fn open_pty(size: Window) -> Result<(OwnedFd, File)> {
    // SAFETY: posix_openpt returns a fresh fd on success.
    let raw = cvt(unsafe { libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY | libc::O_CLOEXEC) })?;
    // SAFETY: raw is the newly allocated master and is owned by this function.
    let master = unsafe { OwnedFd::from_raw_fd(raw) };
    // SAFETY: raw still refers to the open master. The peer ioctl returns a new fd.
    let slave = unsafe {
        cvt(libc::grantpt(raw))?;
        cvt(libc::unlockpt(raw))?;
        File::from_raw_fd(cvt(libc::ioctl(
            raw,
            TIOCGPTPEER,
            libc::O_RDWR | libc::O_NOCTTY | libc::O_CLOEXEC,
        ))?)
    };
    size.apply(raw)?;
    Ok((master, slave))
}

struct RawTerminal(libc::termios);

impl RawTerminal {
    fn enter() -> Result<Self> {
        let mut original = MaybeUninit::uninit();
        // SAFETY: tcgetattr initializes termios on success. Both attributes
        // passed back to libc are initialized and stdin remains open.
        unsafe {
            cvt(libc::tcgetattr(libc::STDIN_FILENO, original.as_mut_ptr()))?;
            let original = original.assume_init();
            let mut raw = original;
            libc::cfmakeraw(&mut raw);
            cvt(libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &raw))?;
            Ok(Self(original))
        }
    }
}

impl Drop for RawTerminal {
    fn drop(&mut self) {
        // SAFETY: the original value was initialized by tcgetattr.
        unsafe {
            libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &self.0);
        }
    }
}

fn relay_terminal(stream: &mut UnixStream, mut master: File) -> Result<u8> {
    let _terminal = RawTerminal::enter()?;
    let mut stdin = File::from(io::stdin().as_fd().try_clone_to_owned()?);
    let mut stdout = File::from(io::stdout().as_fd().try_clone_to_owned()?);
    let mut fds = [
        pollfd(libc::STDIN_FILENO, libc::POLLIN),
        pollfd(master.as_raw_fd(), libc::POLLIN),
        pollfd(stream.as_raw_fd(), libc::POLLIN),
    ];
    let mut buffer = [0; 4096];
    let mut status = None;
    let mut previous = None;
    while fds[1].fd >= 0 || status.is_none() {
        let size = Window::read(libc::STDIN_FILENO)?;
        let dimensions = (size.rows, size.cols, size.xpixel, size.ypixel);
        if previous != Some(dimensions) && fds[1].fd >= 0 {
            size.apply(master.as_raw_fd())?;
            previous = Some(dimensions);
        }
        poll(&mut fds, 100)?;
        if fds[1].revents != 0 {
            match master.read(&mut buffer) {
                Ok(0) => fds[1].fd = -1,
                Ok(count) => stdout.write_all(&buffer[..count])?,
                Err(error) if error.raw_os_error() == Some(libc::EIO) => fds[1].fd = -1,
                Err(error) => return Err(error.into()),
            }
        }
        if fds[2].revents != 0 {
            status = Some(read_status(stream)?);
            fds[2].fd = -1;
            fds[0].fd = -1;
        }
        if fds[0].fd >= 0 && fds[0].revents != 0 {
            let count = stdin.read(&mut buffer)?;
            ensure!(count != 0, "terminal disconnected");
            if fds[1].fd >= 0 {
                master.write_all(&buffer[..count])?;
            }
        }
    }
    status.context("native command returned no exit status")
}

fn pollfd(fd: RawFd, events: libc::c_short) -> libc::pollfd {
    libc::pollfd {
        fd,
        events,
        revents: 0,
    }
}

fn poll(fds: &mut [libc::pollfd], timeout: libc::c_int) -> io::Result<()> {
    // SAFETY: poll receives a valid mutable array with its actual length.
    match cvt(unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout) }) {
        Err(error) if error.kind() != io::ErrorKind::Interrupted => Err(error),
        _ => Ok(()),
    }
}

fn cvt(value: libc::c_int) -> io::Result<libc::c_int> {
    if value < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(value)
    }
}

fn send_fds(stream: &UnixStream, fds: &[RawFd]) -> Result<()> {
    let mut control = [0usize; 8];
    let mut marker = [0u8];
    let mut data = libc::iovec {
        iov_base: marker.as_mut_ptr().cast(),
        iov_len: marker.len(),
    };
    // SAFETY: zero is valid for msghdr; iov and ancillary storage have stable
    // addresses and sufficient alignment and capacity until sendmsg returns.
    unsafe {
        let mut message: libc::msghdr = mem::zeroed();
        message.msg_iov = &mut data;
        message.msg_iovlen = 1;
        message.msg_control = control.as_mut_ptr().cast();
        let size = mem::size_of_val(fds) as libc::c_uint;
        let space = libc::CMSG_SPACE(size) as usize;
        ensure!(
            space <= mem::size_of_val(&control),
            "too many native descriptors"
        );
        message.msg_controllen = space as _;
        let header = libc::CMSG_FIRSTHDR(&message);
        (*header).cmsg_level = libc::SOL_SOCKET;
        (*header).cmsg_type = libc::SCM_RIGHTS;
        (*header).cmsg_len = libc::CMSG_LEN(size) as _;
        std::ptr::copy_nonoverlapping(fds.as_ptr(), libc::CMSG_DATA(header).cast(), fds.len());
        if libc::sendmsg(stream.as_raw_fd(), &message, libc::MSG_NOSIGNAL) != 1 {
            return Err(io::Error::last_os_error().into());
        }
    }
    Ok(())
}

fn receive_fds(stream: &UnixStream, count: usize) -> Result<Vec<OwnedFd>> {
    let mut control = [0usize; 8];
    let mut marker = [0u8];
    let mut data = libc::iovec {
        iov_base: marker.as_mut_ptr().cast(),
        iov_len: marker.len(),
    };
    let mut fds = Vec::new();
    // SAFETY: the aligned control buffer and one-byte data buffer outlive
    // recvmsg. Only kernel-produced SCM_RIGHTS payloads are interpreted, and
    // every received fd is immediately transferred to an owning handle.
    unsafe {
        let mut message: libc::msghdr = mem::zeroed();
        message.msg_iov = &mut data;
        message.msg_iovlen = 1;
        message.msg_control = control.as_mut_ptr().cast();
        message.msg_controllen = mem::size_of_val(&control) as _;
        let result = libc::recvmsg(stream.as_raw_fd(), &mut message, libc::MSG_CMSG_CLOEXEC);
        if result < 0 {
            return Err(io::Error::last_os_error().into());
        }
        let mut header = libc::CMSG_FIRSTHDR(&message);
        while !header.is_null() {
            if (*header).cmsg_level == libc::SOL_SOCKET && (*header).cmsg_type == libc::SCM_RIGHTS {
                let bytes = (*header).cmsg_len as usize - libc::CMSG_LEN(0) as usize;
                let handles = std::slice::from_raw_parts(
                    libc::CMSG_DATA(header).cast::<RawFd>(),
                    bytes / mem::size_of::<RawFd>(),
                );
                fds.extend(handles.iter().map(|&fd| OwnedFd::from_raw_fd(fd)));
            }
            header = libc::CMSG_NXTHDR(&message, header);
        }
        ensure!(
            result == 1 && message.msg_flags & libc::MSG_CTRUNC == 0 && fds.len() == count,
            "invalid native descriptor message"
        );
    }
    Ok(fds)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Shutdown;

    fn client_request(stream: &mut UnixStream, command: &str, terminal: Option<Window>) {
        let body = serde_json::to_vec(&Request {
            args: vec![
                b"/bin/sh".to_vec(),
                b"-c".to_vec(),
                command.as_bytes().to_vec(),
            ],
            terminal,
            term: Some("xterm".into()),
        })
        .unwrap();
        stream
            .write_all(&(body.len() as u32).to_be_bytes())
            .unwrap();
        stream.write_all(&body).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
    }

    fn command(args: &[OsString]) -> Result<Command> {
        let mut command = Command::new(&args[0]);
        command.args(&args[1..]);
        Ok(command)
    }

    #[test]
    fn remote_command_passes_separate_streams_and_exit_status() {
        let (mut server, mut client) = UnixStream::pair().unwrap();
        let (input, mut writer) = UnixStream::pair().unwrap();
        let (output, mut reader) = UnixStream::pair().unwrap();
        let (error, mut error_reader) = UnixStream::pair().unwrap();
        let worker = std::thread::spawn(move || serve_connection(&mut server, command));
        client_request(
            &mut client,
            "read line; printf '%s\\n' \"$line\"; printf '%s\\n' err >&2; exit 42",
            None,
        );
        send_fds(
            &client,
            &[input.as_raw_fd(), output.as_raw_fd(), error.as_raw_fd()],
        )
        .unwrap();
        drop((input, output, error));
        writer.write_all(b"guest input\n").unwrap();
        writer.shutdown(Shutdown::Write).unwrap();
        let mut ready = [255];
        client.read_exact(&mut ready).unwrap();
        assert_eq!(ready, [0]);
        assert_eq!(read_status(&mut client).unwrap(), 42);
        worker.join().unwrap().unwrap();
        let mut output = String::new();
        let mut error = String::new();
        reader.read_to_string(&mut output).unwrap();
        error_reader.read_to_string(&mut error).unwrap();
        assert_eq!(output, "guest input\n");
        assert_eq!(error, "err\n");
    }

    #[test]
    fn remote_pty_has_a_controlling_terminal_and_propagates_interrupt() {
        let (mut server, mut client) = UnixStream::pair().unwrap();
        let worker = std::thread::spawn(move || serve_connection(&mut server, command));
        let size = Window {
            rows: 24,
            cols: 80,
            xpixel: 0,
            ypixel: 0,
        };
        client_request(
            &mut client,
            "test -t 0 && test -t 1 && test -t 2 && test -r /dev/tty || exit 2; stty size; read line; stty size; trap 'exit 130' INT; echo ready; read line; exit 3",
            Some(size),
        );
        let mut ready = [255];
        client.read_exact(&mut ready).unwrap();
        assert_eq!(ready, [0]);
        let mut master = receive_fds(&client, 1).unwrap();
        let mut master = File::from(master.pop().unwrap());
        let mut reader = BufReader::new(master.try_clone().unwrap());
        let mut readable = [pollfd(master.as_raw_fd(), libc::POLLIN)];
        poll(&mut readable, 5000).unwrap();
        assert_ne!(readable[0].revents, 0);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        assert_eq!(line.trim(), "24 80");
        Window {
            rows: 36,
            cols: 100,
            ..size
        }
        .apply(master.as_raw_fd())
        .unwrap();
        master.write_all(b"continue\n").unwrap();
        for expected in ["continue", "36 100", "ready"] {
            if reader.buffer().is_empty() {
                poll(&mut readable, 5000).unwrap();
                assert_ne!(readable[0].revents, 0);
            }
            line.clear();
            reader.read_line(&mut line).unwrap();
            assert_eq!(line.trim(), expected);
        }
        master.write_all(b"\x03").unwrap();
        assert_eq!(read_status(&mut client).unwrap(), 130);
        worker.join().unwrap().unwrap();
    }

    #[test]
    fn remote_command_is_reaped_when_client_disconnects() {
        let (mut server, mut client) = UnixStream::pair().unwrap();
        let null = File::open("/dev/null").unwrap();
        let worker = std::thread::spawn(move || serve_connection(&mut server, command));
        client_request(&mut client, "exec sleep 30", None);
        send_fds(&client, &[null.as_raw_fd(); 3]).unwrap();
        let mut ready = [255];
        client.read_exact(&mut ready).unwrap();
        assert_eq!(ready, [0]);
        drop(client);
        assert!(worker.join().unwrap().is_err());
    }

    #[test]
    fn remote_command_stops_when_ssh_closes_output_but_keeps_the_client_alive() {
        let (mut server, mut client) = UnixStream::pair().unwrap();
        let null = File::open("/dev/null").unwrap();
        let (stdout, stdout_reader) = UnixStream::pair().unwrap();
        let (stderr, stderr_reader) = UnixStream::pair().unwrap();
        let worker = std::thread::spawn(move || serve_connection(&mut server, command));
        client_request(&mut client, "exec sleep 30", None);
        send_fds(
            &client,
            &[null.as_raw_fd(), stdout.as_raw_fd(), stderr.as_raw_fd()],
        )
        .unwrap();
        let mut ready = [255];
        client.read_exact(&mut ready).unwrap();
        assert_eq!(ready, [0]);
        drop((stdout_reader, stderr_reader));
        let error = worker.join().unwrap().unwrap_err();
        assert_eq!(error.to_string(), "native command output disconnected");
    }
}

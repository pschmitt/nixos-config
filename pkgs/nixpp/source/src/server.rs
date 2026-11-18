//! The native management socket.
//!
//! One request per connection: a single JSON line of at most 4096 bytes from a
//! peer with the same UID, answered by a single JSON line of at most 65536
//! bytes. Requests are handled one at a time; every mutation additionally
//! takes the controller lock.

use crate::controller;
use crate::error::{Error, Result};
use crate::fsutil::{FileLock, canonical_json};
use crate::runner::Runner;
use serde_json::{Value, json};
use std::fs;
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::time::{Duration, Instant};

/// Largest accepted request line, including the newline.
pub const REQUEST_LIMIT: usize = 4096;
/// Largest response line, including the newline.
pub const RESPONSE_LIMIT: usize = 65536;
/// Time a client has to deliver its request and to accept the response.
const IO_TIMEOUT: Duration = Duration::from_secs(5);
/// How often an idle server looks at its stop flag.
const POLL_INTERVAL_MS: libc::c_int = 250;

const SERVER_LOCK: &str = "system-server.lock";

/// A bound management socket. Dropping it unlinks the socket path.
#[derive(Debug)]
pub struct Server {
    listener: UnixListener,
    path: PathBuf,
    runtime: PathBuf,
    _lock: FileLock,
}

fn own_uid() -> u32 {
    // SAFETY: getuid has no preconditions and cannot fail.
    unsafe { libc::getuid() }
}

fn check_socket_directory(path: &Path) -> Result<()> {
    let parent = match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    };
    let metadata = fs::symlink_metadata(parent)?;
    if !metadata.file_type().is_dir() || metadata.uid() != own_uid() || metadata.mode() & 0o022 != 0
    {
        return Err(Error::invalid(
            "management socket needs an owned, non-writable-by-others directory",
        ));
    }
    Ok(())
}

pub(crate) fn remove_stale_socket(path: &Path) -> Result<()> {
    check_socket_directory(path)?;
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_socket() && metadata.uid() == own_uid() => {
            fs::remove_file(path)?;
        }
        Ok(_) => {
            return Err(Error::invalid(
                "refusing to replace a non-socket or foreign socket",
            ));
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

impl Server {
    /// Take the server lock and bind `path`.
    ///
    /// Returns `Ok(None)` when another server already holds the lock; its
    /// socket is left untouched. A stale socket of our own is replaced, any
    /// other file at `path` is refused.
    pub fn bind(runtime: &Path, path: &Path) -> Result<Option<Self>> {
        let runtime = fs::canonicalize(runtime)?;
        check_socket_directory(path)?;
        let Some(lock) = FileLock::try_acquire(&runtime.join(SERVER_LOCK))? else {
            return Ok(None);
        };
        remove_stale_socket(path)?;
        let listener = UnixListener::bind(path)?;
        // Constructed before the chmod so that a failure unlinks the socket.
        let server = Self {
            listener,
            path: path.to_owned(),
            runtime,
            _lock: lock,
        };
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
        server.listener.set_nonblocking(true)?;
        Ok(Some(server))
    }

    /// The socket path this server listens on.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Accept and answer connections until `stop` is set.
    ///
    /// Only a SIGINT/SIGTERM that reaches a running command ends the loop with
    /// an error; every other failure is reported to the client or dropped.
    pub fn run(&self, runner: &mut dyn Runner, stop: &AtomicBool) -> Result<()> {
        while !stop.load(Ordering::SeqCst) {
            if !self.wait_readable() {
                continue;
            }
            let stream = match self.listener.accept() {
                Ok((stream, _)) => stream,
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                    ) =>
                {
                    continue;
                }
                Err(error) => return Err(error.into()),
            };
            self.handle(stream, runner)?;
        }
        Ok(())
    }

    fn wait_readable(&self) -> bool {
        let mut descriptor = libc::pollfd {
            fd: self.listener.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: one valid pollfd that outlives the call.
        let ready = unsafe { libc::poll(&mut descriptor, 1, POLL_INTERVAL_MS) };
        ready > 0
    }

    fn handle(&self, stream: UnixStream, runner: &mut dyn Runner) -> Result<()> {
        if stream.set_nonblocking(false).is_err() || peer_uid(&stream) != Some(own_uid()) {
            return Ok(());
        }
        let response = match read_request(&stream) {
            Err(Outcome::Drop) => return Ok(()),
            Err(Outcome::Reject(message)) => error_response(&message),
            Ok(request) => match controller::dispatch(&self.runtime, &request, runner) {
                Ok(response) => response,
                Err(error) if error.is_stop_request() => return Err(error),
                Err(error) => error_response(&error.to_string()),
            },
        };
        // A client that vanished or stalled must not take the server down.
        let _ = write_response(&stream, &response);
        Ok(())
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

/// Why a request could not be read.
enum Outcome {
    /// Answer with an error response.
    Reject(String),
    /// Close the connection without an answer.
    Drop,
}

/// UID of the process on the other end of `stream` (`SO_PEERCRED`).
pub fn peer_uid(stream: &UnixStream) -> Option<u32> {
    peer_credentials(stream).map(|credentials| credentials.uid)
}

pub(crate) fn peer_credentials(stream: &UnixStream) -> Option<libc::ucred> {
    let mut credentials = libc::ucred {
        pid: 0,
        uid: 0,
        gid: 0,
    };
    let mut length = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    // SAFETY: the buffer and its length describe a `ucred`, and the socket
    // descriptor is valid for the duration of the call.
    let result = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            (&mut credentials as *mut libc::ucred).cast(),
            &mut length,
        )
    };
    (result == 0).then_some(credentials)
}

fn read_request(mut stream: &UnixStream) -> std::result::Result<Value, Outcome> {
    let size = || Outcome::Reject("invalid management request size".to_owned());
    let deadline = Instant::now() + IO_TIMEOUT;
    let mut payload = Vec::new();
    // One byte more than the limit, so that an oversized line is noticed
    // without leaving unread data behind.
    let mut chunk = [0u8; REQUEST_LIMIT + 1];
    while !payload.ends_with(b"\n") {
        let remaining = deadline
            .checked_duration_since(Instant::now())
            .filter(|remaining| !remaining.is_zero())
            .ok_or(Outcome::Drop)?;
        stream
            .set_read_timeout(Some(remaining))
            .map_err(|_| Outcome::Drop)?;
        let wanted = REQUEST_LIMIT + 1 - payload.len();
        match stream.read(&mut chunk[..wanted]) {
            Ok(0) => return Err(size()),
            Ok(count) => payload.extend_from_slice(&chunk[..count]),
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            Err(_) => return Err(Outcome::Drop),
        }
        if payload.len() > REQUEST_LIMIT {
            return Err(size());
        }
    }
    serde_json::from_slice(&payload)
        .map_err(|_| Outcome::Reject("invalid management request".to_owned()))
}

fn error_response(message: &str) -> Value {
    json!({ "status": 1, "error": message })
}

/// Serialise a response, replacing one that exceeds the wire limit.
pub fn bounded_response(response: &Value) -> String {
    let mut text = canonical_json(response) + "\n";
    if text.len() > RESPONSE_LIMIT {
        text = canonical_json(&error_response("management response exceeds size limit")) + "\n";
    }
    text
}

fn write_response(mut stream: &UnixStream, response: &Value) -> io::Result<()> {
    stream.set_write_timeout(Some(IO_TIMEOUT))?;
    stream.write_all(bounded_response(response).as_bytes())?;
    stream.flush()
}

/// SIGINT or SIGTERM seen while the server was idle (0 for none).
static STOP_SIGNAL: AtomicI32 = AtomicI32::new(0);
static STOP: AtomicBool = AtomicBool::new(false);

extern "C" fn record_stop(signal: libc::c_int) {
    STOP_SIGNAL.store(signal, Ordering::SeqCst);
    STOP.store(true, Ordering::SeqCst);
}

/// Restores the signal dispositions replaced by [`StopHandlers::install`].
struct StopHandlers {
    term: libc::sigaction,
    int: libc::sigaction,
}

impl StopHandlers {
    fn install() -> io::Result<Self> {
        STOP.store(false, Ordering::SeqCst);
        STOP_SIGNAL.store(0, Ordering::SeqCst);
        // SAFETY: sigaction with zero-initialised structures; the handler only
        // stores into atomics, which is async-signal-safe.
        unsafe {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = record_stop as *const () as usize;
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

impl Drop for StopHandlers {
    fn drop(&mut self) {
        // SAFETY: restores the dispositions saved by `install`.
        unsafe {
            libc::sigaction(libc::SIGTERM, &self.term, std::ptr::null_mut());
            libc::sigaction(libc::SIGINT, &self.int, std::ptr::null_mut());
        }
    }
}

/// Why [`serve`] returned without serving.
#[derive(Debug, PartialEq, Eq)]
pub enum Served {
    /// Another server holds the lock; nothing was bound.
    AlreadyRunning,
}

/// Bind `socket` and serve until SIGINT or SIGTERM.
///
/// A normal stop is reported as [`Error::Interrupted`] or
/// [`Error::Terminated`] so that the process exits with the conventional code;
/// `Ok` means that another server already owns the runtime.
pub fn serve(runtime: &Path, socket: &Path, runner: &mut dyn Runner) -> Result<Served> {
    let Some(server) = Server::bind(runtime, socket)? else {
        return Ok(Served::AlreadyRunning);
    };
    let _handlers = StopHandlers::install()?;
    if cfg!(target_os = "android")
        && let Err(error) = crate::outer_remote::start(&server.runtime)
    {
        eprintln!("nixpp: could not start the native outer socket: {error:#}");
    }
    server.run(runner, &STOP)?;
    match STOP_SIGNAL.load(Ordering::SeqCst) {
        libc::SIGINT => Err(Error::Interrupted),
        _ => Err(Error::Terminated),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{Fixture, MockRunner, Outcome as Scripted};
    use std::os::unix::fs::symlink;
    use std::thread;

    struct Sockets {
        _dir: tempfile::TempDir,
        directory: PathBuf,
    }

    impl Sockets {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let directory = fs::canonicalize(dir.path()).unwrap().join("sock");
            fs::create_dir(&directory).unwrap();
            fs::set_permissions(&directory, fs::Permissions::from_mode(0o700)).unwrap();
            Self {
                _dir: dir,
                directory,
            }
        }

        fn path(&self) -> PathBuf {
            self.directory.join("nixpp.sock")
        }
    }

    fn exchange(path: &Path, request: &[u8]) -> Vec<u8> {
        let mut stream = UnixStream::connect(path).unwrap();
        stream.write_all(request).unwrap();
        let mut reply = Vec::new();
        stream.read_to_end(&mut reply).unwrap();
        reply
    }

    fn reply(path: &Path, request: &[u8]) -> Value {
        serde_json::from_slice(&exchange(path, request)).unwrap()
    }

    fn serve_with<T>(
        server: &Server,
        runner: &mut MockRunner,
        client: impl FnOnce(&Path) -> T,
    ) -> (T, Result<()>) {
        let stop = AtomicBool::new(false);
        thread::scope(|scope| {
            let handle = scope.spawn(|| server.run(runner, &stop));
            let value = client(server.path());
            stop.store(true, Ordering::SeqCst);
            (value, handle.join().unwrap())
        })
    }

    #[test]
    fn answers_list_generations_over_a_private_socket() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let server = Server::bind(&fixture.runtime, &sockets.path())
            .unwrap()
            .unwrap();
        let mode = fs::symlink_metadata(sockets.path()).unwrap().mode() & 0o777;
        assert_eq!(mode, 0o600);
        let mut runner = MockRunner::returning(0);
        let (response, result) = serve_with(&server, &mut runner, |path| {
            reply(path, b"{\"command\": \"list-generations\"}\n")
        });
        result.unwrap();
        assert_eq!(response["status"], 0);
        assert_eq!(response["generations"][0]["generation"], fixture.name);
        assert!(runner.calls.is_empty());
        drop(server);
        assert!(!sockets.path().exists());
    }

    #[test]
    fn second_server_yields_and_leaves_the_socket() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let first = Server::bind(&fixture.runtime, &sockets.path())
            .unwrap()
            .unwrap();
        let other = sockets.directory.join("other.sock");
        assert!(Server::bind(&fixture.runtime, &other).unwrap().is_none());
        assert!(!other.exists());
        assert!(sockets.path().exists());
        drop(first);
        assert!(Server::bind(&fixture.runtime, &other).unwrap().is_some());
    }

    #[test]
    fn stale_socket_is_replaced() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        drop(UnixListener::bind(sockets.path()).unwrap());
        assert!(sockets.path().exists());
        assert!(
            Server::bind(&fixture.runtime, &sockets.path())
                .unwrap()
                .is_some()
        );
    }

    #[test]
    fn non_socket_is_refused() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        fs::write(sockets.path(), "precious").unwrap();
        let error = Server::bind(&fixture.runtime, &sockets.path()).unwrap_err();
        assert!(error.to_string().contains("refusing"), "{error}");
        assert_eq!(fs::read_to_string(sockets.path()).unwrap(), "precious");
    }

    #[test]
    fn symlink_at_the_socket_path_is_refused() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        symlink("/nonexistent", sockets.path()).unwrap();
        assert!(Server::bind(&fixture.runtime, &sockets.path()).is_err());
    }

    #[test]
    fn shared_directory_is_refused() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        for mode in [0o777, 0o770, 0o707] {
            fs::set_permissions(&sockets.directory, fs::Permissions::from_mode(mode)).unwrap();
            let error = Server::bind(&fixture.runtime, &sockets.path()).unwrap_err();
            assert!(
                error.to_string().contains("non-writable"),
                "{mode:o}: {error}"
            );
        }
        assert!(!sockets.path().exists());
    }

    #[test]
    fn symlinked_socket_directory_is_refused() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let link = sockets.directory.with_file_name("link");
        symlink(&sockets.directory, &link).unwrap();
        assert!(Server::bind(&fixture.runtime, &link.join("nixpp.sock")).is_err());
    }

    #[test]
    fn oversized_request_is_rejected() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let server = Server::bind(&fixture.runtime, &sockets.path())
            .unwrap()
            .unwrap();
        let mut runner = MockRunner::returning(0);
        let (response, result) = serve_with(&server, &mut runner, |path| {
            reply(path, &vec![b'x'; REQUEST_LIMIT + 1])
        });
        result.unwrap();
        assert_eq!(response["status"], 1);
        assert_eq!(response["error"], "invalid management request size");
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn request_that_ends_without_newline_is_rejected() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let server = Server::bind(&fixture.runtime, &sockets.path())
            .unwrap()
            .unwrap();
        let mut runner = MockRunner::returning(0);
        let (response, result) = serve_with(&server, &mut runner, |path| {
            let mut stream = UnixStream::connect(path).unwrap();
            stream.write_all(b"{\"command\": \"recover\"}").unwrap();
            stream.shutdown(std::net::Shutdown::Write).unwrap();
            let mut reply = Vec::new();
            stream.read_to_end(&mut reply).unwrap();
            serde_json::from_slice::<Value>(&reply).unwrap()
        });
        result.unwrap();
        assert_eq!(response["error"], "invalid management request size");
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn malformed_and_disallowed_requests_get_an_error_status() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let server = Server::bind(&fixture.runtime, &sockets.path())
            .unwrap()
            .unwrap();
        let mut runner = MockRunner::returning(0);
        let (responses, result) = serve_with(&server, &mut runner, |path| {
            [
                &b"not json\n"[..],
                b"[]\n",
                b"{\"command\": \"exec\"}\n",
                b"{\"command\": \"switch\", \"candidate\": \"../escape\"}\n",
            ]
            .map(|request| reply(path, request))
        });
        result.unwrap();
        for response in responses {
            assert_eq!(response["status"], 1, "{response}");
            assert!(response["error"].is_string());
        }
        assert!(runner.calls.is_empty());
    }

    #[test]
    fn controller_failures_are_reported_not_fatal() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let server = Server::bind(&fixture.runtime, &sockets.path())
            .unwrap()
            .unwrap();
        let mut runner = MockRunner::returning(0);
        let (responses, result) = serve_with(&server, &mut runner, |path| {
            let recover = reply(path, b"{\"command\": \"recover\"}\n");
            let list = reply(path, b"{\"command\": \"list-generations\"}\n");
            (recover, list)
        });
        result.unwrap();
        assert_eq!(responses.0["status"], 1);
        assert!(
            responses.0["error"]
                .as_str()
                .unwrap()
                .contains("no unfinished")
        );
        assert_eq!(responses.1["status"], 0);
    }

    #[test]
    fn interrupted_command_stops_the_server_without_a_reply() {
        let fixture = Fixture::new();
        let sockets = Sockets::new();
        let server = Server::bind(&fixture.runtime, &sockets.path())
            .unwrap()
            .unwrap();
        let mut runner = MockRunner::script(vec![Scripted::Terminated]);
        let request = format!(
            "{{\"command\": \"check\", \"candidate\": \"{}\"}}\n",
            fixture.name
        );
        let (bytes, result) = serve_with(&server, &mut runner, |path| {
            exchange(path, request.as_bytes())
        });
        assert!(bytes.is_empty());
        assert!(matches!(result, Err(Error::Terminated)));
    }

    #[test]
    fn peer_uid_is_our_own() {
        let (first, second) = UnixStream::pair().unwrap();
        assert_eq!(peer_uid(&first), Some(own_uid()));
        assert_eq!(peer_uid(&second), Some(own_uid()));
    }

    #[test]
    fn oversized_responses_are_replaced_by_an_error() {
        let small = json!({"status": 0, "generations": []});
        assert_eq!(
            bounded_response(&small),
            "{\"generations\": [], \"status\": 0}\n"
        );
        let huge = json!({"status": 0, "padding": "x".repeat(RESPONSE_LIMIT)});
        let text = bounded_response(&huge);
        assert!(text.len() < 128);
        let value: Value = serde_json::from_str(&text).unwrap();
        assert_eq!(value["status"], 1);
        assert_eq!(value["error"], "management response exceeds size limit");
    }
}

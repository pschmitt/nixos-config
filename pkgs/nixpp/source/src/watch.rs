//! inotify watches, so long-running native processes block on changes
//! instead of polling for them.

use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

/// Watches a directory and reports changes to some of its entries.
pub(crate) struct Watch {
    fd: OwnedFd,
    names: Vec<Vec<u8>>,
}

impl Watch {
    /// Watch `directory` for `names` being created, replaced, written,
    /// moved or removed; None when inotify is unavailable.
    pub(crate) fn new(directory: &Path, names: Vec<Vec<u8>>) -> Option<Self> {
        // SAFETY: inotify_init1 takes flags and returns a new descriptor.
        let fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
        if fd < 0 {
            return None;
        }
        // SAFETY: the kernel just returned this descriptor to us.
        let fd = unsafe { OwnedFd::from_raw_fd(fd) };
        let directory = std::ffi::CString::new(directory.as_os_str().as_bytes()).ok()?;
        let mask = libc::IN_MOVED_TO
            | libc::IN_MOVED_FROM
            | libc::IN_CREATE
            | libc::IN_DELETE
            | libc::IN_CLOSE_WRITE
            | libc::IN_ATTRIB;
        // SAFETY: a valid inotify descriptor and a NUL-terminated path.
        let watch = unsafe { libc::inotify_add_watch(fd.as_raw_fd(), directory.as_ptr(), mask) };
        (watch >= 0).then_some(Self { fd, names })
    }

    /// The descriptor to poll for readability.
    pub(crate) fn fd(&self) -> &OwnedFd {
        &self.fd
    }

    /// Reads the pending events; whether one concerned a watched name.
    pub(crate) fn drain(&mut self) -> bool {
        let mut buffer = [0_u8; 4096];
        let mut matched = false;
        loop {
            // SAFETY: reading into a buffer of the given length.
            let read = unsafe {
                libc::read(
                    self.fd.as_raw_fd(),
                    buffer.as_mut_ptr().cast(),
                    buffer.len(),
                )
            };
            let Ok(read) = usize::try_from(read) else {
                return matched;
            };
            if read == 0 {
                return matched;
            }
            matched |= event_names(&buffer[..read])
                .any(|name| self.names.iter().any(|watched| watched.as_slice() == name));
        }
    }
}

/// The names in a buffer of inotify events.
fn event_names(mut events: &[u8]) -> impl Iterator<Item = &[u8]> {
    const HEADER: usize = std::mem::size_of::<libc::inotify_event>();
    std::iter::from_fn(move || {
        if events.len() < HEADER {
            return None;
        }
        let length = u32::from_ne_bytes(events[HEADER - 4..HEADER].try_into().ok()?) as usize;
        let name = events.get(HEADER..HEADER + length)?;
        events = &events[HEADER + length..];
        let end = name
            .iter()
            .position(|byte| *byte == 0)
            .unwrap_or(name.len());
        Some(&name[..end])
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(name: &str, padded: usize) -> Vec<u8> {
        let mut bytes = vec![0_u8; std::mem::size_of::<libc::inotify_event>() - 4];
        bytes.extend_from_slice(&(padded as u32).to_ne_bytes());
        let mut name = name.as_bytes().to_vec();
        name.resize(padded, 0);
        bytes.extend(name);
        bytes
    }

    #[test]
    fn reads_the_names_of_inotify_events() {
        let mut buffer = event("nixpp", 16);
        buffer.extend(event("network.json", 16));
        buffer.extend(event("", 0));
        let names: Vec<&[u8]> = event_names(&buffer).collect();
        assert_eq!(names, [&b"nixpp"[..], b"network.json", b""]);
    }

    #[test]
    fn reports_only_watched_names() {
        let directory = tempfile::tempdir().unwrap();
        let mut watch = Watch::new(directory.path(), vec![b"current-system".to_vec()]).unwrap();
        std::fs::write(directory.path().join("network.json"), "{}").unwrap();
        assert!(!watch.drain());
        std::fs::write(directory.path().join(".current-system.tmp"), "x\n").unwrap();
        std::fs::rename(
            directory.path().join(".current-system.tmp"),
            directory.path().join("current-system"),
        )
        .unwrap();
        assert!(watch.drain());
        assert!(!watch.drain());
    }
}

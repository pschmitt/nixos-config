//! Filesystem helpers: atomic state files, bounded reads, locks, canonical JSON.

use crate::error::{Error, Result};
use serde::Serialize;
use serde_json::Value;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

/// Largest accepted state, manifest or journal file.
pub const STATE_LIMIT: u64 = 65536;

/// Render a path as UTF-8; command lines and JSON need valid text.
pub fn path_str(path: &Path) -> Result<String> {
    path.to_str()
        .map(str::to_owned)
        .ok_or_else(|| Error::invalid(format!("path is not valid UTF-8: {}", path.display())))
}

/// `Path::is_symlink` without following; missing paths count as no symlink.
pub fn is_symlink(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_symlink())
        .unwrap_or(false)
}

/// Size of a regular, non-symlink file, or `None` for anything else.
pub fn regular_file_size(path: &Path) -> Option<u64> {
    let metadata = fs::symlink_metadata(path).ok()?;
    metadata.file_type().is_file().then_some(metadata.len())
}

/// Read at most `limit` bytes; longer content is an error.
pub fn read_bounded(path: &Path, limit: u64) -> Result<Vec<u8>> {
    let mut data = Vec::new();
    File::open(path)?.take(limit + 1).read_to_end(&mut data)?;
    if data.len() as u64 > limit {
        return Err(Error::invalid("file exceeds the size limit"));
    }
    Ok(data)
}

fn sibling_with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(suffix);
    path.with_file_name(name)
}

/// Write `path.new` (0600, no symlinks, fsync), rename it over `path` and
/// fsync the parent directory.
pub fn atomic_write(path: &Path, text: &str) -> Result<()> {
    let temporary = sibling_with_suffix(path, ".new");
    if is_symlink(&temporary) || is_symlink(path) {
        return Err(Error::invalid("state files must not be symlinks"));
    }
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .custom_flags(libc::O_NOFOLLOW)
        .mode(0o600)
        .open(&temporary)?;
    if !file.metadata()?.file_type().is_file() {
        return Err(Error::invalid("state files must be regular files"));
    }
    file.write_all(text.as_bytes())?;
    file.flush()?;
    file.sync_all()?;
    drop(file);
    fs::rename(&temporary, path)?;
    let parent = match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    };
    File::open(parent)?.sync_all()?;
    Ok(())
}

/// Read a JSON-object state file from the runtime directory.
///
/// Returns `None` when the file does not exist. Symlinks, special files, files
/// above [`STATE_LIMIT`] and non-object JSON are rejected.
pub fn read_state_value(runtime: &Path, filename: &str) -> Result<Option<Value>> {
    let path = runtime.join(filename);
    match fs::symlink_metadata(&path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
        Ok(metadata) => {
            if metadata.file_type().is_symlink() {
                return Err(Error::invalid("state files must not be symlinks"));
            }
            if !metadata.file_type().is_file() || metadata.len() > STATE_LIMIT {
                return Err(Error::invalid(
                    "state file is not regular or exceeds size limit",
                ));
            }
        }
    }
    let value: Value = serde_json::from_slice(&read_bounded(&path, STATE_LIMIT)?)?;
    if !value.is_object() {
        return Err(Error::invalid("invalid system state"));
    }
    Ok(Some(value))
}

/// Serialize with sorted keys, Python-style separators and ASCII-only strings,
/// byte-compatible with `json.dumps(value, sort_keys=True)`.
pub fn canonical_json(value: &Value) -> String {
    let mut out = String::new();
    write_canonical(value, &mut out);
    out
}

/// [`canonical_json`] for any serializable value.
pub fn to_canonical<T: Serialize>(value: &T) -> Result<String> {
    Ok(canonical_json(&serde_json::to_value(value)?))
}

fn write_canonical(value: &Value, out: &mut String) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(flag) => out.push_str(if *flag { "true" } else { "false" }),
        Value::Number(number) => out.push_str(&number.to_string()),
        Value::String(text) => write_string(text, out),
        Value::Array(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push_str(", ");
                }
                write_canonical(item, out);
            }
            out.push(']');
        }
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            out.push('{');
            for (index, key) in keys.into_iter().enumerate() {
                if index > 0 {
                    out.push_str(", ");
                }
                write_string(key, out);
                out.push_str(": ");
                write_canonical(&map[key], out);
            }
            out.push('}');
        }
    }
}

fn write_string(text: &str, out: &mut String) {
    out.push('"');
    for character in text.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            character if (character as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", character as u32));
            }
            character if character.is_ascii() => out.push(character),
            character => {
                let mut units = [0u16; 2];
                for unit in character.encode_utf16(&mut units) {
                    out.push_str(&format!("\\u{unit:04x}"));
                }
            }
        }
    }
    out.push('"');
}

/// An exclusive advisory lock held for as long as the value lives.
#[derive(Debug)]
pub struct FileLock {
    file: File,
}

impl FileLock {
    /// Take the lock without blocking. `Ok(None)` means another holder has it.
    pub fn try_acquire(path: &Path) -> Result<Option<Self>> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .custom_flags(libc::O_NOFOLLOW)
            .mode(0o600)
            .open(path)?;
        // SAFETY: the descriptor is owned by `file` and valid for this call.
        let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
        if result == 0 {
            return Ok(Some(Self { file }));
        }
        let error = io::Error::last_os_error();
        if error.kind() == io::ErrorKind::WouldBlock {
            Ok(None)
        } else {
            Err(error.into())
        }
    }

    /// Take the lock or fail with an `Io(WouldBlock)` error.
    pub fn acquire(path: &Path) -> Result<Self> {
        Self::try_acquire(path)?.ok_or_else(|| {
            Error::Io(io::Error::new(
                io::ErrorKind::WouldBlock,
                "another controller operation holds the lock (resource temporarily unavailable)",
            ))
        })
    }
}

impl Drop for FileLock {
    fn drop(&mut self) {
        // SAFETY: the file still owns the descriptor. Explicitly unlock the
        // open file description in case a concurrent fork inherited it and
        // has not yet closed close-on-exec descriptors.
        unsafe { libc::flock(self.file.as_raw_fd(), libc::LOCK_UN) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::os::unix::fs::{PermissionsExt, symlink};

    #[test]
    fn dropping_a_lock_releases_an_inherited_file_description() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("lock");
        let lock = FileLock::acquire(&path).unwrap();
        let _inherited = lock.file.try_clone().unwrap();
        assert!(FileLock::try_acquire(&path).unwrap().is_none());
        drop(lock);
        FileLock::acquire(&path).unwrap();
    }

    #[test]
    fn canonical_json_matches_python_sort_keys() {
        let value = json!({"b": [1, true, null], "a": {"z": "x\"y", "é": "\u{1F600}\n"}});
        assert_eq!(
            canonical_json(&value),
            r#"{"a": {"z": "x\"y", "\u00e9": "\ud83d\ude00\n"}, "b": [1, true, null]}"#
        );
    }

    #[test]
    fn atomic_write_is_private_and_replaces() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("state");
        atomic_write(&path, "one\n").unwrap();
        atomic_write(&path, "two\n").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "two\n");
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(!dir.path().join("state.new").exists());
    }

    #[test]
    fn atomic_write_rejects_symlinks() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("target");
        fs::write(&target, "keep").unwrap();
        let path = dir.path().join("state");
        symlink(&target, &path).unwrap();
        assert!(atomic_write(&path, "x").is_err());
        fs::remove_file(&path).unwrap();
        symlink(&target, dir.path().join("state.new")).unwrap();
        assert!(atomic_write(&path, "x").is_err());
        assert_eq!(fs::read_to_string(&target).unwrap(), "keep");
    }

    #[test]
    fn state_reads_are_bounded_and_typed() {
        let dir = tempfile::tempdir().unwrap();
        assert!(read_state_value(dir.path(), "missing").unwrap().is_none());
        fs::write(dir.path().join("list"), "[1]").unwrap();
        assert!(read_state_value(dir.path(), "list").is_err());
        fs::write(
            dir.path().join("big"),
            format!("{{\"a\": \"{}\"}}", "x".repeat(70000)),
        )
        .unwrap();
        assert!(read_state_value(dir.path(), "big").is_err());
        fs::write(dir.path().join("ok"), "{\"a\": 1}").unwrap();
        assert_eq!(read_state_value(dir.path(), "ok").unwrap().unwrap()["a"], 1);
        symlink(dir.path().join("ok"), dir.path().join("link")).unwrap();
        assert!(read_state_value(dir.path(), "link").is_err());
    }

    #[test]
    fn lock_is_exclusive() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("lock");
        let first = FileLock::acquire(&path).unwrap();
        assert!(FileLock::try_acquire(&path).unwrap().is_none());
        assert!(FileLock::acquire(&path).unwrap_err().is_would_block());
        drop(first);
        assert!(FileLock::try_acquire(&path).unwrap().is_some());
    }
}

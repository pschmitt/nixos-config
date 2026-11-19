//! A terminal's outer server switches to a replaced nixpp in place: same
//! process, same socket, same guest child.

use std::fs;
use std::os::unix::fs::MetadataExt;
use std::process::Command;
use std::time::{Duration, Instant};

fn wait_for(what: &str, mut condition: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(20);
    while !condition() {
        assert!(Instant::now() < deadline, "timed out waiting for {what}");
        std::thread::sleep(Duration::from_millis(50));
    }
}

/// Whether the process re-executed into the handover entry point; its
/// command line shows that even under qemu-user emulation, where
/// /proc/PID/exe is the interpreter.
fn resumed(pid: u32) -> bool {
    fs::read(format!("/proc/{pid}/cmdline")).is_ok_and(|cmdline| {
        cmdline
            .split(|byte| *byte == 0)
            .any(|arg| arg == b"__outer-resume")
    })
}

fn running_inode(pid: u32) -> Option<u64> {
    fs::metadata(format!("/proc/{pid}/exe"))
        .ok()
        .map(|found| found.ino())
}

#[test]
fn outer_server_reexecs_into_a_replaced_nixpp() {
    let root = tempfile::tempdir().unwrap();
    let bin = root.path().join("nixpp");
    fs::copy(env!("CARGO_BIN_EXE_nixpp"), &bin).unwrap();
    let tmp = root.path().join("t");
    fs::create_dir(&tmp).unwrap();
    let release = root.path().join("release");
    let guest = format!(
        "while [ ! -e {} ]; do sleep 0.1; done; exit 7",
        release.display()
    );
    let mut server = Command::new(&bin)
        .args(["__outer-supervise", "--", "/bin/sh", "-c", &guest])
        .env("TMPDIR", &tmp)
        .spawn()
        .unwrap();
    let pid = server.id();
    let socket = tmp.join(format!("nixpp-outer-{pid}")).join("s");
    wait_for("the outer socket", || socket.exists());
    let before = running_inode(pid).unwrap();
    // Under emulation /proc/PID/exe names the interpreter, not nixpp.
    let native = before == fs::metadata(&bin).unwrap().ino();

    // Idle, the server blocks: the old 20 ms accept loop woke 50 times a second.
    let switches = || -> u64 {
        fs::read_to_string(format!("/proc/{pid}/status"))
            .unwrap()
            .lines()
            .find_map(|line| line.strip_prefix("voluntary_ctxt_switches:"))
            .unwrap()
            .trim()
            .parse()
            .unwrap()
    };
    let idle = switches();
    std::thread::sleep(Duration::from_secs(1));
    let woke = switches() - idle;
    assert!(
        woke < 5,
        "an idle outer server woke {woke} times in a second"
    );

    // An update installs a new file over the old one.
    let staged = root.path().join("nixpp.new");
    fs::copy(env!("CARGO_BIN_EXE_nixpp"), &staged).unwrap();
    fs::rename(&staged, &bin).unwrap();
    let after = fs::metadata(&bin).unwrap().ino();
    assert_ne!(before, after);
    wait_for("the re-exec", || resumed(pid));
    if native {
        assert_eq!(running_inode(pid), Some(after), "the new file runs");
    }

    assert!(socket.exists(), "the socket survives the re-exec");
    std::os::unix::net::UnixStream::connect(&socket).expect("the new code serves the socket");
    fs::write(&release, "").unwrap();
    let status = server.wait().unwrap();
    assert_eq!(
        status.code(),
        Some(7),
        "the guest's exit code still comes through"
    );
    assert!(!socket.exists(), "the socket is removed at the end");
}

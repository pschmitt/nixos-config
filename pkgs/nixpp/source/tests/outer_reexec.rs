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

    // An update installs a new file over the old one.
    let staged = root.path().join("nixpp.new");
    fs::copy(env!("CARGO_BIN_EXE_nixpp"), &staged).unwrap();
    fs::rename(&staged, &bin).unwrap();
    let after = fs::metadata(&bin).unwrap().ino();
    assert_ne!(before, after);
    wait_for("the re-exec", || running_inode(pid) == Some(after));

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

//! Which app process's cgroup the daemon runs in.
//!
//! Android gives every app process its own cgroup (`/apps/uid_N/pid_P`) and
//! freezes it while that process is cached. Children inherit the cgroup, so a
//! daemon started from a secondary process (`dev.pschmitt.termux:background`,
//! the Tasker receiver) froze with it: its sessions, switches and checks
//! stalled for minutes. Only the main app process keeps a foreground service.

use std::path::Path;

/// The name of the secondary app process whose cgroup holds this process,
/// or None for the main process or an unknown layout.
pub(crate) fn secondary_owner() -> Option<String> {
    let cgroup = std::fs::read_to_string("/proc/self/cgroup").ok()?;
    owner_of(&cgroup, |pid| {
        let raw = std::fs::read(Path::new("/proc").join(pid).join("cmdline")).ok()?;
        let name = raw.split(|byte| *byte == 0).next()?;
        String::from_utf8(name.to_vec()).ok()
    })
    .filter(|name| name.contains(':'))
}

/// The process name of the cgroup's owning app process, from the unified
/// (`0::`) line of /proc/self/cgroup.
fn owner_of(cgroup: &str, name_of: impl Fn(&str) -> Option<String>) -> Option<String> {
    let path = cgroup.lines().find_map(|line| line.strip_prefix("0::"))?;
    let pid = path.rsplit('/').next()?.strip_prefix("pid_")?;
    if pid.is_empty() || !pid.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    name_of(pid)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CGROUP: &str = "3:cpuset:/background\n2:cpu:/\n0::/apps/uid_10459/pid_21173\n";

    #[test]
    fn names_the_owning_app_process() {
        let owner = owner_of(CGROUP, |pid| {
            assert_eq!(pid, "21173");
            Some("dev.pschmitt.termux:background".to_owned())
        });
        assert_eq!(owner.as_deref(), Some("dev.pschmitt.termux:background"));
    }

    #[test]
    fn unknown_layouts_have_no_owner() {
        let never = |_: &str| -> Option<String> { panic!("no pid to look up") };
        assert_eq!(owner_of("0::/user.slice/session-1.scope\n", never), None);
        assert_eq!(owner_of("1:blkio:/\n", never), None);
        assert_eq!(owner_of("0::/apps/uid_10459/pid_x\n", never), None);
    }
}

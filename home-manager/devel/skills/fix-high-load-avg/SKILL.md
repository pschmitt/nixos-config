---
name: fix-high-load-avg
description: Diagnose unexpectedly high load on Linux hosts using bounded process, CPU, I/O, and service checks. Use especially for fnuc; preserve its mission-critical Home Assistant VM.
---

# Host Load Triage

Use live measurements to identify what is driving high load on a Linux host.
Read the repository `AGENTS.md` before making configuration or service changes.
For Monit alerts, also follow the `monit` skill.

## Keep discovery bounded

Start with load, CPU, process, and service state. Do not begin with recursive
filesystem searches. In particular, do not run broad `find`, `bfs`, or
recursive `grep` commands over `/`, a home directory, `/nix/store`, generated
trees, or network/FUSE mounts. A traversal of `/mnt/ha` can stall in SSHFS and
add load to the Home Assistant VM itself.

- Prefer `ps`, `top`, `top -H`, `vmstat`, `pidstat`, `systemd-cgtop`, and
  `/proc` counters to find the active CPU, runnable, and blocked tasks.
- Compare at least two short samples before calling a process runaway. `ps`
  `%CPU` is averaged over the process lifetime and can misrepresent current
  activity; use a sampled `top`/`pidstat` view or counter deltas.
- Check both load average and current CPU utilization. Load includes runnable
  and uninterruptible tasks, so it is not a CPU percentage. Inspect `R` and `D`
  states, `procs_running`, `procs_blocked`, and I/O wait.
- Search only a specific, known directory or file after evidence points there.
  Exclude generated/cache trees and put a timeout around filesystem reads that
  can hang, especially on SSHFS or other remote mounts. Do not retry a timed
  out broad search unchanged.

## Inspect the host and identify the cause

For remote hosts, use the configured SSH alias, non-interactive SSH with a
connection timeout, and `sudo -n`. Capture the host and timestamp. Begin with
concise samples such as:

```sh
uptime
cat /proc/loadavg
grep -E 'procs_running|procs_blocked' /proc/stat
top -b -n 2 -d 2 -w 140
ps -eo pid,ppid,user,state,pcpu,pmem,etime,comm,args --sort=-pcpu | head -25
```

Follow the evidence: inspect the specific PID's threads, parent, cgroup,
systemd unit, logs, I/O, or owning VM/container. For a VM, compare hypervisor
CPU-time deltas with the guest's own load and process/container samples. Check
the current endpoint from the live host configuration or monitoring check;
do not mistake a bridge address for the guest address.

## Preserve fnuc's Home Assistant VM

The Home Assistant VM on `fnuc` is mission critical and must remain available
during load triage. Do not stop, shut down, reboot, pause, or kill the VM/QEMU
process to reduce load or as a diagnostic shortcut. Do not present shutting
down the VM as the answer to a high-load report.

If the VM is implicated, inspect the guest and identify the specific process,
container, or add-on responsible. Use read-only guest/process/container
inspection first. Any proposed mitigation must preserve Home Assistant service
availability and target only the demonstrated cause. If a safe, narrow remedy
is not clear, report the evidence and a plan that keeps the VM running. Any
action that would interrupt Home Assistant requires an explicit user request
and a clear impact/recovery plan.

## Report

State the sampled load and CPU utilization, the active cause(s), whether a
suspect is still running, and the exact validation performed. Distinguish a
short-lived process or stale load average from current sustained CPU or I/O
pressure. Say what action was taken; make no changes when the cause is unclear
or a proposed fix would threaten Home Assistant availability.

# Monit triage runbook

## 1. Establish scope and inventory

Read the repository `AGENTS.md` before making changes. Take the `rofl-*` and
`oci-*` hosts from the host table in `flake.nix` (the hosts under `hosts/`, minus
`test-delete-*`), then add `fnuc`, `turris`, and `brkn-ap`; check the local SSH
configuration for aliases. Do not rely on a remembered host list. Use SSH aliases
where available.

Check hosts in parallel when possible. Use non-interactive SSH with a connection
timeout and `sudo -n`; never hang waiting for a password. An access failure is an
incident to report, not a reason to guess.

## 2. Inspect live Monit state

On each host, start with concise output:

```sh
sudo -n monit summary
sudo -n journalctl -u monit --since "24 hours ago" --no-pager
```

Use `monit status` for the full detail of only failed or suspicious checks. Correlate
each alert with its live service, container, socket, filesystem, or systemd unit.
Useful read-only checks include:

- `systemctl status <unit> --no-pager --full`
- `systemctl show <unit> -p ActiveState -p SubState -p Result -p NRestarts`
- `systemctl --failed --no-pager`
- `docker ps -a`, `docker inspect`, and bounded container logs when Docker is involved
- `ss -ltnp` and a local `curl` or protocol check for port or HTTP alerts
- `journalctl -u <unit> --since "2 hours ago" --no-pager`
- `df -h` and `df -ih` for filesystem alerts

Do not rely on an earlier conversation's status: alerts can clear or change while
investigating. Capture timestamps and current status in the report.

## 3. Classify and act

Fix immediately when the cause is clear, the action is reversible and low risk, and
the service is expected to run. Do not delete data, alter formats, reboot, change
secrets, or affect unrelated services. Examples include restarting one crashed
stateless service after checking its logs, starting an unexpectedly stopped service
with an unambiguous unit, or clearing a stale failed state after confirming the
underlying service is healthy. Validate the service and Monit check afterward.

### NixOS upgrade activation retry

When `nixos-upgrade.service` is failed with `status=4/NOPERMISSION` and its logs show
root user activation failing because `/run/user/0/bus` is unavailable or the D-Bus
connection closed, restart that unit once. This is the configured recovery path for
this specific failure and is authorized despite the general restriction on deployment
actions. Do not restart the unit if it is already running, and do not retry if this
restart fails.

Before restarting, confirm the exact D-Bus activation error and record the current
generation:

```sh
readlink -f /run/current-system
sudo -n systemctl restart nixos-upgrade.service
```

If activation disconnects SSH, reconnect and verify. Check the active generation,
unit result, failed units, and affected Monit checks:

```sh
readlink -f /run/current-system
sudo -n systemctl show nixos-upgrade.service -p ActiveState -p SubState -p Result -p ExecMainStatus
sudo -n systemctl --failed --no-pager
sudo -n monit status "systemd timers"
sudo -n monit status "systemd services"
```

A successful oneshot may be `inactive` afterward. Require a successful unit result,
no failed upgrade unit, and healthy affected Monit checks. Wait for checks that are
`Initializing` or `Waiting` to take their next sample. If the restart fails, capture
the new logs, report the failure, and stop rather than looping.

For other Nix configuration or deployment failures, diagnose and report a plan rather
than improvising a deployment. Also do not improvise fixes for data migrations,
schema or storage-format errors, corruption, cleanup/deletion, reboot-required alerts,
kernel changes, disk pressure, filesystem faults, suspected hardware/storage problems,
repeated crash loops, authentication or secret failures, network reachability problems,
package/image rollbacks or upgrades, firewall/network changes, or monitoring-policy
changes.

Any plan for unresolved incidents must state the evidence, likely cause, proposed
steps, backup or rollback needs, expected service impact, and validation checks. If
execution needs user approval or an external choice, stop after the plan.

## 4. Reset stale Monit checks

When the live service or endpoint is healthy but Monit retains a stale `Timeout`,
`Status failed`, or similar state, reset only that check. Confirm the underlying check
independently first; do not use this to hide a current failure.

Run these commands in order so a reload does not undo the re-monitor request:

```sh
sudo -n monit unmonitor <check-name>
sudo -n monit reload
sudo -n monit monitor <check-name>
sudo -n monit status <check-name>
```

The status may be `Initializing` or `Waiting` until its next scheduled sample,
especially for checks using `every N cycles`. Verify the underlying service and
`monitoring status Monitored` with status `OK`. If the check remains failed, diagnose
it as a real incident. Never finish with a check `Not monitored`, `monitor pending`,
or otherwise disabled.

## 5. Prevent Monit interference during maintenance

Monit may automatically restart a failing service. During maintenance, this can race
the agent or repeatedly undo an intentional stop. Before a repair that leaves a
Monit-restarted service stopped or restarting, unmonitor only that check:

```sh
sudo -n monit unmonitor <check-name>
sudo -n systemctl stop <unit>
```

After the service is healthy, reload Monit's configuration and then re-enable the
specific check. Keep `monitor` after `reload`, because a reload can replace a pending
monitor request:

```sh
sudo -n systemctl start <unit>
sudo -n monit reload
sudo -n monit monitor <check-name>
sudo -n monit status <check-name>
```

Never finish an incident with a check left unmonitored. If the repair fails or planned
maintenance is abandoned, restore monitoring and report the remaining failure.
Do not stop or unmonitor the whole Monit daemon unless that is the diagnosed problem.
Leave maintenance backups and migration source data intact until verification is
complete.

## 6. Report

Return a compact per-host summary with:

- Host and exact Monit alert/check.
- Live evidence and likely root cause.
- Action taken and validation result, if any.
- Remaining alerts and a game plan for each complex incident.
- Access failures, backups created, and intentionally preserved data.

Say explicitly when no action was taken. Do not claim an alert is fixed until both the
underlying service and Monit report healthy.

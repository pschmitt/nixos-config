---
name: monit-fix
description: Inspect live Monit alerts on the rofl-* and oci-* VMs over SSH, identify root causes, immediately fix low-risk reversible service issues, and report unresolved incidents with a concrete game plan. Use when Monit raises alerts, a rofl or oci VM appears unhealthy, or the user asks to check or repair live VM monitoring issues.
---

# Monit Fix

Use live SSH inspection as the source of truth for Monit incidents. Check every known
`rofl-*` and `oci-*` VM, repair only obvious low-risk issues in scope, and clearly
separate completed fixes from complex work that needs a plan.

## Workflow

### 1. Establish scope and inventory

Read the repository `AGENTS.md` before making changes. The current VM inventory is
normally `rofl-10` through `rofl-14`, `oci-01`, and `oci-03`; verify it from the
repository's generated SSH host inventory and the local SSH configuration instead of
assuming the list is permanent. Use SSH aliases where available.

Check hosts in parallel when possible. Use non-interactive SSH with a connection
timeout and `sudo -n`; never hang waiting for a password. An access failure is an
incident to report, not a reason to guess.

### 2. Inspect live Monit state

On each host, start with concise output:

```sh
sudo -n monit summary
sudo -n journalctl -u monit --since "24 hours ago" --no-pager
```

Use `monit status` for the full detail of only the failed or suspicious checks.
Correlate each alert with the live service, container, socket, filesystem, or systemd
unit rather than treating Monit's label as the root cause. Useful read-only checks
include:

- `systemctl status <unit> --no-pager --full`
- `systemctl show <unit> -p ActiveState -p SubState -p Result -p NRestarts`
- `systemctl --failed --no-pager`
- `docker ps -a`, `docker inspect`, and bounded container logs when Docker is involved
- `ss -ltnp` and a local `curl` or protocol check for port or HTTP alerts
- `journalctl -u <unit> --since "2 hours ago" --no-pager`
- `df -h` and `df -ih` for filesystem alerts

Do not rely on an earlier conversation's status: alerts can clear or change while
investigating. Capture timestamps and the current status in the report.

### 3. Classify before changing anything

Fix immediately when all of these are true:

- The cause is clear from live evidence.
- The action is reversible and low risk.
- It does not delete data, alter a data format, reboot a host, deploy configuration,
  change secrets, or affect unrelated services.
- The service is expected to run and restarting or starting that one service is an
  appropriate remedy.

Examples include restarting one crashed stateless service or container after checking
its logs, starting an unexpectedly stopped service with an unambiguous unit, or
clearing a transient failed state after the underlying service is healthy. Validate
the specific Monit check and service afterward.

Do not apply an improvised fix for any of the following; diagnose and provide a game
plan instead:

- Data migrations, schema or storage-format errors, corruption, or cleanup/deletion.
- Reboot-required alerts, kernel changes, disk pressure, filesystem faults, or
  suspected hardware or storage problems.
- Repeated crash or restart loops, authentication or secret failures, network
  reachability problems, or unclear root causes.
- Nix configuration changes, deployments, package or image rollbacks/upgrades,
  firewall or network changes, or monitoring-policy changes.

The game plan must state the evidence, likely cause, proposed steps, backup or
rollback needs, expected service impact, and validation checks. If execution needs
user approval or an external choice, stop after the plan.

### 4. Prevent Monit interference during maintenance

Monit may automatically restart a failing service. During troubleshooting or
maintenance, that restart mechanism can race the agent, hide the original failure,
or repeatedly undo an intentional stop. Unmonitor the specific check before doing
anything that may leave its service stopped or restarting.

Before a repair that intentionally stops or restarts a monitored service, unmonitor
only that check:

```sh
sudo -n monit unmonitor <check-name>
sudo -n systemctl stop <unit>
```

After the service is healthy, re-enable and validate it:

```sh
sudo -n monit monitor <check-name>
sudo -n monit reload
sudo -n monit summary
```

Never finish an incident with a check left unmonitored. If the repair fails or the
planned maintenance is abandoned, restore monitoring before reporting back and note
the remaining failure.

Do not stop or unmonitor the whole Monit daemon unless that is itself the diagnosed
problem. Leave maintenance backups and migration source data intact until verification
is complete.

### 5. Report the result

Return a compact per-host summary containing:

- Host and exact Monit alert or check.
- Live evidence and likely root cause.
- Action taken, if any, and validation result.
- Remaining alerts and a game plan for each complex incident.
- Any access failures, backups created, or intentionally preserved data.

Say explicitly when no action was taken. Do not claim an alert is fixed until both the
underlying service and Monit report healthy.

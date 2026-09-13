---
name: nixos-upgrade-reboot
description: Restart NixOS upgrades on the rofl-* and oci-* fleet, reboot each host as soon as its upgrade is complete and a new kernel is pending, and verify the result without waiting for unrelated hosts.
---

# NixOS Upgrade and Reboot

Use this skill for live maintenance of the `rofl-*` and `oci-*` NixOS hosts when
the user asks to restart `nixos-upgrade.service` and reboot hosts that have a
new kernel waiting.

## Scope and inventory

Read the repository `AGENTS.md` first. Derive the target set from the generated
host-key inventory and local SSH configuration; do not assume that a remembered
host list is still current. The usual targets are `rofl-10` through `rofl-14`,
`oci-01`, and `oci-03`.

Use SSH aliases where available and run independent host checks in parallel.
Use non-interactive SSH with a connection timeout, `BatchMode=yes`, and
`sudo -n`; never wait for a password or guess around an access failure.

## Determine reboot state

On each host, capture:

```sh
uname -r
readlink -f /run/booted-system/kernel
readlink -f /run/current-system/kernel
sudo -n systemctl show nixos-upgrade.service \
  -p ActiveState -p SubState -p Result
```

The authoritative pending-reboot check is whether the resolved
`/run/booted-system/kernel` and `/run/current-system/kernel` paths differ. A
`uname -r` difference is useful context, but do not replace the generation-path
comparison with package-name guesswork.

## Start upgrades

For each target whose `nixos-upgrade.service` is not already active, run:

```sh
sudo -n systemctl restart nixos-upgrade.service
```

This is a oneshot upgrade and may take many minutes while it evaluates,
downloads, or builds a complete NixOS system. If the unit is already active,
treat that as an upgrade in progress and monitor it; do not interrupt it with a
second restart unless the user explicitly asks for that.

Track each host independently. A completed unit normally reports
`ActiveState=inactive`, `SubState=dead`, and `Result=success`; use the unit's
journal to confirm completion. A client SSH command can lose its D-Bus
connection during activation or service restarts. Do not call that a failed
upgrade until an independent SSH check confirms a failed unit or error journal.

## Reboot completed hosts promptly

As soon as one host's upgrade is complete, re-check its booted/current kernel
paths. If they differ, reboot that host immediately:

```sh
sudo -n systemctl reboot
```

Do not wait for other hosts' builds to finish. Never reboot a host while its
upgrade unit is still active. Hosts with no generation mismatch do not need a
reboot.

### Remote unlock grace period

The hosts use `luks-ssh-unlock` with target signatures collected and stored on
`fnuc`. The collection runs approximately once per minute. After a
kernel-changing upgrade, the freshly activated target state may not yet have
been collected, and rebooting too quickly can make the remote unlock refuse to
unlock the host.

When a completed upgrade has a kernel-generation mismatch:

1. Wait at least 60 seconds after upgrade completion before rebooting.
2. Prefer waiting for one fresh `luks-ssh-unlock` collection cycle, or about
   two minutes when there is no direct way to verify collection on `fnuc`.
3. Then reboot the host without waiting for unrelated hosts' upgrades.

Do not skip this grace period merely because the reboot is operationally
urgent. If the signature collection can be inspected, confirm that `fnuc` has
recent material for the target before rebooting.

After reboot, retry SSH for a bounded period and verify:

- the host is reachable and has the expected hostname;
- `uname -r` reflects the new kernel;
- `/run/booted-system/kernel` and `/run/current-system/kernel` now match; and
- `nixos-upgrade.service` is inactive/dead/success.

If SSH reports a changed host key, do not overwrite `known_hosts` blindly.
Validate the fingerprint against a trusted current inventory or other
independent source first. If validation is available, a temporary
`UserKnownHostsFile=/dev/null` plus `StrictHostKeyChecking=no` may be used only
for the narrowly scoped post-reboot check; report the key change and do not
silently alter the user's persistent SSH configuration.

## Completion and reporting

It is acceptable to finish once all currently completed hosts have been
processed, even if another host is still building. Leave unfinished upgrade
services running and report them as pending rather than stopping or restarting
them again.

Report per host:

- upgrade action and final systemd result;
- old/new running and current kernel generations;
- whether a reboot was performed and post-reboot verification; and
- any access failures, key changes, or rebuilds still in progress.

Do not claim a reboot or upgrade is verified solely because the command was
accepted; confirm the post-action state where connectivity permits.

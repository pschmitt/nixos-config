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

### Verify remote unlock readiness

Do not use an elapsed-time delay as the reboot gate. The target's signed initrd
checksum must be current on the configured `luks-ssh-unlock` controller before
rebooting; a recent timestamp alone is not sufficient if collection or
validation is failing.

After a successful upgrade with a kernel-generation mismatch:

1. Derive the controller and instance for the target from the active NixOS
   configuration. Start with the public repository's
   `services/luks-ssh-unlock/fleet.nix` and host imports, then follow the
   `nixos-config-private` input for private modules or host-specific overrides.
   Use the evaluated `services.luks-ssh-unlock.instances` configuration on the
   controller to identify the target instance; do not assume a controller,
   hostname, or target list from memory.
2. Inspect that instance's journal from the upgrade completion time onward.
   Check for checksum fetch failures or SSH/healthcheck errors. Successful
   healthchecks may be intentionally silent, and a controller-side health check
   before the upgrade does not prove the new checksum was collected.
3. Read the instance's configured `initrdCheck.dir` (the `INITRD_CHECKSUM_DIR`
   value) from the evaluated configuration. Confirm the checksum and detached
   signature exist in its per-target directory, and that the successful
   collection is newer than activation. Verify the signature with the target's
   trusted SSH host key as configured by Nix. Treat timestamps as supporting
   evidence alongside a successful fetch and signature verification. Resolve
   private module values from the private checkout or evaluated configuration
   rather than copying sensitive data into notes.
4. If the new checksum has not been collected, or the controller reports a
   missing file, signature/checksum validation failure, or skipped unlock,
   leave the host running and diagnose the controller/target exchange. Do not
   bypass signature validation or reboot on a timer. Recheck after the
   controller records a successful post-activation collection.
5. Re-check that the upgrade unit is inactive and the kernel paths still
   differ, then reboot that host promptly without waiting for unrelated builds.

After reboot, the target may briefly present its distinct initrd SSH host key.
Use the trusted initrd host-key record to validate it; never overwrite
`known_hosts` or disable checking blindly. If validation succeeds, a temporary
`UserKnownHostsFile=/dev/null` plus `StrictHostKeyChecking=no` may be used only
for the narrowly scoped post-reboot check. Report the key change and do not
silently alter persistent SSH configuration.

After reboot, retry SSH for a bounded period and verify:

- the host is reachable and has the expected hostname;
- `uname -r` reflects the new kernel;
- `/run/booted-system/kernel` and `/run/current-system/kernel` now match; and
- `nixos-upgrade.service` is inactive/dead/success.

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

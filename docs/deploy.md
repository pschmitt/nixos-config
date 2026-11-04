# Deployment

## Deploy a working tree

```sh
just deploy HOST
```

This copies the working tree to the target, builds there and runs
`nixos-rebuild switch`. It includes uncommitted changes, so use it to test them.
Home Manager is part of the host configuration and activates with it.

Without a target, `just deploy` builds and switches on the local machine.

To skip evaluation on the target, pass a closure you built elsewhere:

```sh
just deploy HOST --store-path /nix/store/HASH-nixos-system-HOST
```

## Deploy a pushed commit

Servers and workstations run `system.autoUpgrade` from
`github:pschmitt/nixos-config` every night. To start it now, run this on the
host:

```sh
sudo systemctl restart nixos-upgrade.service
```

The upgrade never reboots a host by itself.

## False failures

`just deploy` can report a failure after a successful switch. When
NetworkManager restarts during activation, the SSH session dies with
`Timeout, server HOST not responding`, while `nixos-rebuild` continues on the
target. Check the result on the host:

```sh
readlink -f /run/current-system
nix-env -p /nix/var/nix/profiles/system --list-generations | tail -3
```

Hosts with [`services/initrd-luks-ssh-unlock.nix`](../services/initrd-luks-ssh-unlock.nix)
present a different SSH host key while the initrd waits for the LUKS unlock. A
changed host key warning in that window is expected.

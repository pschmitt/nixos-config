# nixbot-worker

A disposable, encrypted build VM on OpenStack. The nixbot host creates them
from one image for two uses: as Nix remote builders for nixbot (autoscaled by
build demand) and as ad-hoc workers that agents create for heavy compiles
(the `rofl-worker` skill). Workers hold no secrets and keep nothing across reboots.

## Boot

- The image (`images.nixbot-worker` in nixbot's jobs) is a GPT disk with only
  an ESP: systemd-boot, the kernel, and the netboot initrd that carries the
  whole system as squashfs. That is the only unencrypted part of the disk.
- In the initrd, `nixbot-worker-luks-key` writes a random 64-byte key to
  `/run`. `systemd-repart` then deletes the previous boot's data partition
  (factory reset), creates a new LUKS2 partition with that key and formats it.
  `nixbot-worker-open-data` opens it after repart. The key is removed from
  `/run` once the system is up; it never touches a disk.
- The encrypted partition is the writable layer of `/nix/store` and holds
  the build directory. A reboot makes it unreadable; the next boot replaces it.

## Joining nixbot

- `nixbot-worker-netbird-up` reads the instance name and a one-off NetBird
  setup key (`{"netbird_setup_key": "..."}` in the user-data) from the
  OpenStack metadata service and registers with NetBird.
- SSH listens on the NetBird interface only. Three accounts can log in, all
  with keys only (there are no passwords), and nobody on the console:
  - the main user (`mainUser`, with passwordless sudo) with
    `mainUser.authorizedKeys`, for debugging;
  - `nix-remote-builder` (nixbot's pool, the shared builder key);
  - `agent` (ad-hoc workers): its keys come from `agent_authorized_keys`
    in the user-data and are written to
    `/run/nixbot-worker/authorized_keys/agent`. Without user-data keys
    nobody can log in as `agent`. Its home is on the encrypted partition;
    it is a trusted Nix user so it can serve as a remote builder.
- Users of ad-hoc workers: see the `rofl-worker` skill.
- The SSH host key is printed to the serial console as
  `NIXBOT-WORKER-HOSTKEY <type> <key>`, so the autoscaler can read it through
  the OpenStack API instead of trusting it on first use.

## Test

`checks.x86_64-linux.nixbot-worker-boot` boots the image twice in QEMU (UEFI)
and checks from the outside that each boot creates a new LUKS2 volume and a
new host key.

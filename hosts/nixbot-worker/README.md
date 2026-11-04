# nixbot-worker

A disposable, encrypted build VM on OpenStack. The nixbot host creates them
from one image for two uses: as Nix remote builders for nixbot (autoscaled by
build demand) and as ad-hoc workers that agents create for heavy compiles
(the `rworker` skill). Workers hold no secrets and keep nothing across reboots.

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

## Disk layout

One OpenStack volume per worker (250 GiB for the pool, 150 GiB by default
for ad-hoc workers), booted with `hw_firmware_type=uefi`, `q35` and
`virtio` disks:

```
vda                      volume (deleted with the server)
├─vda1   2 GiB   vfat    ESP, the only unencrypted part, from the image:
│                          EFI/BOOT/BOOTX64.EFI            systemd-boot
│                          EFI/nixbot-worker/kernel
│                          EFI/nixbot-worker/initrd        incl. the system
│                                                          as squashfs
│                          loader/entries/nixbot-worker.conf
└─vda2   rest    LUKS2   created by systemd-repart on every boot,
                         random 64-byte key in RAM only
  └─workerdata   ext4    /nix/.rw-store
                           store/  upper layer of /nix/store
                           work/   overlayfs work directory
                           builds/ Nix build directory (build-dir)
                           home/   bind-mounted to /home
```

| Mount | What | Where it lives |
| --- | --- | --- |
| `/` | tmpfs | RAM |
| `/nix/.ro-store` | squashfs of the system closure (from the initrd) | RAM |
| `/nix/.rw-store` | `workerdata` (ext4 inside LUKS2) | `vda2` |
| `/nix/store` | overlay of `.ro-store` and `.rw-store/store` | RAM + `vda2` |
| `/home` | bind mount of `/nix/.rw-store/home` | `vda2` |

Every boot runs, in the initrd: `nixbot-worker-luks-key` (key to
`/run/nixbot-worker/luks.key`), `systemd-repart --factory-reset=yes`
(drops the old `worker-data` partition, creates and encrypts a new one,
formats it), `nixbot-worker-open-data` (`systemd-cryptsetup attach` after
repart; not a crypttab entry, which would bind to the old partition's
device) and the mounts above. Once the system is up,
`nixbot-worker-forget-luks-key` removes the key file; the volume key stays
only in the kernel's device-mapper table. Check it on a worker with
`lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS` and `findmnt /nix/.rw-store`.

## Joining nixbot

- `nixbot-worker-netbird-up` reads the instance name and a one-off NetBird
  setup key (`{"netbird_setup_key": "..."}` in the user-data) from the
  OpenStack metadata service and registers with NetBird.
- SSH listens on the NetBird interface only. Three accounts can log in, all
  with keys only (there are no passwords), and nobody on the console. The
  main user's keys (`mainUser.authorizedKeys`) work for all three:
  - the main user (with passwordless sudo), for debugging;
  - `nix-remote-builder` (nixbot's pool, plus the shared builder key);
  - `agent` (ad-hoc workers): additionally the creator's keys from
    `agent_authorized_keys` in the user-data, written to
    `/run/ssh-authorized-keys/agent`. Its home is on the encrypted partition;
    it is a trusted Nix user so it can serve as a remote builder.
- Users of ad-hoc workers: see the `rworker` skill.
- The SSH host key is printed to the serial console as
  `NIXBOT-WORKER-HOSTKEY <type> <key>`, so the autoscaler can read it through
  the OpenStack API instead of trusting it on first use.

## Metadata on the worker

`/run/rworker/metadata.json` (world-readable) holds what the worker knew at
boot: its name, UUID and availability zone, the boot time, its NixOS system
path, and the server metadata from its creation (`nixbot-worker` kind,
`owner`, `created_at`, `expires_at`, `max_lifetime`; ad-hoc workers only
for the latter ones). It is written once (`"source": "initial"`); a later
`rworker extend` only changes OpenStack. For current values ask the
metadata service:
`curl -s http://169.254.169.254/openstack/latest/meta_data.json | jq .meta`.

## Test

`checks.x86_64-linux.nixbot-worker-boot` boots the image twice in QEMU (UEFI)
and checks from the outside that each boot creates a new LUKS2 volume and a
new host key.

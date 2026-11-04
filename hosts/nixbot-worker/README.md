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
  with keys only (there are no passwords), and nobody on the console:
  - the main user (`mainUser`, with passwordless sudo) with
    `mainUser.authorizedKeys`, for debugging;
  - `nix-remote-builder` (nixbot's pool, the shared builder key);
  - `agent` (ad-hoc workers): its keys come from `agent_authorized_keys`
    in the user-data and are written to
    `/run/nixbot-worker/authorized_keys/agent`. Without user-data keys
    nobody can log in as `agent`. Its home is on the encrypted partition;
    it is a trusted Nix user so it can serve as a remote builder.
- Users of ad-hoc workers: see the `rworker` skill.
- The SSH host key is printed to the serial console as
  `NIXBOT-WORKER-HOSTKEY <type> <key>`, so the autoscaler can read it through
  the OpenStack API instead of trusting it on first use.

## Test

`checks.x86_64-linux.nixbot-worker-boot` boots the image twice in QEMU (UEFI)
and checks from the outside that each boot creates a new LUKS2 volume and a
new host key.

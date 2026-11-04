# nixbot-worker

A disposable Nix remote builder for nixbot. The autoscaler on the nixbot host
creates workers from an OpenStack image when builds queue up and deletes them
when they are idle. Workers hold no secrets and keep nothing across reboots.

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
- SSH listens on the NetBird interface only and lets in `nix-remote-builder`
  alone. No other account can log in, not even on the console.
- The SSH host key is printed to the serial console as
  `NIXBOT-WORKER-HOSTKEY <type> <key>`, so the autoscaler can read it through
  the OpenStack API instead of trusting it on first use.

## Test

`checks.x86_64-linux.nixbot-worker-boot` boots the image twice in QEMU (UEFI)
and checks from the outside that each boot creates a new LUKS2 volume and a
new host key.

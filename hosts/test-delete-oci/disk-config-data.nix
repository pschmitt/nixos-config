{ lib, ... }:
{
  disko.devices.disk.data = {
    # /dev/oracleoci/oraclevdX (from the attachment's explicit `device`
    # argument) doesn't exist in the kexec installer environment - that
    # symlink needs the oci-consistent-device-naming udev rule (see
    # hardware/oci.nix), which isn't present there since disko partitioning
    # runs inside nixos-anywhere's own generic kexec installer image, not
    # our host's config. This exact predictable-device-name approach was
    # tried and reverted in 2024 (see git history) in favor of hardcoding
    # the SCSI WWN, which is what oci-01's data disk already does - a
    # standard udev by-id symlink needing no OCI-specific tooling, stable
    # for the life of this volume attachment. Discovered empirically the
    # same way: `ls -la /dev/disk/by-id/` on the live host after attaching.
    device = lib.mkDefault "/dev/disk/by-id/scsi-3600c1308c9a44a5c880063f93ce10a9e";
    destroy = lib.mkForce false;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "data-encrypted";
            settings = {
              keyFile = "/tmp/disk-2.key";
              allowDiscards = true;
            };
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@data" = {
                  mountpoint = "/mnt/data";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}

{ lib, ... }:
{
  disko.devices.disk.data = {
    # /dev/oracleoci/oraclevdX (from the attachment's explicit `device`
    # argument) doesn't exist in the kexec installer environment - that
    # symlink needs Oracle Cloud Agent's udev rules, which aren't present
    # there. Use the SCSI WWN instead: a standard udev by-id symlink
    # (available with no OCI-specific tooling) that's stable for the life
    # of this volume attachment. Discovered empirically the same way
    # oci-01's static data disk id was: `ls -la /dev/disk/by-id/` on the
    # live host after attaching.
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

{ lib, ... }:
let
  tfVars = builtins.fromJSON (builtins.readFile ./tf-vars.json);
in
{
  disko.devices.disk = {
    data = {
      device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_${tfVars.disks.data.id}";
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
  };
}

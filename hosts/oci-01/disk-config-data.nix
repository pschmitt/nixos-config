{ lib, ... }:
{
  disko.devices.disk.data = {
    device = lib.mkDefault "/dev/disk/by-id/scsi-360699125d7c94b828af12fe7b489ba4b";
    destroy = lib.mkForce false;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "data";
            settings = {
              keyFile = "/tmp/disk-2.key";
              allowDiscards = true;
            };
            content = {
              type = "btrfs";
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
}

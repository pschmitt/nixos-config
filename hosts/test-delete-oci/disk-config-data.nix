{ lib, ... }:
{
  disko.devices.disk.data = {
    # Predictable device path from the paravirtualized volume attachment's
    # explicit `device` argument (Oracle Cloud Agent creates this symlink),
    # not a tf-vars-derived id like the OpenStack hosts use.
    device = lib.mkDefault "/dev/oracleoci/oraclevdb";
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

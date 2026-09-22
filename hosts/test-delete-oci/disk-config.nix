{ lib, ... }:
{
  disko.devices = {
    disk.system = {
      # /dev/sda is NOT stable once a second disk is attached (SCSI letter
      # assignment is attachment-order-dependent, not tied to boot vs. data)
      # - confirmed empirically: with the data disk attached, the boot
      # volume enumerated as /dev/sdb, not /dev/sda. Use its SCSI WWN
      # instead - the same pattern oci-01 already uses for its data disk
      # (see disk-config-data.nix). A predictable /dev/oracleoci/oraclevdX
      # name was tried and reverted in 2024 (see git history); the WWN is
      # what stuck.
      device = lib.mkDefault "/dev/disk/by-id/scsi-3604c27e2f30d43f69e4998462381f66a";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02"; # mbr, bios
          };
          esp = {
            name = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "encrypted";
              settings = {
                keyFile = "/tmp/disk-1.key";
                # NOTE fallbackToPassword is implied when enabling systemd
                # in initrd
                # fallbackToPassword = true;
                allowDiscards = true;
              };
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
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

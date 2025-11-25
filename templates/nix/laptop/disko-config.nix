{ lib, ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    # Update to the correct disk path for the machine (e.g. /dev/nvme0n1 or /dev/disk/by-id/...).
    device = lib.mkDefault "/dev/disk/by-id/REPLACE-ME";
    content = {
      type = "gpt";
      partitions = {
        mbr = {
          label = "MBR"; # For grub MBR
          size = "1M";
          type = "EF02";
          priority = 1;
        };
        ESP = {
          name = "ESP";
          label = "EFI";
          size = "10G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "defaults" ];
            extraArgs = [
              "-n"
              "EFI"
            ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "luks-root";
            extraOpenArgs = [ "--allow-discards" ];
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "luks-root"
              ];
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
}

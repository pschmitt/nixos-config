# Disk layout of the laptops: BIOS boot + ESP + a LUKS-encrypted btrfs root
# with @root, @home and @nix subvolumes. Import it from a host and set the
# disk and ESP size.
{ config, lib, ... }:
let
  cfg = config.hardware.disko.laptop;
  btrfsMount = mountpoint: {
    inherit mountpoint;
    mountOptions = [
      "compress=zstd"
      "noatime"
    ];
  };
in
{
  options.hardware.disko.laptop = {
    device = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_XXXXXXXX";
      description = "Disk to partition, preferably a /dev/disk/by-id path.";
    };
    espSize = lib.mkOption {
      type = lib.types.str;
      default = "10G";
      description = "Size of the EFI system partition.";
    };
  };

  config.disko.devices.disk.main = {
    type = "disk";
    inherit (cfg) device;
    content = {
      type = "gpt";
      partitions = {
        mbr = {
          # GPT partition name (/dev/disk/by-partlabel/MBR). disko only applies
          # it when it partitions the disk; it does not rename an existing one.
          label = "MBR";
          size = "1M";
          type = "EF02"; # for grub MBR
          priority = 1;
        };
        ESP = {
          name = "ESP";
          label = "EFI";
          size = cfg.espSize;
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
                "@root" = btrfsMount "/";
                "@home" = btrfsMount "/home";
                # FIXME Snapper
                # "/home/.snapshots" = { };
                "@nix" = btrfsMount "/nix";
              };
            };
          };
        };
      };
    };
  };
}

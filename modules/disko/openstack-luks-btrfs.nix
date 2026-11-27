# Disk layout of the OpenStack rofl VMs: BIOS boot + ESP + a LUKS-encrypted
# btrfs root with @root, @home and @nix subvolumes. Import it from a host and
# set the root disk id (from the host's tf-vars.json).
{ config, lib, ... }:
let
  cfg = config.hardware.disko.openstack;
  btrfsMount = mountpoint: {
    inherit mountpoint;
    mountOptions = [
      "compress=zstd"
      "noatime"
    ];
  };
in
{
  options.hardware.disko.openstack = {
    rootDiskId = lib.mkOption {
      type = lib.types.str;
      description = "Id of the root volume, as in /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<id>.";
    };
    extraSubvolumes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "@monero-wallet-rpc" = "/var/lib/monero-wallet-rpc";
      };
      description = "Extra btrfs subvolumes (name to mountpoint) on the encrypted root.";
    };
  };

  config.disko.devices.disk.system = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_${cfg.rootDiskId}";
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
              allowDiscards = true;
            };
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = btrfsMount "/";
                "@home" = btrfsMount "/home";
                "@nix" = btrfsMount "/nix";
              }
              // lib.mapAttrs (_: btrfsMount) cfg.extraSubvolumes;
            };
          };
        };
      };
    };
  };
}

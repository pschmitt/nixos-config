{ lib, ... }:
{
  fileSystems = {
    "/" = {
      fsType = "btrfs";
      options = [
        "subvol=@root"
        "compress=zstd"
        "noatime"
      ];
    };

    "/home" = {
      fsType = "btrfs";
      options = [
        "subvol=@home"
        "compress=zstd"
        "noatime"
      ];
    };

    "/nix" = {
      fsType = "btrfs";
      options = [
        "subvol=@nix"
        "compress=zstd"
        "noatime"
      ];
    };
  };

  disko.devices = {
    # SATA data disk: LUKS encrypted volume matching lrz and rofl-10/11 pattern.
    disk.data = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions.luks = {
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
              mountpoint = "/mnt/sda1";
              mountOptions = [
                "compress=zstd"
                "noatime"
                "nofail"
              ];
            };
          };
        };
      };
    };

    # System NVMe: 10 GiB EFI system partition, 1M BIOS boot, remaining for LUKS Btrfs.
    disk.system = {
      device = lib.mkDefault "/dev/nvme0n1";
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
            label = "EFI";
            name = "ESP";
            size = "10G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "defaults"
                "umask=0077"
              ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "encrypted";
              settings = {
                keyFile = "/tmp/disk-1.key";
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

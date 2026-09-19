{ lib, ... }:
{
  # fileSystems."/boot" = {
  #   fsType = "vfat";
  #   # options = [ "defaults" "fmask=0077" ];
  # };

  fileSystems = {
    "/" = {
      # device = "/dev/sda1";  # set by disko
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
    # SATA media disk: LUKS encrypted volume matching rofl-10/11 pattern.
    # HA media is exported over NFS; VM images remain on the system NVMe.
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

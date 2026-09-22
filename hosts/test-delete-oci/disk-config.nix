{ lib, ... }:
{
  disko.devices = {
    disk.system = {
      # /dev/sda is NOT stable once a second disk is attached (SCSI letter
      # assignment is attachment-order-dependent, not tied to boot vs. data)
      # - confirmed empirically: with the data disk attached, the boot
      # volume enumerated as /dev/sdb, not /dev/sda.
      #
      # Use the oci-consistent-device-naming udev rule's predictable name
      # instead (boot volume is always LUN 1 -> oraclevda). This normally
      # only works once the target's own final NixOS config is booted (see
      # hardware/oci.nix) - not during the ephemeral kexec+disko install
      # phase, which runs nixos-anywhere's own generic installer image
      # instead of ours. To fix that, this host's kexec_tarball_url (see
      # test-delete-oci.tf) points at a custom kexec image
      # (pkgs/oci/oci-kexec-installer) with that same udev rule baked in.
      device = lib.mkDefault "/dev/oracleoci/oraclevda";
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

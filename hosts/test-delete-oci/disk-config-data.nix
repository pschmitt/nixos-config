{ lib, ... }:
{
  disko.devices.disk.data = {
    # See disk-config.nix: this needs the custom oci-kexec-installer image
    # (kexec_tarball_url in test-delete-oci.tf) to resolve during install -
    # the udev rule that provides it otherwise only applies to the final
    # booted system (hardware/oci.nix), not the ephemeral kexec+disko
    # environment. LUN 2 (the first additional attachment after boot's
    # LUN 1) maps to oraclevdb per Oracle's own convention.
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

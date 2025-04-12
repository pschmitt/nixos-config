{ lib, ... }:
{
  imports = [
    ./disk-config-data.nix
  ];

  # Data volume
  boot.initrd.luks.devices.data-encrypted = {
    # device = "/dev/sdb";
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };

  # fileSystems."/mnt/data" = {
  #   device = "/dev/mapper/data-encrypted";
  #   # mountPoint = "/mnt/data";
  #   fsType = "btrfs";
  #   options = [
  #     "compress=zstd"
  #     "noatime"
  #   ];
  #
  #   neededForBoot = false;
  # };
}

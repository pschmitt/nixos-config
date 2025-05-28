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

  # symlink /srv to /mnt/data/srv
  systemd.tmpfiles.rules = [
    "L+ /srv - - - - /mnt/data/srv"
  ];
}

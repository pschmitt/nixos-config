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

  # systemd's home.conf ships "q /srv", which duplicates the /srv symlink below
  # and makes systemd-tmpfiles --clean exit 73. Keep only the /home rule.
  environment.etc."tmpfiles.d/home.conf".text = lib.mkForce "Q /home 0755 - - -\n";

  # symlink /srv to /mnt/data/srv
  systemd.tmpfiles.rules = [
    "L+ /srv - - - - /mnt/data/srv"
  ];
}

{ lib, ... }:
{
  imports = [
    ./disk-config-data.nix
  ];

  # The data volume is unlocked in the initrd with the key stored on the
  # already-unlocked root filesystem.  The installer still supplies the
  # temporary key while Disko creates/mounts the volume.
  boot.initrd.luks.devices.data = {
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };

  # systemd's home.conf ships "q /srv", which duplicates the /srv symlink below
  # and makes systemd-tmpfiles --clean exit 73. Keep only the /home rule.
  environment.etc."tmpfiles.d/home.conf".text = lib.mkForce "Q /home 0755 - - -\n";

  systemd.tmpfiles.rules = [
    "L+ /srv - - - - /mnt/data/srv"
  ];
}

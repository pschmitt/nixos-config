{ config, lib, ... }:
{
  imports = [
    ./disk-config-data.nix
  ];

  # Data volume
  boot.initrd.luks.devices.data-encrypted = {
    # device = "/dev/sdb";
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };

  services.postgresql.dataDir = "/mnt/data/srv/postgresql/${config.services.postgresql.package.psqlSchema}";

  systemd.tmpfiles.rules = [
    # dirs
    #                             perm id gid
    "d  /mnt/data/srv/postgresql  0755 71 71 - -"

    # symlinks
    "L+ /srv                      -    -  -  - /mnt/data/srv"
    "L+ /var/lib/postgresql       -    -  -  - /mnt/data/srv/postgresql"
  ];
}

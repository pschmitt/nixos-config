{ config, ... }:
{
  # Data volume

  # FIXME sops-nix decrypts too late, so we *might* need to use age for now
  # sops.secrets."luks/data" = { sopsFile = config.custom.sopsFile; };
  # environment.etc.crypttab.text = ''
  #   data UUID=371fa9e9-38f4-4022-bc96-227821c5eea7 ${config.sops.secrets."luks/data".path}
  # '';

  # agenix
  age.secrets.luks-key-data.file = ../../secrets/${config.networking.hostName}/luks-passphrase-data.age;
  environment.etc.crypttab.text = ''
    data UUID=371fa9e9-38f4-4022-bc96-227821c5eea7 ${config.age.secrets.luks-key-data.path}
  '';

  fileSystems."/mnt/data" = {
    device = "/dev/mapper/data";
    # mountPoint = "/mnt/data";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "noatime"
    ];

    neededForBoot = false;

    # encrypted = {
    #   enable = true;
    #   blkDev = "/dev/disk/by-uuid/371fa9e9-38f4-4022-bc96-227821c5eea7";
    #   keyFile = config.sops.secrets."luks/data".path;
    # };
  };

  services.postgresql.dataDir = "/mnt/data/srv/postgresql";

  systemd.tmpfiles.rules = [ "L+ /srv - - - - /mnt/data/srv" ];
}

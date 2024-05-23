{ config, ... }: {
  # Data volume
  sops.secrets."luks/data" = { sopsFile = config.custom.sopsFile; };

  environment.etc.crypttab.text = ''
    data UUID=371fa9e9-38f4-4022-bc96-227821c5eea7 ${config.sops.secrets."luks/data".path}
  '';

  fileSystems."/mnt/data" = {
    device = "/dev/mapper/data";
    fsType = "btrfs";
    options = [ "compress=zstd" "noatime" ];
  };

  systemd.tmpfiles.rules = [
    "L+ /srv - - - - /mnt/data/srv"
  ];
}

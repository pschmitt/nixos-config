{ config, ... }: {
  # Data volume
  age.secrets.luks-key-data.file = ../../secrets/${config.networking.hostName}/luks-passphrase-data.age;

  environment.etc.crypttab.text = ''
    data UUID=371fa9e9-38f4-4022-bc96-227821c5eea7 ${config.age.secrets.luks-key-data.path}
  '';

  fileSystems."/mnt/data" = {
    device = "/dev/mapper/data";
    fsType = "btrfs";
  };

  systemd.tmpfiles.rules = [
    "L+ /srv - - - - /mnt/data/srv"
  ];
}

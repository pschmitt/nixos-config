{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  # Data volume
  age.secrets.luks-key-data.file = ../../secrets/${hostname}/luks-passphrase-data.age;

  environment.etc.crypttab.text = ''
    data UUID=371fa9e9-38f4-4022-bc96-227821c5eea7 ${config.age.secrets.luks-key-data.path}
  '';

  fileSystems."/mnt/data" = {
    device = "/dev/mapper/data";
    fsType = "btrfs";
  };
}

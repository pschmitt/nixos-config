{ config, lib, ... }:
{
  # Data volume

  # FIXME sops-nix decryption of the data volume
  # sops.secrets."luks/data" = {
  #   sopsFile = ./luks.sops.yaml;
  # };
  # sops.templates.crypttab.content = ''
  #   data PARTLABEL=disk-data-luks ${config.sops.secrets."luks/data".path}
  # '';
  # environment.etc.crypttab = {
  #   source = config.sops.templates.crypttab.path;
  #   mode = "0400";
  # };

  fileSystems."/mnt/data".neededForBoot = lib.mkForce false;

  # TODO Replace with sops-nix
  # agenix
  age.secrets.luks-key-data.file = ../../secrets/${config.networking.hostName}/luks-passphrase-data.age;
  environment.etc.crypttab.text = ''
    data PARTLABEL=disk-data-luks ${config.age.secrets.luks-key-data.path}
  '';
}

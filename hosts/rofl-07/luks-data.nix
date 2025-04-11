{ config, lib, ... }:
let
  # keyFile = "/mnt-root/luks-data.keyfile";
  # keyFile = "/sysroot/luks-data.keyfile";
  keyFile = "/luks-data.keyfile";
in
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

  # TODO Replace with sops-nix
  # agenix
  # age.secrets.luks-key-data.file = ../../secrets/${config.networking.hostName}/luks-passphrase-data.age;
  # environment.etc.crypttab.text = ''
  #   data PARTLABEL=disk-data-luks ${config.age.secrets.luks-key-data.path}
  # '';

  environment.etc.crypttab.text = ''
    data PARTLABEL=disk-data-luks ${keyFile}
  '';

  # fileSystems."/mnt/data" = {
  #   encrypted = {
  #     # TODO Try explicitly disabling it with lib.mkForce false
  #     # and use crypttab?
  #     enable = lib.mkForce false;
  #     keyFile = "/mnt-root/luks-data.keyfile";
  #   };
  # };

  boot.initrd.luks.devices.data-encrypted = {
    keyFile = lib.mkForce "/sysroot${keyFile}";
    fallbackToPassword = lib.mkForce false;
  };
}

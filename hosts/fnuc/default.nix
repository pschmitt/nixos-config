{ config, ... }:
{
  imports = [
    ../../modules/main-user.nix

    ../../home-manager/server-base.nix
    ../../home-manager/sops-standalone.nix
  ];

  sops.defaultSopsFile = ./secrets.sops.yaml;

  targets.genericLinux.enable = true;

  home = {
    inherit (config.mainUser) username homeDirectory;
    stateVersion = "25.11";
  };
}

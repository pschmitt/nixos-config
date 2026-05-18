{ config, pkgs, ... }:
{
  imports = [
    ../../modules/main-user.nix
    ../../modules/domains.nix

    ../../home-manager/base.nix
    # ../../home-manager/work
    ../../home-manager/sops-standalone.nix
  ];

  sops.defaultSopsFile = ./secrets.sops.yaml;
  domains.main = "brkn.lol";

  targets.genericLinux.enable = true;

  home = {
    inherit (config.mainUser) username homeDirectory;
    stateVersion = "26.05";
  };

  services.home-manager.autoUpgrade = {
    enable = true;
    frequency = "02:30";
    useFlake = true;
    flakeDir = "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";
    flags = [
      "-b"
      "hm-backup"
    ];
    preSwitchCommands = [
      "${pkgs.gitMinimal}/bin/git pull"
    ];
  };
}

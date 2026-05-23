{ config, pkgs, ... }:
{
  imports = [
    ../../modules/main-user.nix
    ../../modules/domains.nix

    ../../home-manager/base.nix
    ../../home-manager/work
    ../../home-manager/sops-standalone.nix
    ../../home-manager/devel/claude-remote.nix
    ../../home-manager/codex-ha-bridge.nix
    ../../services/nix-distributed-build.nix
  ];

  domains.main = "brkn.lol";

  targets.genericLinux.enable = true;

  xdg.configFile."home-manager".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";

  home = {
    inherit (config.mainUser) username homeDirectory;
    stateVersion = "26.05";
  };

  nix.package = pkgs.nix;
  nix.settings.max-jobs = 0;

  sops.secrets."ssh/nix-remote-builder/privkey".mode = "0400";

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

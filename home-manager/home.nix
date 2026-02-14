{
  lib,
  pkgs,
  osConfig,
  ...
}:
{
  imports = lib.concatLists [
    [
      ./banking.nix
      ./bitwarden.nix
      ./cli
      ./crypto.nix
      ./devel
      ./env.nix
      ./flatpak.nix
      ./mail.nix
      ./network.nix
      ./nix-index-database.nix
      ./nrf.nix
      # ./openclaw.nix
      ./gpg.nix
      ./sops.nix
      ./ssh.nix
      ./work
      ./yadm.nix
    ]
    (lib.optional osConfig.hardware.bluetooth.enable ./bluetooth.nix)
    (lib.optional osConfig.services.xserver.enable ./gui)
  ];

  programs.home-manager.enable = true;

  systemd.user.startServices = "sd-switch";

  home.preferXdgDirectories = true;

  home = {
    # The home.stateVersion option does not have a default and must be set
    inherit (osConfig.system) stateVersion;
    packages = [ pkgs.home-manager ];
  };
}

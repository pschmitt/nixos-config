{
  inputs,
  lib,
  osConfig,
  ...
}:
{
  imports = lib.concatLists [
    [
      inputs.catppuccin.homeModules.catppuccin
      inputs.nix-index-database.homeModules.nix-index
      inputs.sops-nix.homeManagerModules.sops

      ./banking.nix
      ./bitwarden.nix
      ./cli
      ./crypto.nix
      ./devel
      ./env.nix
      ./flatpak.nix
      ./mail.nix
      ./networking.nix
      ./nrf.nix
      ./nvim.nix
      ./gpg.nix
      ./sops.nix
      ./ssh.nix
      ./work
      ./yadm.nix
      ./zsh
    ]
    (lib.optional osConfig.hardware.bluetooth.enable ./bluetooth.nix)
    (lib.optional osConfig.services.xserver.enable ./gui)
  ];

  programs = {
    home-manager.enable = true;
    nix-index-database.comma.enable = true;
  };

  systemd.user.startServices = "sd-switch";

  home = {
    # The home.stateVersion option does not have a default and must be set
    inherit (osConfig.system) stateVersion;
  };
}

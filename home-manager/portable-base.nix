{ ... }:
{
  imports = [
    ./banking.nix
    ./bitwarden.nix
    ./cli
    ./crypto.nix
    ./devel/portable.nix
    ./env.nix
    ./flatpak.nix
    ./mail.nix
    ./network.nix
    ./nix-index-database.nix
    ./nrf.nix
  ];

  programs.home-manager.enable = true;

  systemd.user.startServices = "sd-switch";

  home.preferXdgDirectories = true;
  xdg.userDirs.setSessionVariables = true;
}

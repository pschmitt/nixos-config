{ ... }:
{
  imports = [
    ./bitwarden.nix
    ./cli/server.nix
    ./devel/server.nix
    ./env.nix
    ./network.nix
  ];

  programs.home-manager.enable = true;

  systemd.user.startServices = "sd-switch";

  home.preferXdgDirectories = true;
  xdg.userDirs.setSessionVariables = true;
}

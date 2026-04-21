{
  imports = [
    ./banking.nix
    ./bitwarden.nix
    ./cli
    ./crypto.nix
    ./devel
    ./env.nix
    ./flatpak.nix
    ./gpg.nix
    ./mail.nix
    ./network.nix
    ./nix-index-database.nix
  ];

  programs.home-manager.enable = true;

  systemd.user.startServices = "sd-switch";

  home.preferXdgDirectories = true;
  xdg.userDirs.setSessionVariables = true;
}

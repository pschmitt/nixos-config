{ pkgs, ... }:
{
  imports = [
    ./env.nix
    ./devel/portable.nix
    ./network.nix
  ];

  programs.home-manager.enable = true;

  home = {
    preferXdgDirectories = true;

    packages = with pkgs; [
      bat
      fd
      fzf
      git
      gnugrep
      gnused
      gnutar
      jq
      neovim
      procps
      ripgrep
      tmux
      unzip
      zip
    ];
  };

  xdg.userDirs.setSessionVariables = true;
}

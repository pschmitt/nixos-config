{ pkgs, ... }:
{
  imports = [
    ./env.nix
    ./network.nix

    ./devel/android.nix
    ./devel/git.nix
    ./devel/nix.nix
    ./devel/nodejs.nix
    ./devel/sh.nix
    ./devel/zsh.nix
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

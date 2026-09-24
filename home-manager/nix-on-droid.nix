{ lib, pkgs, ... }:
{
  imports = [
    ./env.nix
    ./network.nix
    ./nix-on-droid-sops.nix

    ./devel/git.nix
    ./devel/nix.nix
    ./devel/nodejs.nix
    ./devel/sh.nix
    ./devel/zsh.nix
  ];

  programs.home-manager.enable = true;

  # The NixOS HM module bridges this from the system; nix-on-droid does not.
  nix.package = lib.mkDefault pkgs.nix;

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

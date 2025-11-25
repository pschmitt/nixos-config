{ pkgs, ... }:
{

  imports = [
    ./ai.nix
    ./android.nix
    ./git.nix
    ./nix.nix
    ./python.nix
    ./rust.nix
    ./sh.nix
    ./zsh.nix
  ];

  home.packages = with pkgs; [
    apacheHttpd # for htpasswd
    codespell
    envsubst
    flarectl
    hostctl
    inotify-tools
    openssl
    sqlite
    tmux-xpanes
    websocat

    # task runners
    gnumake
    go-task
    just

    # compilers and shit
    gcc
    go
    nodejs
  ];
}

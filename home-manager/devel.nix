{ pkgs, ... }:

{
  home.packages = with pkgs; [
    act # gh actions, locally
    codespell
    devenv
    gh
    git-extras
    inotify-tools
    openssl
    shellcheck
    zunit

    # misc
    flarectl
    sqlite

    # ai
    aichat
    shell-gpt
    tgpt

    # android
    android-tools # adb + fastboot
    pmbootstrap

    # nix
    alejandra
    cachix
    niv
    nix-init
    nixfmt-rfc-style
    nixos-anywhere
    nixos-generators
    nixpkgs-fmt
    nvd
  ];
}

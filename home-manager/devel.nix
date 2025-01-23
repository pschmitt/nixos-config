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

    # misc
    flarectl

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
  ];
}

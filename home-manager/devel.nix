{ pkgs, ... }:
let
  pythonPackages =
    ps: with ps; [
      dbus-python
      dnspython
      black
      flake8
      gst-python
      ipython
      isort
      pip
      pipx
      pygobject3
      pynvim
      requests
      rich
      uv
    ];
in
{
  home.packages = with pkgs; [
    act # gh actions, locally
    codespell
    gh
    git-extras
    inotify-tools
    openssl
    shellcheck
    zunit

    # banking
    python313Packages.woob

    # devel
    gcc
    gnumake
    go
    nodejs
    pkg-config
    (fenix.complete.withComponents [
      "cargo"
      # "clippy"
      # "rust-src"
      "rustc"
      "rustfmt"
    ])
    (python3.withPackages (pythonPackages))

    # misc
    flarectl
    hostctl
    sqlite

    # ai
    aichat
    shell-gpt
    tgpt

    # android
    android-tools # adb + fastboot
    pmbootstrap

    # python
    poetry
    uv

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

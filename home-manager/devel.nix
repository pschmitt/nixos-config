{ pkgs, ... }:
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
    python3Packages.woob

    # devel
    gcc
    gnumake
    go
    just
    nodejs
    pkg-config
    (fenix.complete.withComponents [
      "cargo"
      # "clippy"
      # "rust-src"
      "rustc"
      "rustfmt"
    ])

    # misc
    apacheHttpd # for htpasswd
    envsubst
    flarectl
    hostctl
    sqlite
    websocat

    # ai
    aichat
    master.codex
    master.github-copilot-cli
    tgpt

    # android
    android-tools # adb + fastboot
    pmbootstrap

    # python
    black
    isort
    pipx
    poetry
    python3Packages.flake8
    python3Packages.ipython
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
    statix
  ];
}

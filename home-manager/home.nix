{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    inputs.nur.hmModules.nur
    ./bitwarden.nix
    ./firefox.nix
    ./nvim.nix
    ./obs-studio.nix
    ./theme.nix
    ./work.nix
  ];

  # FIXME Do we need that for anything?
  # nixpkgs.overlays = [
  #   inputs.nur.overlay
  # ];

  # The home.stateVersion option does not have a default and must be set
  home.stateVersion = "23.05";

  programs.home-manager = { enable = true; };

  home.packages = with pkgs; [
    home-manager
    # nwg-displays
    # thunderbird

    # cli
    age
    atuin
    bat
    direnv
    fd
    fzf
    jc
    jsonrepair
    neofetch
    rich-cli
    sops
    yadm

    # gui
    gimp
    nextcloud-client
    unstable.signal-desktop

    # iot
    mosquitto

    # virtualization
    distrobox
    quickemu
    quickgui

    # devel
    android-tools
    # ansible
    codespell
    flarectl
    openssl
    shellcheck

    # nix
    niv
    nix-index
    nix-init
    nixfmt
    nixos-generators
    nixpkgs-fmt
    rnix-lsp

    # Media
    ffmpeg-full
    mpv
    v4l-utils
    vlc
  ];

  # AccountService profile picture
  home.file = {
    ".face" = {
      enable = true;
      source = builtins.fetchurl {
        url = "https://www.gravatar.com/avatar/8635e7a28259cb6da1c6a3c96c75b425.png?size=96";
        sha256 = "1kg0x188q1g2mph13cs3sm4ybj3wsliq2yjz5qcw4qs8ka77l78p";
      };
    };
  };

  gtk = {
    enable = true;
    # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
    gtk3 = {
      extraConfig = { gtk-application-prefer-dark-theme = 1; };
      bookmarks = [
        "file:///tmp tmp"
        "file://${config.home.homeDirectory}/devel/private devel-p"
        "file://${config.home.homeDirectory}/devel/work devel-w"
        "file://${config.home.homeDirectory}/Documents"
        "file://${config.home.homeDirectory}/Downloads"
        "file://${config.home.homeDirectory}/Music"
        "file://${config.home.homeDirectory}/Public"
        "file://${config.home.homeDirectory}/Pictures"
        "file://${config.home.homeDirectory}/Templates"
        "file://${config.home.homeDirectory}/Videos"
      ];
    };
  };
}

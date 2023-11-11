{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    inputs.nur.hmModules.nur
    ./firefox.nix
    ./obs-studio.nix
    ./work.nix
  ];

  # FIXME Do we need that for anything?
  # nixpkgs.overlays = [
  #   inputs.nur.overlay
  # ];

  # The home.stateVersion option does not have a default and must be set
  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    home-manager
    # nwg-displays
    # thunderbird

    # cli
    age
    atuin
    bitwarden-cli
    bat
    direnv
    jc
    fd
    jsonrepair
    fzf
    neofetch
    sops
    yadm

    # gui
    gimp
    nextcloud-client
    unstable.signal-desktop

    # iot
    mosquitto

    # virtualization
    quickemu
    quickgui
    distrobox

    # devel
    android-tools
    codespell
    flarectl
    # ansible
    shellcheck
    niv
    nixpkgs-fmt
    nixos-generators
    rnix-lsp
    nixfmt
    nix-index
    openssl
    # openssl_1_1

    # Media
    ffmpeg-full
    mpv
    v4l-utils
    vlc

    # FIXME This should be part of hyprland.nix
    # NOTE Installing gtklock with home manager has the nice side-effect
    # that it creates nice symlinks in
    # /etc/profiles/per-user/pschmitt/lib/gtklock/
    gtklock
    gtklock-playerctl-module
    gtklock-userinfo-module
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
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome.gnome-themes-extra;
    };
    iconTheme = {
      name = "Colloid-nord-dark";
      # Colloid-nord-dark is not technically part of colloid-icon-theme
      # package = pkgs.colloid-icon-theme;
    };
    font = {
      name = "Noto Sans 10";
      package = pkgs.noto-fonts;
    };
    cursorTheme = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
    };

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

    gtk4 = { extraConfig = { gtk-application-prefer-dark-theme = 1; }; };
  };

  qt = {
    enable = true;
    platformTheme = "gnome";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt6;
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = { color-scheme = "prefer-dark"; };
  };

  programs.home-manager = { enable = true; };

  programs.neovim = {
    enable = true;
    extraPackages = with pkgs; [
      vimPlugins.nvim-treesitter.withAllGrammars
      shellcheck
      shfmt

      # nix
      nixpkgs-fmt
    ];

    viAlias = false;
    vimAlias = true;
  };
}

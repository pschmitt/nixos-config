{ inputs, lib, config, pkgs, ... }: {
  # You can import other home-manager modules here
  imports = [
    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];

  # The home.stateVersion option does not have a default and must be set
  home.stateVersion = "23.05";
  home.packages = with pkgs; [
    home-manager
    # nwg-displays
    # thunderbird

    # cli
    age
    bitwarden-cli
    bat
    fd
    fzf
    neofetch
    sops
    yadm

    # gui
    gimp
    nextcloud-client

    # virtualization
    quickemu
    quickgui
    distrobox

    # devel
    android-tools
    # ansible
    shellcheck
    niv
    nixpkgs-fmt
    rnix-lsp
    nixfmt
    nix-index
    openssl
    # openssl_1_1

    # Work
    kubectl
    vault
    openvpn
    openconnect
    zoom-us
    taskwarrior
    timewarrior

    # Media
    ffmpeg-full
    fx_cast_bridge
    mpv-unwrapped
    v4l-utils
    vlc

    # OBS Plugins
    obs-studio
    unstable.obs-studio-plugins.obs-text-pthread
    obs-studio-plugins.obs-freeze-filter
    obs-studio-plugins.obs-replay-source

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

    # OBS Studio plugins
    ".config/obs-studio/plugins/obs-text-pthread/bin/64bit/obs-text-pthread.so" = {
      enable = true;
      source = "${pkgs.unstable.obs-studio-plugins.obs-text-pthread}/lib/obs-plugins/obs-text-pthread.so";
    };
    ".config/obs-studio/plugins/obs-text-pthread/data" = {
      enable = true;
      recursive = true;
      source = "${pkgs.unstable.obs-studio-plugins.obs-text-pthread}/share/obs/obs-plugins/obs-text-pthread";
    };

    ".config/obs-studio/plugins/freeze-filter/bin/64bit/freeze-filter.so" = {
      enable = true;
      source = "${pkgs.obs-studio-plugins.obs-freeze-filter}/lib/obs-plugins/freeze-filter.so";
    };
    ".config/obs-studio/plugins/freeze-filter/data" = {
      enable = true;
      recursive = true;
      source = "${pkgs.obs-studio-plugins.obs-freeze-filter}/share/obs/data/obs-plugins/freeze-filter";
    };

    ".config/obs-studio/plugins/replay-source/bin/64bit/replay-source.so" = {
      enable = true;
      source = "${pkgs.obs-studio-plugins.obs-replay-source}/lib/obs-plugins/replay-source.so";
    };
    ".config/obs-studio/plugins/replay-source/data" = {
      enable = true;
      recursive = true;
      source = "${pkgs.obs-studio-plugins.obs-replay-source}/share/obs/data/obs-plugins/replay-source";
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
        # "file://${config.users.users.pschmitt.home}/devel/private devel-p"
        # "file://${config.users.users.pschmitt.home}/devel/work devel-w"
        # "file://${config.users.users.pschmitt.home}/Documents"
        # "file://${config.users.users.pschmitt.home}/Downloads"
        # "file://${config.users.users.pschmitt.home}/Music"
        # "file://${config.users.users.pschmitt.home}/Public"
        # "file://${config.users.users.pschmitt.home}/Pictures"
        # "file://${config.users.users.pschmitt.home}/Templates"
        # "file://${config.users.users.pschmitt.home}/Videos"
        "file:///home/pschmitt/devel/private devel-p"
        "file:///home/pschmitt/devel/work devel-w"
        "file:///home/pschmitt/Documents"
        "file:///home/pschmitt/Downloads"
        "file:///home/pschmitt/Music"
        "file:///home/pschmitt/Public"
        "file:///home/pschmitt/Pictures"
        "file:///home/pschmitt/Templates"
        "file:///home/pschmitt/Videos"
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
      shellcheck
      shfmt

      # nix
      nixpkgs-fmt
    ];

    viAlias = false;
    vimAlias = true;
  };

  programs.firefox = {
    enable = true;
    profiles.default = {
      search = {
        force = true;
        engines = {
          "Nix Packages" = {
            urls = [{
              template = "https://search.nixos.org/packages";
              params = [
                { name = "type"; value = "packages"; }
                { name = "query"; value = "{searchTerms}"; }
              ];
            }];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "nixp" ];
          };

          "Nix Options" = {
            urls = [{
              template = "https://search.nixos.org/options";
              params = [
                { name = "type"; value = "options"; }
                { name = "query"; value = "{searchTerms}"; }
              ];
            }];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "nixo" ];
          };

          "NixOS Wiki" = {
            urls = [{ template = "https://nixos.wiki/index.php?search={searchTerms}"; }];
            iconUpdateURL = "https://nixos.wiki/favicon.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "nixw" ];
          };

          "ArchWiki" = {
            urls = [{ template = "https://wiki.archlinux.org/index.php?title=Special%3ASearch&profile=default&fulltext=1&search={searchTerms}"; }];
            iconUpdateURL = "https://wiki.archlinux.org/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "aw" ];
          };

          "Bing".metaData.hidden = true;
          "Google".metaData.alias = "g"; # builtin engines only support specifying one additional alias

          "YouTube" = {
            urls = [{ template = "https://www.youtube.com/results?search_query={searchTerms}"; }];
            iconUpdateURL = "https://www.youtube.com/s/desktop/6ca9d352/img/favicon_144x144.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "y" ];
          };

          "GMail" = {
            urls = [{ template = "https://mail.google.com/mail/u/0/#search/{searchTerms}"; }];
            iconUpdateURL = "https://www.google.com/a/cpanel/schmitt.co/images/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "gm" ];
          };
        };
      };
    };
  };
}

{ config, pkgs, ... }:
let
  home-manager = builtins.fetchTarball
    # "https://github.com/nix-community/home-manager/archive/master.tar.gz";
    "https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz";
  unstable = import
    (builtins.fetchTarball "https://github.com/nixos/nixpkgs/tarball/master")
    # reuse the current configuration
    { config = config.nixpkgs.config; };
in
{
  imports = [ (import "${home-manager}/nixos") ];

  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;

    users.pschmitt = {
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
        obs-studio
        v4l-utils
        vlc

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
          source = builtins.fetchurl
            ("https://www.gravatar.com/avatar/8635e7a28259cb6da1c6a3c96c75b425.png?size=96");
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
            "file://${config.users.users.pschmitt.home}/devel/private devel-p"
            "file://${config.users.users.pschmitt.home}/devel/work devel-w"
            "file://${config.users.users.pschmitt.home}/Documents"
            "file://${config.users.users.pschmitt.home}/Downloads"
            "file://${config.users.users.pschmitt.home}/Music"
            "file://${config.users.users.pschmitt.home}/Public"
            "file://${config.users.users.pschmitt.home}/Pictures"
            "file://${config.users.users.pschmitt.home}/Templates"
            "file://${config.users.users.pschmitt.home}/Videos"
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

              "Bing".metaData.hidden = true;
              "Google".metaData.alias = "@g"; # builtin engines only support specifying one additional alias
            };
          };
        };
      };
    };
  };
}

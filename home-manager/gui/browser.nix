{ inputs, pkgs, ... }:
{

  home.packages = with pkgs; [
    brotab
    tor-browser
    inputs.zen-browser.packages."${system}".default
  ];

  programs.firefox = {
    enable = true;

    profiles.default = {
      extensions.packages = with pkgs.firefox-addons; [
        # https://gitlab.com/rycee/nur-expressions
        auto-tab-discard
        bitwarden
        brotab
        # bypass-paywalls-clean
        consent-o-matic
        don-t-fuck-with-paste
        external-application
        firefox-translations
        foxyproxy-standard
        french-dictionary
        fx_cast
        # header-editor
        # istilldontcareaboutcookies
        languagetool
        # link-cleaner # leads to issues on github
        multi-account-containers
        refined-github
        re-enable-right-click
        sidebery
        sponsorblock
        # tridactyl
        ublock-origin
        video-downloadhelper
        zoom-redirector
      ];

      search = {
        force = true;
        default = "Unduck";

        # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.firefox.profiles._name_.search.engines
        engines = {
          "DuckDuckGo" = {
            url = "https://www.duckduckgo.com/?q={searchTerms}";
            hidden = false;
            definedAliases = [ "ddg" ];
          };

          "Perplexity" = {
            urls = [ { template = "https://www.perplexity.ai/?q={searchTerms}"; } ];
            iconUpdateURL = "https://www.perplexity.ai/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # Every day
            definedAliases = [ "pp" ];
          };

          "Nix Packages" = {
            urls = [
              {
                template = "https://search.nixos.org/packages";
                params = [
                  {
                    name = "type";
                    value = "packages";
                  }
                  {
                    name = "channel";
                    value = "unstable";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "nixp" ];
          };

          "Nix Options" = {
            urls = [
              {
                template = "https://search.nixos.org/options";
                params = [
                  {
                    name = "type";
                    value = "options";
                  }
                  {
                    name = "channel";
                    value = "unstable";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "nixopt" ];
          };

          "NixOS Wiki" = {
            urls = [ { template = "https://nixos.wiki/index.php?search={searchTerms}"; } ];
            iconUpdateURL = "https://nixos.wiki/favicon.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "nixw" ];
          };

          "Nixpkgs PRs" = {
            urls = [
              {
                template = "https://github.com/NixOS/nixpkgs/pulls";
                params = [
                  {
                    name = "q";
                    # Search in title explicitly
                    value = "in:title {searchTerms}";
                  }
                ];
              }
            ];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "npr" ];
          };

          "ArchWiki" = {
            urls = [
              {
                template = "https://wiki.archlinux.org/index.php?title=Special%3ASearch&profile=default&fulltext=1&search={searchTerms}";
              }
            ];
            iconUpdateURL = "https://wiki.archlinux.org/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "aw" ];
          };

          "Bing".metaData.hidden = true;
          "Google".metaData.alias = "g"; # builtin engines only support specifying one additional alias
          "Wikipedia (en)".metaData.alias = "wiki"; # builtin engines only support specifying one additional alias

          "GitHub" = {
            urls = [ { template = "https://github.com/search?q={searchTerms}"; } ];
            iconUpdateURL = "https://github.com/fluidicon.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "gh" ];
          };

          "YouTube" = {
            urls = [ { template = "https://www.youtube.com/results?search_query={searchTerms}"; } ];
            iconUpdateURL = "https://www.youtube.com/s/desktop/6ca9d352/img/favicon_144x144.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "y" ];
          };

          "GMail" = {
            urls = [ { template = "https://mail.google.com/mail/u/0/#search/{searchTerms}"; } ];
            iconUpdateURL = "https://www.google.com/a/cpanel/schmitt.co/images/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "gm" ];
          };

          "Unduck" = {
            urls = [ { template = "https://unduck.link?q={searchTerms}"; } ];
            iconUpdateURL = "https://unduck.link/search.svg";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "ud" ];
          };
        };
      };
    };
  };

  # FIXME This seems to be the only really working way to install
  # native messaging hosts.
  # programs.firefox.nativeMessagingHosts.packages doesn't work!
  home.file.".mozilla/native-messaging-hosts/brotab_mediator.json".source =
    "${pkgs.brotab}/lib/mozilla/native-messaging-hosts/brotab_mediator.json";
  home.file.".mozilla/native-messaging-hosts/fx_cast_bridge.json".source =
    "${pkgs.fx-cast-bridge}/lib/mozilla/native-messaging-hosts/fx_cast_bridge.json";
  # external-application-button
  home.file.".mozilla/native-messaging-hosts/com.add0n.node.json".source =
    "${pkgs.native-client}/lib/mozilla/native-messaging-hosts/com.add0n.node.json";
  # FIXME the vdhcoapp 2.0.19 nixpkg does not ship with a static native
  # messaging manifest, instead it is relying on the user running:
  # $ vdhcoapp install
  # home.file.".mozilla/native-messaging-hosts/net.downloadhelper.coapp.json".source = "${pkgs.vdhcoapp}/lib/mozilla/native-messaging-hosts/net.downloadhelper.coapp.json";
  home.file.".mozilla/native-messaging-hosts/tridactyl.json".source =
    "${pkgs.tridactyl-native}/lib/mozilla/native-messaging-hosts/tridactyl.json";

  # BroTab for Google Chrome
  home.file.".config/google-chrome/NativeMessagingHosts/brotab_mediator.json".source =
    "${pkgs.brotab}/lib/chromium/NativeMessagingHosts/brotab_mediator.json";

  systemd.user.services.fx-cast = {
    Unit = {
      Description = "fx-cast-bridge";
      Documentation = "https://hensm.github.io/fx_cast/";
    };

    Service = {
      ExecStart = "${pkgs.fx-cast-bridge}/bin/fx_cast_bridge -d";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

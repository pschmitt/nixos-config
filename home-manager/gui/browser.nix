{ inputs, pkgs, ... }:
{

  home.packages = with pkgs; [
    brotab
    tor-browser
    inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
  ];

  programs.firefox = {
    enable = true;

    nativeMessagingHosts = with pkgs; [
      brotab
      fx-cast-bridge
      native-client # external-application-button
      tridactyl-native
    ];

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
        linkding-extension
        linkding-injector
        multi-account-containers
        refined-github
        re-enable-right-click
        single-file
        sponsorblock
        # tridactyl
        ublock-origin
        video-downloadhelper
        zoom-redirector
      ];

      # about:config
      settings = {
        # Enable custom css (userChrome.css)
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

        # Hide share indicator
        "privacy.webrtc.legacyGlobalIndicator" = false;
        "privacy.webrtc.hideGlobalIndicator" = true;

        # Prevent Firefox from Googling .lan addresses and opening them directly
        "browser.fixup.domainsuffixwhitelist.lan" = true;

        # Hide the "Summarize Page" button in the AI sidebar
        # https://www.reddit.com/r/firefox/comments/1o8zt65/how_do_i_remove_the_summarize_page_button_below/
        "browser.ml.chat.page" = false;
      };

      search = {
        force = true;
        default = "Unduck";

        # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.firefox.profiles._name_.search.engines
        engines = {
          ddg = {
            name = "DuckDuckGo";
            url = "https://www.duckduckgo.com/?q={searchTerms}";
            hidden = false;
            definedAliases = [ "ddg" ];
          };

          perplexity = {
            name = "Perplexity";
            urls = [ { template = "https://www.perplexity.ai/?q={searchTerms}"; } ];
            icon = "https://www.perplexity.ai/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # Every day
            definedAliases = [ "pp" ];
          };

          nix-packages = {
            name = "Nix Packages";
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

          nix-options = {
            name = "Nix Options";
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

          nixos-wiki = {
            name = "NixOS Wiki";
            urls = [ { template = "https://nixos.wiki/index.php?search={searchTerms}"; } ];
            icon = "https://nixos.wiki/favicon.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "nixw" ];
          };

          nixpkgs-prs = {
            name = "Nixpkgs PRs";
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

          archwiki = {
            name = "ArchWiki";
            urls = [
              {
                template = "https://wiki.archlinux.org/index.php?title=Special%3ASearch&profile=default&fulltext=1&search={searchTerms}";
              }
            ];
            icon = "https://wiki.archlinux.org/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "aw" ];
          };

          searXng = {
            name = "SearxNG@brkn.lol";
            urls = [
              {
                template = "https://search.brkn.lol/search";
                method = "POST";
                params = [
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            icon = "https://search.brkn.lol/static/themes/simple/img/favicon.svg";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "sx" ];
          };

          bing.metaData.hidden = true;
          # builtin engines only support specifying one additional alias
          google.metaData.alias = "g";
          # what's the right id here? wikipedia?
          wikipedia.metaData.alias = "wiki";

          github = {
            name = "GitHub";
            urls = [ { template = "https://github.com/search?q={searchTerms}"; } ];
            icon = "https://github.com/fluidicon.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "gh" ];
          };

          youtube = {
            name = "YouTube";
            urls = [ { template = "https://www.youtube.com/results?search_query={searchTerms}"; } ];
            icon = "https://www.youtube.com/s/desktop/6ca9d352/img/favicon_144x144.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "y" ];
          };

          gmail = {
            name = "GMail";
            urls = [ { template = "https://mail.google.com/mail/u/0/#search/{searchTerms}"; } ];
            icon = "https://www.google.com/a/cpanel/schmitt.co/images/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "gm" ];
          };

          unduck = {
            name = "Unduck";
            urls = [ { template = "https://unduck.link?q={searchTerms}"; } ];
            icon = "https://unduck.link/search.svg";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "ud" ];
          };
        };
      };
    };
  };

  # NOTE Below is *only* for chromium, not google-chrome-stable!
  # programs.chromium.nativeMessagingHosts = with pkgs; [
  #   brotab
  #   native-client # external-application-button
  # ];

  # programs.google-chrome.nativeMessagingHosts for poor people
  xdg.configFile =
    let
      dest = "google-chrome/NativeMessagingHosts";
    in
    {
      # BroTab for Google Chrome
      "${dest}/brotab_mediator.json".source =
        "${pkgs.brotab}/lib/chromium/NativeMessagingHosts/brotab_mediator.json";
      # Native Addon (for open in firefox)
      "${dest}/com.add0n.node.json".source =
        "${pkgs.native-client}/lib/chromium/NativeMessagingHosts/com.add0n.node.json";
    };

  systemd.user.services.fx-cast = {
    Unit = {
      Description = "fx-cast-bridge";
      Documentation = "https://hensm.github.io/fx_cast/";
    };

    Service.ExecStart = "${pkgs.fx-cast-bridge}/bin/fx_cast_bridge -d";

    Install.WantedBy = [ "graphical-session.target" ];
  };
}

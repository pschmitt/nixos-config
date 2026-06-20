{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  bruvtabPkg = inputs.bruvtab.packages.${pkgs.stdenv.hostPlatform.system}.default;
  bruvtabFirefoxAddon = inputs.bruvtab.packages.${pkgs.stdenv.hostPlatform.system}.firefoxAddon;
  bruvtabChromeCrx = inputs.bruvtab.packages.${pkgs.stdenv.hostPlatform.system}.chromeCrx;
  bruvtabChromeExtensionId = lib.removeSuffix "\n" (
    builtins.readFile "${bruvtabChromeCrx}/extension-id"
  );
in
{
  options.custom.browser = {
    enable = lib.mkEnableOption "shared browser stack";

    systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        firefox
        chromium
      ];
      description = "System-wide browser packages to install.";
    };

    userPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [
        bruvtabPkg
        pkgs.tor-browser
        inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
      description = "User-level browser packages to install via Home Manager.";
    };

    firefox = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable Firefox.";
      };

      nativeMessagingHosts = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [
          bruvtabPkg
          fx-cast-bridge
          native-client
          tridactyl-native
        ];
        description = "Firefox native messaging host packages.";
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs.firefox-addons; [
          auto-tab-discard
          bitwarden
          bruvtabFirefoxAddon
          consent-o-matic
          don-t-fuck-with-paste
          external-application
          firefox-translations
          foxyproxy-standard
          french-dictionary
          fx_cast
          languagetool
          linkding-extension
          linkding-injector
          multi-account-containers
          refined-github
          re-enable-right-click
          single-file
          sponsorblock
          ublock-origin
          video-downloadhelper
          zoom-redirector
        ];
        description = "Firefox extension packages for the default profile.";
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "privacy.webrtc.legacyGlobalIndicator" = false;
          "privacy.webrtc.hideGlobalIndicator" = true;
          "browser.fixup.domainsuffixwhitelist.lan" = true;
          "browser.ml.chat.page" = false;
        };
        description = "Firefox about:config settings for the default profile.";
      };

      search = {
        default = lib.mkOption {
          type = lib.types.str;
          default = "Unduck";
          description = "Default Firefox search engine.";
        };

        engines = lib.mkOption {
          type = lib.types.attrs;
          default = {
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
              updateInterval = 24 * 60 * 60 * 1000;
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
              updateInterval = 24 * 60 * 60 * 1000;
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
              updateInterval = 24 * 60 * 60 * 1000;
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
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "sx" ];
            };

            bing.metaData.hidden = true;
            google.metaData.alias = "g";
            wikipedia.metaData.alias = "wiki";

            github = {
              name = "GitHub";
              urls = [ { template = "https://github.com/search?q={searchTerms}"; } ];
              icon = "https://github.com/fluidicon.png";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "gh" ];
            };

            youtube = {
              name = "YouTube";
              urls = [ { template = "https://www.youtube.com/results?search_query={searchTerms}"; } ];
              icon = "https://www.youtube.com/s/desktop/6ca9d352/img/favicon_144x144.png";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "y" ];
            };

            amazon-de = {
              name = "Amazon.de";
              urls = [ { template = "https://www.amazon.de/s?k={searchTerms}"; } ];
              icon = "https://www.amazon.de/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "am" ];
            };

            amazon-de-orders = {
              name = "Amazon.de Orders";
              urls = [ { template = "https://www.amazon.de/your-orders/search?search={searchTerms}"; } ];
              icon = "https://www.amazon.de/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "amo" ];
            };

            gmail = {
              name = "GMail";
              urls = [ { template = "https://mail.google.com/mail/u/0/#search/{searchTerms}"; } ];
              icon = "https://www.google.com/a/cpanel/schmitt.co/images/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "gm" ];
            };

            unduck = {
              name = "Unduck";
              urls = [ { template = "https://unduck.link?q={searchTerms}"; } ];
              icon = "https://unduck.link/search.svg";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "ud" ];
            };

            netbox = {
              name = "NetBox";
              urls = [ { template = "https://netbox.${config.domains.main}/search/?q={searchTerms}"; } ];
              icon = "https://netbox.${config.domains.main}/static/netbox_touch-icon-180.png";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "nb" ];
            };
          };
          description = "Firefox search engine definitions.";
        };
      };
    };

    chromium = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable Chromium.";
      };

      nativeMessagingHosts = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ bruvtabPkg ];
        description = "Chromium native messaging host packages.";
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [
          {
            id = "nngceckbapebfimnlniiiahkandclblb";
          }
          {
            id = bruvtabChromeExtensionId;
            crxPath = "${bruvtabChromeCrx}/bruvtab.crx";
            inherit (bruvtabPkg) version;
          }
          {
            id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
          }
        ];
        description = "Chromium extension definitions.";
      };
    };
  };
}

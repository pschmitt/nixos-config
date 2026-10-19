{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop.browser;
  linkdingExtensionId = "{61a05c39-ad45-4086-946f-32adb0a40a9d}";
  linkdingInjectorId = "{19561335-5a63-4b4e-8182-1eced17f9b47}";
  linkdingStorage = builtins.toJSON {
    ld_ext_config = builtins.toJSON {
      baseUrl = config.sops.placeholder."firefox/addons/linkding/url";
      token = config.sops.placeholder."firefox/addons/linkding/token";
    };
  };
  mkLinkdingFirefoxStorageTemplate = addonId: {
    path = "${config.programs.firefox.configPath}/default/browser-extension-data/${addonId}/storage.js";
    mode = "0600";
    content = linkdingStorage;
  };
in
{
  config = lib.mkMerge [
    {
      dotfiles.desktop.browser.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages =
        cfg.userPackages
        ++ lib.optional cfg.node.enable (
          pkgs.writeShellApplication {
            name = "firefox-browser-node";
            text = ''
              exec env MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1 ${lib.getExe config.programs.firefox.finalPackage} --marionette "$@"
            '';
          }
        );

      xdg.desktopEntries.firefox-browser-node = lib.mkIf cfg.node.enable {
        name = "Firefox (Browser Node Control)";
        genericName = "Web Browser";
        exec = "firefox-browser-node %U";
        icon = "firefox";
        terminal = false;
        categories = [
          "Network"
          "WebBrowser"
        ];
      };

      sops = {
        secrets = {
          "firefox/addons/linkding/url".sopsFile = config.host.sopsDefaultFile;
          "firefox/addons/linkding/token".sopsFile = config.host.sopsDefaultFile;
        };

        # programs.firefox.profiles.default.extensions.settings writes this same
        # storage.js path, but SOPS placeholders are only substituted in templates.
        templates = {
          "firefox-linkding-extension-storage" = mkLinkdingFirefoxStorageTemplate linkdingExtensionId;
          "firefox-linkding-injector-storage" = mkLinkdingFirefoxStorageTemplate linkdingInjectorId;
        };
      };

      programs.firefox = {
        enable = cfg.firefox.enable;
        configPath = "${config.xdg.configHome}/mozilla/firefox";
        inherit (cfg.firefox) nativeMessagingHosts policies;

        profiles.default = {
          extensions.packages = cfg.firefox.extensions;
          settings = cfg.firefox.settings;
          search = {
            force = true;
            default = cfg.firefox.search.default;
            engines = cfg.firefox.search.engines;
          };
        };
      };

      programs.chromium = {
        enable = cfg.chromium.enable;
        inherit (cfg.chromium)
          extensions
          nativeMessagingHosts
          ;
      };

      systemd.user.services.fx-cast = {
        Unit = {
          Description = "fx-cast-bridge";
          Documentation = "https://hensm.github.io/fx_cast/";
        };

        Service.ExecStart = "${pkgs.fx-cast-bridge}/bin/fx_cast_bridge -d";

        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
  ];
}

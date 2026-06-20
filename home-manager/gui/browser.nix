{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.browser;
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
      custom.desktop.browser.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages = cfg.userPackages;

      sops = {
        secrets = {
          "firefox/addons/linkding/url".sopsFile = ../../secrets/shared.sops.yaml;
          "firefox/addons/linkding/token".sopsFile = ../../secrets/shared.sops.yaml;
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
        inherit (cfg.firefox) nativeMessagingHosts;

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

{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop.browser;
  chromiumId =
    inputs.browser-daemon.packages.${pkgs.stdenv.hostPlatform.system}.chromium-addon.extensionId;
  rbwChromiumId = inputs.rbw.packages.${pkgs.stdenv.hostPlatform.system}.chromium-addon.extensionId;
in
{
  config = lib.mkMerge [
    {
      dotfiles.desktop.browser.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      # NOTE see also home-manager/gui/browser.nix
      programs.firefox = {
        enable = cfg.firefox.enable;
        inherit (cfg.firefox) policies;
      };

      environment.systemPackages = cfg.systemPackages;
      environment.etc."chromium/policies/managed/rbw.json".source =
        (pkgs.formats.json { }).generate "rbw-chromium-managed-policy.json"
          {
            "3rdparty".extensions.${rbwChromiumId}.allowHttpFill = true;
          };
    })
    (lib.mkIf (cfg.enable && cfg.node.enable) {
      assertions = [
        {
          assertion = cfg.node.allowlistMode != "auto" || cfg.node.discoveryOrigin != null;
          message = "dotfiles.desktop.browser.node.discoveryOrigin is required when allowlistMode is auto.";
        }
      ];
      environment.etc."chromium/policies/managed/browser-daemon-node.json".text = builtins.toJSON (
        {
          "3rdparty".extensions.${chromiumId} = {
            allowedDaemonOriginsMode = cfg.node.allowlistMode;
            # Named without asking when it pairs.
            defaultName = "${config.networking.hostName}-chromium";
          };
        }
        // lib.optionalAttrs (cfg.node.discoveryOrigin != null) {
          "3rdparty".extensions.${chromiumId}.daemonDiscoveryOrigin = cfg.node.discoveryOrigin;
        }
      );

      home-manager.users.${config.mainUser.username}.home.file.".mozilla/managed-storage/browser-daemon-node@pschmitt.dev.json" =
        {
          force = true;
          text = builtins.toJSON (
            {
              name = "browser-daemon-node@pschmitt.dev";
              description = "Allowed browser daemon origins";
              type = "storage";
              data = {
                allowedDaemonOriginsMode = cfg.node.allowlistMode;
                defaultName = "${config.networking.hostName}-firefox";
              };
            }
            // lib.optionalAttrs (cfg.node.discoveryOrigin != null) {
              data.daemonDiscoveryOrigin = cfg.node.discoveryOrigin;
            }
          );
        };
    })
  ];
}

# vim: set ft=nix et ts=2 sw=2 :

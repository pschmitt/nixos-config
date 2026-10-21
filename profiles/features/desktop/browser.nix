{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.desktop.browser;
  allowlist = config.sops.placeholder.${cfg.node.allowlistSecret};
  # Keep the array as a runtime SOPS substitution, outside the Nix store.
  runtimeJSON =
    value:
    builtins.replaceStrings [ (builtins.toJSON allowlist) ] [ allowlist ] (builtins.toJSON value);
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
    (lib.mkIf (cfg.enable && cfg.node.enable && cfg.node.allowlistSecret != null) {
      # SOPS creates missing parent directories as root. Home Manager also
      # writes Firefox managed storage, so these directories must be user-owned.
      systemd.tmpfiles.rules =
        map
          (
            directory:
            "d ${config.mainUser.homeDirectory}/${directory} 0755 ${config.mainUser.username} ${
              config.users.users.${config.mainUser.username}.group
            } - -"
          )
          [
            ".mozilla"
            ".mozilla/managed-storage"
          ];

      sops.templates = {
        "browser-node-chromium-policy" = {
          path = "/etc/chromium/policies/managed/browser-daemon-node.json";
          owner = "root";
          group = config.users.users.${config.mainUser.username}.group;
          mode = "0440";
          content = runtimeJSON {
            "3rdparty".extensions.${chromiumId} = {
              allowedDaemonOrigins = allowlist;
              # Named without asking when it pairs.
              defaultName = "${config.networking.hostName}-chromium";
            };
          };
        };
        "browser-node-firefox-policy" = {
          path = "${config.mainUser.homeDirectory}/.mozilla/managed-storage/browser-daemon-node@pschmitt.dev.json";
          owner = config.mainUser.username;
          mode = "0400";
          content = runtimeJSON {
            name = "browser-daemon-node@pschmitt.dev";
            description = "Allowed browser daemon origins";
            type = "storage";
            data = {
              allowedDaemonOrigins = allowlist;
              defaultName = "${config.networking.hostName}-firefox";
            };
          };
        };
      };
    })
  ];
}

# vim: set ft=nix et ts=2 sw=2 :

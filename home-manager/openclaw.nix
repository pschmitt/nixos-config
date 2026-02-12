{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  programs.openclaw = {
    enable = true;
    package = inputs.nix-openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
    stateDir = "${config.xdg.stateHome}/openclaw";
    installApp = false;
    # excludeTools = [
    #   "ffmpeg"
    #   "python3"
    # ];
    # bundledPlugins.goplaces.enable = false;
    config = {
      gateway = {
        mode = "local";
        auth = {
          mode = "token";
        };
      };
    };
  };

  sops = {
    secrets."openclaw/token" = {
      sopsFile = ../secrets/shared.sops.yaml;
    };

    templates.openclaw-gateway-env.content = ''
      OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder."openclaw/token"}
    '';
  };

  systemd.user.services.${config.programs.openclaw.systemd.unitName} =
    lib.mkIf config.programs.openclaw.enable
      {
        Service = {
          EnvironmentFile = [ config.sops.templates.openclaw-gateway-env.path ];
          StandardOutput = lib.mkForce "journal";
          StandardError = lib.mkForce "journal";
        };
      };

  home.packages = [
    (pkgs.writeShellScriptBin "openclaw-local" ''
      set -euo pipefail

      export OPENCLAW_STATE_DIR="${config.xdg.stateHome}/openclaw"
      export OPENCLAW_CONFIG_PATH="$OPENCLAW_STATE_DIR/openclaw.json"
      export OPENCLAW_GATEWAY_TOKEN="$(cat "${config.sops.secrets."openclaw/token".path}")"

      exec ${
        inputs.nix-openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway
      }/bin/openclaw "$@"
    '')
  ];
}

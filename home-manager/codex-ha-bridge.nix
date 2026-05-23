{ config, pkgs, ... }:
{
  sops.secrets."codex-ha-bridge/env".mode = "0600";

  systemd.user.services.codex-ha-bridge = {
    Unit = {
      Description = "Codex HA Bridge";
      After = [
        "network.target"
        "sops-nix.service"
      ];
    };
    Service = {
      ExecStart = "${pkgs.codex-ha-bridge}/bin/codex-ha-bridge";
      Environment = [ "CODEX_HOME=%h/.config/codex" ];
      EnvironmentFile = config.sops.secrets."codex-ha-bridge/env".path;
      Restart = "on-failure";
      RestartSec = "30s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

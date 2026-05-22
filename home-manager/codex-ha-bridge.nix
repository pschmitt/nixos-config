{ config, pkgs, ... }:
{
  sops.secrets."codex-ha-bridge/env".mode = "0600";

  systemd.user.services.codex-ha-bridge = {
    Unit = {
      Description = "Codex HA Bridge";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.codex-ha-bridge}/bin/codex-ha-bridge";
      EnvironmentFile = config.sops.secrets."codex-ha-bridge/env".path;
      Restart = "on-failure";
      RestartSec = "30s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

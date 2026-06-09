{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.codex-remote-control;

  codexHome =
    if cfg.configDir != null then cfg.configDir else "${config.home.homeDirectory}/.config/codex";

  codexBin = "${config.programs.codex.package}/bin/codex";
  codexStandaloneBin = "${codexHome}/packages/standalone/current/codex";

  codexRemoteControlStart = pkgs.writeShellScript "codex-remote-control-start" ''
    export CODEX_HOME=${lib.escapeShellArg codexHome}
    exec ${lib.escapeShellArg codexStandaloneBin} remote-control start
  '';
in
{
  options.services.codex-remote-control = {
    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override CODEX_HOME for the remote control service.";
    };
  };

  config = {
    home.activation.codex-remote-control-standalone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      codex_standalone_bin=${lib.escapeShellArg codexStandaloneBin}

      $DRY_RUN_CMD mkdir -p "$(dirname "$codex_standalone_bin")"
      $DRY_RUN_CMD ln -sfn ${lib.escapeShellArg codexBin} "$codex_standalone_bin"
    '';

    systemd.user.services.codex-remote-control = {
      Unit = {
        Description = "Codex remote control server";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${codexRemoteControlStart}";
        ExecStop = "${lib.escapeShellArg codexStandaloneBin} remote-control stop";
        WorkingDirectory = "%h";
        StandardInput = "null";
        StandardOutput = "append:${config.home.homeDirectory}/.local/state/codex-remote-control.log";
        StandardError = "journal";
        Environment = [ "CODEX_HOME=${codexHome}" ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}

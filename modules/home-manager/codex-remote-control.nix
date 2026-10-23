{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.codex-remote-control;

  codexHome = if cfg.configDir != null then cfg.configDir else "${config.xdg.configHome}/codex";

  codexBin = "${config.programs.codex.package}/bin/codex";
  codexStandaloneBin = "${codexHome}/packages/standalone/current/codex";

  codexRemoteControlStart = pkgs.writeShellScript "codex-remote-control-start" ''
    export CODEX_HOME=${lib.escapeShellArg codexHome}
    exec ${lib.escapeShellArg codexStandaloneBin} remote-control start
  '';

  codexRemoteControlRestart = pkgs.writeShellScript "codex-remote-control-restart" ''
    export CODEX_HOME=${lib.escapeShellArg codexHome}
    exec ${lib.escapeShellArg codexStandaloneBin} app-server daemon restart
  '';
in
{
  options.services.codex-remote-control = {
    enable = lib.mkEnableOption "the Codex remote-control daemon";

    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override CODEX_HOME for the remote control service.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.codex-remote-control-standalone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      codex_standalone_bin=${lib.escapeShellArg codexStandaloneBin}
      codex_standalone_target=$(readlink "$codex_standalone_bin" 2>/dev/null || :)

      $DRY_RUN_CMD mkdir -p "$(dirname "$codex_standalone_bin")"
      $DRY_RUN_CMD ln -sfn ${lib.escapeShellArg codexBin} "$codex_standalone_bin"

      if [[ "$codex_standalone_target" != ${lib.escapeShellArg codexBin} ]] &&
        systemctl --user is-active --quiet codex-remote-control.service
      then
        $DRY_RUN_CMD ${lib.escapeShellArg codexRemoteControlRestart}
      fi
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
        ExecStop = "${lib.escapeShellArg codexStandaloneBin} app-server daemon stop";
        # A restart can race a transient remote-control disconnect. Retry
        # failed starts so one connection error does not leave this
        # RemainAfterExit unit offline until the next activation.
        Restart = "on-failure";
        RestartSec = "30s";
        WorkingDirectory = "%h";
        StandardInput = "null";
        StandardOutput = "append:${config.xdg.stateHome}/codex-remote-control.log";
        StandardError = "journal";
        Environment = [ "CODEX_HOME=${codexHome}" ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}

{
  config,
  hostname ? null,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  cfg = config.services.claude-remote-control;

  effectiveHostname =
    if hostname != null then
      hostname
    else if osConfig != null then
      osConfig.networking.hostName
    else
      "unknown";

  # Use .claude-wrapped to bypass the HM wrapper that prepends --plugin-dir,
  # which remote-control does not accept as an argument.
  claudeBin = "${config.programs.claude-code.finalPackage}/bin/.claude-wrapped";

  claudeRemoteControlStart = pkgs.writeShellScript "claude-remote-control-start" ''
    ${lib.optionalString (cfg.configDir != null) ''
      export CLAUDE_CONFIG_DIR=${lib.escapeShellArg cfg.configDir}
      export ANTHROPIC_CONFIG_DIR="$CLAUDE_CONFIG_DIR"
    ''}
    exec ${claudeBin} remote-control \
      --name ${effectiveHostname}-svc \
      --permission-mode bypassPermissions
  '';
in
{
  options.services.claude-remote-control = {
    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override CLAUDE_CONFIG_DIR (and ANTHROPIC_CONFIG_DIR) for the remote control service.";
    };
  };

  config = {
    systemd.user.services.claude-remote-control = {
      Unit = {
        Description = "Claude Code remote control server";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${claudeRemoteControlStart}";
        Restart = "on-failure";
        RestartSec = "10s";
        WorkingDirectory = "%h";
        StandardInput = "null";
        StandardOutput = "append:${config.home.homeDirectory}/.local/state/claude-remote-control.log";
        StandardError = "journal";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}

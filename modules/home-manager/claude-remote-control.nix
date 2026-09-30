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
    # Pre-accept the workspace trust dialog for the working directory and the
    # one-time "Enable Remote Control? (y/n)" prompt; with stdin at /dev/null
    # the latter would otherwise make remote-control exit immediately.
    config_file="''${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
    if [[ -f "$config_file" ]]
    then
      tmp_file="$(mktemp "$config_file.XXXXXX")"
      ${pkgs.jq}/bin/jq --arg path ${lib.escapeShellArg cfg.workingDirectory} \
        '.remoteDialogSeen = true
         | .projects[$path] = ((.projects[$path] // {}) + { hasTrustDialogAccepted: true })' \
        "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
    fi

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

    workingDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/devel";
      description = ''
        Working directory for the remote control server. Must be a trusted
        workspace other than the home directory: claude refuses to run
        remote-control from $HOME since home-directory trust is never saved.
      '';
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
        Restart = "always";
        RestartSec = "10s";
        WorkingDirectory = cfg.workingDirectory;
        StandardInput = "null";
        StandardOutput = "append:${config.home.homeDirectory}/.local/state/claude-remote-control.log";
        StandardError = "journal";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}

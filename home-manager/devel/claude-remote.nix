{
  config,
  hostname,
  pkgs,
  ...
}:
let
  # Use .claude-wrapped to bypass the HM wrapper that prepends --plugin-dir,
  # which remote-control does not accept as an argument.
  claudeBin = "${config.programs.claude-code.finalPackage}/bin/.claude-wrapped";

  claudeRemoteControlStart = pkgs.writeShellScript "claude-remote-control-start" ''
    exec ${claudeBin} remote-control \
      --name ${hostname}-svc \
      --permission-mode bypassPermissions
  '';
in
{
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
}

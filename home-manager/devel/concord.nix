{
  lib,
  pkgs,
  ...
}:
let
  concord = lib.getExe' pkgs.concord-mcp "concord";
  concordMcp = lib.getExe' pkgs.concord-mcp "concord-mcp";

  # Mirrors what `concord setup --global` writes, minus the imperative parts:
  # user-level MCP (see ai.nix), lifecycle hooks that deliver messages from
  # other agents, and global mode itself (no per-repo files, state in
  # $XDG_DATA_HOME/concord/global.db).
  mcpFor = kind: {
    command = concordMcp;
    env.CONCORD_AGENT_KIND = kind;
  };

  copilotHook = event: timeout: {
    type = "command";
    bash = "${concord} hook ${event} --client copilot-cli";
    powershell = "${concord} hook ${event} --client copilot-cli";
    timeoutSec = timeout;
  };
in
{
  # The patched package keeps its user-level state in $XDG_DATA_HOME/concord.
  xdg.dataFile."concord/config.json".text = builtins.toJSON {
    globalMode = true;
    globalRegistrations = [ ];
  };

  # COPILOT_HOME is ~/.config/copilot.
  xdg.configFile."copilot/hooks/concord.json".text = builtins.toJSON {
    version = 1;
    hooks = {
      sessionStart = [ (copilotHook "session-start" 10) ];
      postToolUse = [ (copilotHook "post-tool-use" 5) ];
      agentStop = [ (copilotHook "stop" 5) ];
    };
  };

  # A reboot kills every agent session, but their claims stay `active` in
  # Concord and keep blocking other agents; nobody is left to release them.
  # Once per boot, release the claims of every workspace that nothing touched
  # since boot (the released tasks stay visible as `proposed`). An agent seen
  # after the boot, or a task updated since, is left alone, so it does not
  # matter that this runs at the first login rather than at boot.
  systemd.user.services.concord-boot-cleanup = {
    Unit.Description = "Release Concord claims left behind by agents killed in the last reboot";
    Service = {
      Type = "oneshot";
      WorkingDirectory = "%h";
      ExecStart = "${concord} release --stale-since-boot";
    };
    Install.WantedBy = [ "default.target" ];
  };

  programs = {
    # Per-agent identity: stops the MCP process from inheriting a parent
    # terminal's session variables (e.g. CLAUDE_CODE_SESSION_ID).
    antigravity-cli = {
      mcpServers.concord = mcpFor "antigravity";
      hooks.concord = {
        SessionStart = [ { command = "${concord} hook session-start --client antigravity"; } ];
        PreInvocation = [
          {
            command = "${concord} hook pre-invocation --client antigravity";
            timeout = 5;
          }
        ];
        Stop = [
          {
            command = "${concord} hook stop --client antigravity";
            timeout = 5;
          }
        ];
      };
    };

    github-copilot-cli.mcpServers.concord = mcpFor "copilot-cli" // {
      type = "local";
      tools = [ "*" ];
    };

    # Codex hooks are managed in modules/codex-managed-hooks.nix.
  };
}

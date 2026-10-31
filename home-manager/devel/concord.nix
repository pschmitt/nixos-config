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

    # Codex skips these silently until they are trusted once with /hooks.
    codex.settings.hooks = {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = "${concord} inbox register --from-hook --provider codex";
            }
          ];
        }
      ];
      PostToolUse = [
        {
          hooks = [
            {
              type = "command";
              command = "${concord} inbox drain --from-hook --provider codex --format post-tool-use";
            }
          ];
        }
      ];
      Stop = [
        {
          hooks = [
            {
              type = "command";
              command = "${concord} inbox drain --from-hook --provider codex --format stop";
            }
          ];
        }
      ];
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  aiMemory = pkgs.llm-agents.ai-memory;
  exe = lib.getExe aiMemory;
  dataDir = "${config.xdg.dataHome}/ai-memory";
  serverUrl = "https://ai-memory.${config.domains.main}";

  # The stdio bridge reads the bearer token from `<dataDir>/auth-token`, so no
  # token ever lands in an agent config.
  bridgeArgs = [
    "--data-dir"
    dataDir
    "mcp-bridge"
    "--server-url"
    serverUrl
  ];

  hookCommand =
    agent: event:
    "${exe} --data-dir ${dataDir} hook --event ${event} --agent ${agent} --server-url ${serverUrl}";

  # Claude Code and Codex share the hook schema; event names are kebab-case on
  # the command line.
  kebab = lib.replaceStrings (map (c: c) lib.upperChars) (map (c: "-${c}") lib.lowerChars);
  mkEventHooks =
    agent: events:
    lib.genAttrs events (event: [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = hookCommand agent (lib.removePrefix "-" (kebab event));
          }
        ];
      }
    ]);

  commonEvents = [
    "SessionStart"
    "UserPromptSubmit"
    "PreToolUse"
    "PostToolUse"
    "PreCompact"
    "Stop"
    "SessionEnd"
  ];

  agyCommand = event: {
    type = "command";
    command = hookCommand "antigravity-cli" event;
  };
in
{
  sops.secrets."ai-memory/auth-token" = {
    mode = "0600";
    sopsFile = config.host.sopsDefaultFile;
  };

  home = {
    packages = [ aiMemory ];

    file = {
      "${lib.removePrefix "${config.home.homeDirectory}/" dataDir}/auth-token".source =
        config.lib.file.mkOutOfStoreSymlink
          config.sops.secrets."ai-memory/auth-token".path;
    };
  };

  # CODEX_HOME is ~/.config/codex (see programs.codex).
  xdg.configFile."codex/hooks.json".text = builtins.toJSON {
    hooks = mkEventHooks "codex" commonEvents;
  };

  programs = {
    antigravity-cli.hooks.ai-memory = {
      PreToolUse = [
        {
          matcher = "";
          hooks = [ (agyCommand "pre-tool-use") ];
        }
      ];
      PostToolUse = [
        {
          matcher = "";
          hooks = [ (agyCommand "post-tool-use") ];
        }
      ];
      SessionStart = [ (agyCommand "session-start") ];
      PreInvocation = [ (agyCommand "pre-invocation") ];
      Stop = [ (agyCommand "stop") ];
    };

    mcp.servers.ai-memory = {
      command = exe;
      args = bridgeArgs ++ [ "--no-session-id" ];
    };

    claude-code = {
      settings.hooks = mkEventHooks "claude-code" (
        commonEvents
        ++ [
          "SubagentStart"
          "SubagentStop"
        ]
      );
      # Session-aware bridge: forwards CLAUDE_CODE_SESSION_ID.
      mcpServers.ai-memory = {
        command = exe;
        args = bridgeArgs;
      };
    };
  };
}

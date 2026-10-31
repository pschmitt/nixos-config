{
  config,
  lib,
  pkgs,
  ...
}:

let
  agentTmuxContextHook = pkgs.agent-tmux-context-hook;
  agentSecretGuard = pkgs.agent-secret-guard;
  agentSecretScan = pkgs.agent-secret-scan;
  concord = lib.getExe' pkgs.concord-mcp "concord";
  aiMemory = pkgs.llm-agents.ai-memory;
  aiMemoryDataDir = "${config.mainUser.homeDirectory}/.local/share/ai-memory";
  aiMemoryServerUrl = "https://ai-memory.${config.domains.main}";
  aiMemoryHook =
    event:
    "${lib.getExe aiMemory} --data-dir ${aiMemoryDataDir} hook --event ${event} --agent codex --server-url ${aiMemoryServerUrl}";
  hooksDir = pkgs.symlinkJoin {
    name = "codex-managed-hooks";
    paths = [
      agentSecretGuard
      agentSecretScan
      agentTmuxContextHook
      aiMemory
      pkgs.concord-mcp
    ];
  };
in
{
  environment.etc."codex/requirements.toml".text = ''
    [hooks]
    managed_dir = "${hooksDir}/bin"

    [[hooks.SessionStart]]
    [[hooks.SessionStart.hooks]]
    type = "command"
    command = "${aiMemoryHook "session-start"}"

    [[hooks.SessionStart.hooks]]
    type = "command"
    command = "${concord} inbox register --from-hook --provider codex"

    [[hooks.UserPromptSubmit]]
    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "${lib.getExe agentTmuxContextHook}"
    statusMessage = "Checking tmux pane"

    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "${aiMemoryHook "user-prompt-submit"}"

    [[hooks.PreToolUse]]
    matcher = "^Bash$"
    [[hooks.PreToolUse.hooks]]
    type = "command"
    command = "${lib.getExe agentSecretGuard}"
    statusMessage = "Checking for credential leaks"

    [[hooks.PreToolUse]]
    matcher = ""
    [[hooks.PreToolUse.hooks]]
    type = "command"
    command = "${aiMemoryHook "pre-tool-use"}"

    [[hooks.PostToolUse]]
    matcher = ".*"
    [[hooks.PostToolUse.hooks]]
    type = "command"
    command = "${lib.getExe agentSecretScan}"

    [[hooks.PostToolUse.hooks]]
    type = "command"
    command = "${aiMemoryHook "post-tool-use"}"

    [[hooks.PostToolUse.hooks]]
    type = "command"
    command = "${concord} inbox drain --from-hook --provider codex --format post-tool-use"

    [[hooks.PreCompact]]
    [[hooks.PreCompact.hooks]]
    type = "command"
    command = "${aiMemoryHook "pre-compact"}"

    [[hooks.Stop]]
    [[hooks.Stop.hooks]]
    type = "command"
    command = "${aiMemoryHook "stop"}"

    [[hooks.Stop.hooks]]
    type = "command"
    command = "${concord} inbox drain --from-hook --provider codex --format stop"

    [[hooks.SessionEnd]]
    [[hooks.SessionEnd.hooks]]
    type = "command"
    command = "${aiMemoryHook "session-end"}"
  '';
}

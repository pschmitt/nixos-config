{ lib, pkgs, ... }:

let
  agentTmuxContextHook = pkgs.agent-tmux-context-hook;
  agentSecretGuard = pkgs.agent-secret-guard;
  agentSecretScan = pkgs.agent-secret-scan;
  hooksDir = pkgs.symlinkJoin {
    name = "codex-managed-hooks";
    paths = [
      agentSecretGuard
      agentSecretScan
      agentTmuxContextHook
    ];
  };
in
{
  environment.etc."codex/requirements.toml".text = ''
    [hooks]
    managed_dir = "${hooksDir}/bin"

    [[hooks.UserPromptSubmit]]
    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "${lib.getExe agentTmuxContextHook}"
    statusMessage = "Checking tmux pane"

    [[hooks.PreToolUse]]
    matcher = "^Bash$"
    [[hooks.PreToolUse.hooks]]
    type = "command"
    command = "${lib.getExe agentSecretGuard}"
    statusMessage = "Checking for credential leaks"

    [[hooks.PostToolUse]]
    matcher = ".*"
    [[hooks.PostToolUse.hooks]]
    type = "command"
    command = "${lib.getExe agentSecretScan}"
  '';
}

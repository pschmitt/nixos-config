{ lib, pkgs, ... }:

let
  agentTmuxContextHook = pkgs.agent-tmux-context-hook;
in
{
  environment.etc."codex/requirements.toml".text = ''
    [hooks]
    managed_dir = "${agentTmuxContextHook}/bin"

    [[hooks.UserPromptSubmit]]
    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = "${lib.getExe agentTmuxContextHook}"
    statusMessage = "Checking tmux pane"
  '';
}

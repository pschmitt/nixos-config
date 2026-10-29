{
  writeShellApplication,
  jq,
  tmux,
}:

writeShellApplication {
  name = "agent-tmux-context-hook";
  runtimeInputs = [
    jq
    tmux
  ];
  text = builtins.readFile ../../../home-manager/devel/scripts/agent-tmux-context-hook.sh;
}

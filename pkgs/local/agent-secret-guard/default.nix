{ writeShellApplication, jq }:

writeShellApplication {
  name = "agent-secret-guard";
  runtimeInputs = [ jq ];
  text = builtins.readFile ../../../home-manager/devel/scripts/agent-secret-guard.sh;
}

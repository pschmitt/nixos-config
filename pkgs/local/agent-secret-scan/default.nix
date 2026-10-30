{ writeShellApplication, jq }:

writeShellApplication {
  name = "agent-secret-scan";
  runtimeInputs = [ jq ];
  text = builtins.readFile ../../../home-manager/devel/scripts/agent-secret-scan.sh;
}

{
  writeShellApplication,
  gitleaks,
  jq,
}:

writeShellApplication {
  name = "agent-secret-scan";
  runtimeInputs = [
    gitleaks
    jq
  ];
  runtimeEnv.AGENT_SECRET_SCAN_RULES = "${./gitleaks.toml}";
  text = builtins.readFile ../../../home-manager/devel/scripts/agent-secret-scan.sh;
}

{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "codex-plugin-cc";
  version = "1.0.6";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex-plugin-cc";
    rev = "db52e28f4d9ded852ab3942cea316258ae4ef346";
    hash = "sha256-S/R4kHTcIHBcG0TRX063C7ILXZZm0oMqunchPGg6ToU=";
  };

  dontBuild = true;

  # Only the plugin directory is installed: Claude Code loads it as a plugin
  # (commands, subagent, hooks) and the scripts run on the node from PATH.
  installPhase = ''
    runHook preInstall
    cp -r plugins/codex $out
    runHook postInstall
  '';

  meta = {
    description = "Codex plugin for Claude Code: code review and task delegation";
    homepage = "https://github.com/openai/codex-plugin-cc";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ pschmitt ];
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.resume;
  agents = lib.mapAttrs (_: agent: {
    inherit (agent) kind configDir resumeArgs;
    program =
      if agent.executable == null then
        lib.getExe agent.package
      else
        lib.getExe' agent.package agent.executable;
  }) cfg.agents;
  agentsFile = pkgs.writeText "resume-agents.json" (builtins.toJSON agents);
  python = pkgs.python3;
  resume = pkgs.writeShellApplication {
    name = "resume";
    runtimeInputs = [ python ];
    runtimeEnv.RESUME_AGENTS_CONFIG = toString agentsFile;
    text = ''
      exec ${python}/bin/python ${./scripts/resume.py} "$@"
    '';
  };
in
{
  options.programs.resume.agents = lib.mkOption {
    default = { };
    description = "Agent launch and session-discovery configuration for resume.";
    type = lib.types.attrsOf (
      lib.types.submodule (_: {
        options = {
          package = lib.mkOption {
            description = "Package that provides the agent executable.";
            type = lib.types.package;
          };
          executable = lib.mkOption {
            default = null;
            description = "Executable name within package; null uses meta.mainProgram.";
            type = lib.types.nullOr lib.types.str;
          };
          kind = lib.mkOption {
            description = "Session format to scan.";
            type = lib.types.enum [
              "claude"
              "codex"
              "agy"
            ];
          };
          configDir = lib.mkOption {
            description = "Agent configuration directory containing its sessions.";
            type = lib.types.str;
          };
          resumeArgs = lib.mkOption {
            description = "Arguments placed before the selected session ID when resuming.";
            type = lib.types.listOf lib.types.str;
          };
        };
      })
    );
  };

  config.home.packages = [ resume ];
}
